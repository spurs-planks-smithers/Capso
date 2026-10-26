"""Bounded, fail-closed ingestion. User files are data, never instructions."""
import base64
import binascii
import hashlib
import io
import json
import re
import stat
import unicodedata
import warnings
import zipfile
from dataclasses import dataclass
from pathlib import PurePosixPath

from PIL import Image, ImageOps, UnidentifiedImageError

POLICY_VERSION = '1'
CLASSIFIER_REVISION = '11614a155199674a0a95e6602d6ab0417b790ed0'


@dataclass(frozen=True)
class Limits:
    upload_bytes: int = 10_000_000
    email_bytes: int = 15_000_000
    expanded_bytes: int = 50_000_000
    entries: int = 100
    captures: int = 20
    image_pixels: int = 20_000_000
    total_pixels: int = 80_000_000
    text_bytes: int = 100_000
    response_bytes: int = 24_000_000


class ScanFailure(Exception):
    def __init__(self, reason, rejected=False):
        self.reason = reason
        self.rejected = rejected
        super().__init__(reason)


def strict_json(value):
    def pairs(items):
        result = {}
        for key, item in items:
            if key in result:
                raise ScanFailure('duplicate_json_key', True)
            result[key] = item
        return result
    try:
        return json.loads(value, object_pairs_hook=pairs,
                          parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
    except (ValueError, UnicodeError, RecursionError) as error:
        raise ScanFailure('invalid_json', True) from error


def bounded_string(value, maximum=100_000):
    if not isinstance(value, str) or len(value.encode('utf-8')) > maximum:
        raise ScanFailure('invalid_text', True)
    return value


def normalized(value):
    return ''.join(c for c in unicodedata.normalize('NFKC', value)
                   if unicodedata.category(c) != 'Cf')


def luhn(value):
    digits = [int(c) for c in value if c.isdecimal() and c.isascii()]
    if not 13 <= len(digits) <= 19 or len(set(digits)) < 2: return False
    total = 0
    for index, number in enumerate(reversed(digits)):
        if index % 2: number = number * 2 - (9 if number >= 5 else 0)
        total += number
    return total % 10 == 0


def sensitive_reasons(text):
    result = set()
    if any(unicodedata.category(c) == 'Cf' or (unicodedata.category(c) == 'Cc' and c not in '\n\r\t') for c in text):
        result.add('hidden_control_text')
    text = normalized(text)
    if re.search(r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----|\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[A-Z0-9]{16})\b', text):
        result.add('sensitive_credentials')
    if re.search(r'(?i)\b(?:password|passwd|api[_ -]?key|access[_ -]?token|client[_ -]?secret)\s*[:=]\s*[\"\']?[^\s\"\']{4,}', text):
        result.add('sensitive_credentials')
    if re.search(r'\b(?!000|666|9\d\d)\d{3}[- ](?!00)\d{2}[- ](?!0000)\d{4}\b', text):
        result.add('sensitive_government_id')
    if any(luhn(match.group()) for match in re.finditer(r'(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)', text)):
        result.add('sensitive_payment')
    if re.search(r'(?i)\b(?:medical record|patient name|patient id|diagnosis|health record|confidential|attorney.client privileged|internal use only)\b', text):
        result.add('sensitive_private_record')
    if re.search(r'(?i)\b(?:ignore|disregard|override)\b.{0,70}\b(?:previous|prior|system|developer)\b.{0,50}\b(?:instructions?|prompts?|rules?)\b|\b(?:reveal|print|exfiltrate)\b.{0,50}\b(?:system prompt|api key|credentials)\b', text, re.S):
        result.add('prompt_injection')
    if any(unicodedata.bidirectional(c) in {'RLO','LRO','RLE','LRE','PDF','RLI','LRI','FSI','PDI'} for c in text):
        result.add('hidden_control_text')
    return result


class Scanner:
    def __init__(self, engines, limits=Limits()):
        self.engines = engines
        self.limits = limits

    def scan(self, job):
        metadata = {'engine':'clamav','definitionsAt':None,
                    'classifierRevision':CLASSIFIER_REVISION,'policyVersion':POLICY_VERSION}
        try:
            state = ScanState(self.engines, self.limits)
            if not isinstance(job, dict) or not isinstance(job.get('submission'), dict):
                raise ScanFailure('invalid_job', True)
            submission = job['submission']
            message = bounded_string(submission.get('message', ''))
            files = job.get('files')
            if not isinstance(files, list) or len(files) > 21:
                raise ScanFailure('file_limit', True)
            decoded = []
            upload_bytes = 0
            raw_email_count = 0
            for file in files:
                if not isinstance(file, dict): raise ScanFailure('invalid_file', True)
                encoded = file.get('bodyBase64')
                if not isinstance(encoded, str) or len(encoded) > 20_000_000:
                    raise ScanFailure('upload_limit', True)
                try: data = base64.b64decode(encoded, validate=True)
                except (ValueError, binascii.Error) as error: raise ScanFailure('invalid_encoding', True) from error
                if file.get('role') == 'email-original':
                    raw_email_count += 1
                    if raw_email_count > 1 or file.get('contentType') != 'message/rfc822' or len(data) > self.limits.email_bytes:
                        raise ScanFailure('invalid_email_original', True)
                else:
                    upload_bytes += len(data)
                    if upload_bytes > self.limits.upload_bytes: raise ScanFailure('upload_limit', True)
                decoded.append((file, data))
            metadata = self.engines.ready(job.get('signatureManifest'))
            state.text(message, canonical=True)
            for file, data in decoded:
                self.engines.malware(data)
                if file.get('role') == 'email-original': continue
                if file.get('role') is not None: raise ScanFailure('unsupported_file_role', True)
                kind = file.get('contentType')
                if kind == 'application/zip': state.archive(data)
                elif kind in ('image/png','image/jpeg'): state.image(data, kind, emit=True)
                else: raise ScanFailure('unsupported_type', True)
            inspection = '\n'.join(state.inspection)
            reasons = sensitive_reasons(inspection)
            if reasons: raise ScanFailure(sorted(reasons)[0])
            self.engines.classify(inspection)
            result = {'version':1,'status':'passed','reasonCodes':[],
                      'text':'\n'.join(state.canonical),'inspectionText':inspection,
                      'images':state.images,'scan':metadata}
            if len(json.dumps(result).encode()) > self.limits.response_bytes:
                raise ScanFailure('rebuilt_output_limit')
            return result
        except ScanFailure as error:
            return {'version':1,'status':'rejected' if error.rejected else 'held',
                    'reasonCodes':[error.reason],'scan':metadata}
        except Exception:
            # Logs and the public result never contain parser details or user text.
            return {'version':1,'status':'held','reasonCodes':['scanner_error'],'scan':metadata}


class ScanState:
    def __init__(self, engines, limits):
        self.engines = engines; self.limits = limits
        self.inspection = []; self.canonical = []; self.images = []
        self.text_size = 0; self.pixels = 0; self.capture_count = 0
        self.expanded = 0; self.entry_count = 0

    def text(self, value, canonical=False):
        value = bounded_string(value, self.limits.text_bytes)
        self.text_size += len(value.encode('utf-8'))
        if self.text_size > self.limits.text_bytes: raise ScanFailure('text_limit', True)
        if value:
            self.inspection.append(value)
            if canonical: self.canonical.append(value)

    def image(self, data, kind, emit=False, dimensions=None):
        try:
            with warnings.catch_warnings():
                warnings.simplefilter('error', Image.DecompressionBombWarning)
                image = Image.open(io.BytesIO(data))
                expected = {'image/jpeg':'JPEG','image/png':'PNG'}[kind]
                if image.format != expected or getattr(image,'n_frames',1) != 1:
                    raise ScanFailure('image_type_mismatch', True)
                width, height = image.size
                if width < 1 or height < 1 or width * height > self.limits.image_pixels:
                    raise ScanFailure('image_pixel_limit', True)
                self.pixels += width * height
                if self.pixels > self.limits.total_pixels: raise ScanFailure('image_pixel_limit', True)
                if dimensions and (width,height) != dimensions: raise ScanFailure('image_dimensions_mismatch', True)
                metadata = []
                for value in image.info.values():
                    if isinstance(value,str): metadata.append(value)
                for value in image.getexif().values():
                    if isinstance(value,str): metadata.append(value)
                for value in metadata: self.text(value)
                image.verify()
                image = Image.open(io.BytesIO(data))
                image.load()
                image = ImageOps.exif_transpose(image).convert('RGB')
                image.thumbnail((1568,1568), Image.Resampling.LANCZOS)
                output = io.BytesIO()
                # No EXIF, ICC, PNG text, source name, or archive metadata survives.
                image.save(output, 'JPEG', quality=80, optimize=True)
                rebuilt = output.getvalue()
            self.text(self.engines.ocr(data))
            if emit:
                self.capture_count += 1
                if self.capture_count > self.limits.captures: raise ScanFailure('capture_limit', True)
                self.images.append({'name':f'capture-{self.capture_count}.jpg','contentType':'image/jpeg',
                                    'bodyBase64':base64.b64encode(rebuilt).decode(),
                                    'sha256':hashlib.sha256(rebuilt).hexdigest()})
        except ScanFailure: raise
        except (UnidentifiedImageError, OSError, ValueError, SyntaxError, Image.DecompressionBombError, Image.DecompressionBombWarning) as error:
            raise ScanFailure('invalid_image', True) from error

    def archive(self, data):
        try:
            if not data.startswith(b'PK\x03\x04') or len(data)<22 or data[-22:-18]!=b'PK\x05\x06':
                raise ScanFailure('invalid_archive',True)
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                if archive.comment: raise ScanFailure('archive_comment', True)
                entries = archive.infolist()
                self.entry_count += len(entries)
                if not entries or self.entry_count > self.limits.entries: raise ScanFailure('archive_entry_limit', True)
                members = {}; seen = set(); top = None
                for entry in entries:
                    name = entry.filename
                    path = PurePosixPath(name)
                    if (not name or '\\' in name or '\x00' in name or path.is_absolute()
                        or any(part in ('..','.') for part in name.split('/'))
                        or any(unicodedata.category(c) in ('Cc','Cf') for c in name)
                        or unicodedata.normalize('NFC',name) != name):
                        raise ScanFailure('unsafe_archive_path', True)
                    comparison = name.rstrip('/').casefold()
                    if comparison in seen: raise ScanFailure('duplicate_archive_path', True)
                    seen.add(comparison)
                    parts = path.parts
                    if len(parts) not in (1,2): raise ScanFailure('archive_structure', True)
                    top = parts[0] if top is None else top
                    if parts[0] != top: raise ScanFailure('archive_structure', True)
                    mode = entry.external_attr >> 16
                    if stat.S_ISLNK(mode) or (stat.S_IFMT(mode) and not (stat.S_ISREG(mode) or stat.S_ISDIR(mode))):
                        raise ScanFailure('archive_link', True)
                    if entry.flag_bits & 1: raise ScanFailure('encrypted_archive', True)
                    if entry.comment: raise ScanFailure('archive_comment', True)
                    if entry.compress_type not in (zipfile.ZIP_STORED,zipfile.ZIP_DEFLATED):
                        raise ScanFailure('unsupported_compression', True)
                    if entry.is_dir():
                        if len(parts) != 1: raise ScanFailure('archive_structure', True)
                        continue
                    if len(parts) != 2: raise ScanFailure('archive_structure', True)
                    suffix = path.suffix.lower()
                    if suffix not in ('.jpg','.jpeg','.png','.json','.md'):
                        raise ScanFailure('unsupported_archive_member', True)
                    self.expanded += entry.file_size
                    if entry.file_size < 0 or self.expanded > self.limits.expanded_bytes:
                        raise ScanFailure('expanded_limit', True)
                    maximum = self.limits.text_bytes if suffix in ('.json','.md') else self.limits.upload_bytes
                    if entry.file_size > maximum: raise ScanFailure('archive_member_limit', True)
                    with archive.open(entry) as stream:
                        content = stream.read(maximum + 1)
                        if len(content) != entry.file_size or stream.read(1): raise ScanFailure('archive_size_mismatch', True)
                    self.engines.malware(content)
                    members[parts[-1]] = content
                if 'support.json' in members:
                    self.support(members)
                elif 'feedback.json' in members:
                    self.standard(members)
                else: raise ScanFailure('unsupported_archive_schema', True)
        except ScanFailure: raise
        except (zipfile.BadZipFile, zipfile.LargeZipFile, RuntimeError, OSError, ValueError, EOFError) as error:
            raise ScanFailure('invalid_archive', True) from error

    def read_model(self, members, name):
        text = members[name].decode('utf-8', errors='strict')
        self.text(text)
        model = strict_json(text)
        if not isinstance(model, dict) or type(model.get('schemaVersion')) is not int or model['schemaVersion'] != 1:
            raise ScanFailure('unsupported_archive_schema', True)
        captures = model.get('captures')
        if not isinstance(captures,list) or not 1 <= len(captures) <= self.limits.captures:
            raise ScanFailure('capture_limit', True)
        indices = [capture.get('index') for capture in captures if isinstance(capture,dict)]
        if len(indices) != len(captures) or any(type(x) is not int or x < 1 for x in indices) or len(set(indices)) != len(indices):
            raise ScanFailure('invalid_capture_indices', True)
        return model

    def support(self, members):
        model = self.read_model(members, 'support.json')
        if set(model) - {'schemaVersion','app','note','contactEmail','captures','submissionID'}:
            raise ScanFailure('unexpected_support_field', True)
        app = model.get('app')
        if not isinstance(app,dict) or set(app) != {'version','build','channel','osVersion'}:
            raise ScanFailure('invalid_support_app', True)
        for value in app.values(): bounded_string(value,256)
        if model.get('note') is not None: self.text(model['note'],canonical=True)
        expected = {'support.json'}
        for capture in model['captures']:
            if set(capture) - {'index','imageFile','width','height','note','items'}:
                raise ScanFailure('unexpected_support_field', True)
            index = capture['index']; name = capture.get('imageFile')
            if name != f'capture-{index}.jpg': raise ScanFailure('invalid_support_image_name',True)
            expected.add(name)
            if name not in members: raise ScanFailure('missing_capture_image',True)
            dimensions = self.dimensions(capture.get('width'),capture.get('height'))
            self.image(members[name],'image/jpeg',True,dimensions)
            if capture.get('note') is not None: self.text(capture['note'],canonical=True)
            items = capture.get('items')
            if not isinstance(items,list) or len(items)>200: raise ScanFailure('invalid_items',True)
            ids = set()
            for item in items:
                if not isinstance(item,dict) or set(item) != {'id','instruction'}: raise ScanFailure('invalid_item',True)
                item_id = item.get('id')
                if not isinstance(item_id,str) or not re.fullmatch(rf'{index}\.[1-9][0-9]*',item_id) or item_id in ids:
                    raise ScanFailure('invalid_item_id',True)
                ids.add(item_id); self.text(f'{item_id}: {bounded_string(item["instruction"])}',canonical=True)
        if set(members) != expected: raise ScanFailure('unexpected_archive_member',True)

    @staticmethod
    def dimensions(width,height):
        if type(width) is not int or type(height) is not int or width<1 or height<1:
            raise ScanFailure('invalid_image_dimensions',True)
        return width,height

    def standard(self,members):
        model=self.read_model(members,'feedback.json')
        if set(model)-{'schemaVersion','name','slug','folderName','startedAt','endedAt','captures'}:
            raise ScanFailure('unexpected_export_field',True)
        for field in ('name','slug','folderName'): bounded_string(model.get(field),1000)
        if not isinstance(model.get('startedAt'),(str,int,float)):
            raise ScanFailure('invalid_export_date',True)
        expected={'feedback.json','README.md','manifest.md'}
        if not expected.issubset(members): raise ScanFailure('missing_export_file',True)
        for capture in model['captures']:
            if set(capture)-{'index','imageFile','cleanImageFile','size','capturedAt','sourceApp','windowTitle','note','ocrText','marks'}:
                raise ScanFailure('unexpected_export_field',True)
            if not isinstance(capture.get('capturedAt'),(str,int,float)):
                raise ScanFailure('invalid_export_date',True)
            index=capture['index']; image=capture.get('imageFile'); clean=capture.get('cleanImageFile')
            if not isinstance(image,str) or not re.fullmatch(rf'{index}-[^/]+\.jpg',image) or clean != image[:-4]+'-clean.jpg':
                raise ScanFailure('invalid_export_image_name',True)
            prompt=image[:-4]+'-prompt.md'; expected.update((image,clean,prompt))
            if not {image,clean,prompt}.issubset(members): raise ScanFailure('missing_export_file',True)
            size=capture.get('size')
            if not isinstance(size,dict): raise ScanFailure('invalid_image_dimensions',True)
            dimensions=self.dimensions(size.get('width'),size.get('height'))
            self.image(members[image],'image/jpeg',True,dimensions)
            self.image(members[clean],'image/jpeg',False,dimensions)
            if capture.get('note') is not None: self.text(capture['note'],True)
            marks=capture.get('marks')
            if not isinstance(marks,list) or len(marks)>1000: raise ScanFailure('invalid_marks',True)
            for mark in marks:
                if not isinstance(mark,dict) or set(mark)-{'kind','badge','box','point','textOnImage','ocrText','instruction'}:
                    raise ScanFailure('invalid_mark',True)
                if mark.get('kind') not in {'counter','rectangle','ellipse','arrow','line','freehand','text','pixelate','spotlight'}:
                    raise ScanFailure('invalid_mark',True)
                box=mark.get('box')
                if not isinstance(box,dict) or set(box)!={'x1','y1','x2','y2'} or any(type(v) is not int or abs(v)>10_000_000 for v in box.values()):
                    raise ScanFailure('invalid_mark',True)
                if mark.get('badge') is not None and (type(mark['badge']) is not int or mark['badge']<1):
                    raise ScanFailure('invalid_mark',True)
                if mark.get('instruction') is not None:
                    self.text(bounded_string(mark['instruction']),True)
        if set(members) != expected: raise ScanFailure('unexpected_archive_member',True)
        for name in sorted(expected):
            if name.endswith('.md'): self.text(members[name].decode('utf-8',errors='strict'))
