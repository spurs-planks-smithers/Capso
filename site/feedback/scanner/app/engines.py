"""Offline engines. Missing artifacts and incomplete scans always hold content."""
import hashlib
import io
import json
import math
import os
import re
import resource
import shutil
import subprocess
import tempfile
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from scan import CLASSIFIER_REVISION, POLICY_VERSION, ScanFailure, strict_json

MODEL_ID = 'meta-llama/Llama-Prompt-Guard-2-22M'
DATABASE_NAMES = {'main.cvd','daily.cvd','bytecode.cvd'}


def token_windows(ids):
    for start in range(0,max(1,len(ids)),446):
        yield ids[start:start+510]


def now_seconds(): return datetime.now(timezone.utc).timestamp()


def parse_time(value):
    try: return datetime.fromisoformat(value.replace('Z','+00:00')).timestamp()
    except (TypeError, ValueError, AttributeError) as error: raise ScanFailure('stale_signatures') from error


def child_limits():
    resource.setrlimit(resource.RLIMIT_CPU,(90,90))
    resource.setrlimit(resource.RLIMIT_FSIZE,(55_000_000,55_000_000))
    resource.setrlimit(resource.RLIMIT_NOFILE,(64,64))
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))


def command(args, timeout=40, input_data=None, temporary_root=None):
    try:
        return subprocess.run(args,input=input_data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                              timeout=timeout,check=False,preexec_fn=child_limits,
                              env={'PATH':'/usr/bin:/bin','LANG':'C.UTF-8','OMP_THREAD_LIMIT':'1','OMP_NUM_THREADS':'1',
                                   **({'TMPDIR':str(temporary_root)} if temporary_root is not None else {})})
    except (OSError, subprocess.TimeoutExpired) as error: raise ScanFailure('engine_unavailable') from error


class ProductionEngines:
    def __init__(self, model_dir='/opt/prompt-guard', definitions_dir='/tmp/definitions', temporary_root=None):
        self.model_dir=Path(model_dir); self.definitions_dir=Path(definitions_dir)
        self.temporary_root=Path(temporary_root) if temporary_root is not None else None
        self.definition_version=None; self.model=None; self.tokenizer=None

    def ready(self, manifest):
        if not shutil.which('clamscan') or not shutil.which('sigtool') or not shutil.which('tesseract'):
            raise ScanFailure('engine_unavailable')
        self.prepare_definitions(manifest)
        self.prepare_classifier()
        version=command(['clamscan','--version'],timeout=5)
        if version.returncode!=0: raise ScanFailure('engine_unavailable')
        engine=version.stdout.decode('ascii',errors='replace').strip()[:128]
        if not engine.startswith('ClamAV'): raise ScanFailure('engine_unavailable')
        return {'engine':engine,'definitionsAt':manifest['updatedAt'],
                'classifierRevision':CLASSIFIER_REVISION,'policyVersion':POLICY_VERSION}

    def prepare_definitions(self,manifest):
        if not isinstance(manifest,dict): raise ScanFailure('stale_signatures')
        updated=parse_time(manifest.get('updatedAt'))
        if not 0 <= now_seconds()-updated <= 24*3600: raise ScanFailure('stale_signatures')
        files=manifest.get('files')
        if not isinstance(files,list) or len(files)!=3 or {f.get('name') for f in files if isinstance(f,dict)}!=DATABASE_NAMES:
            raise ScanFailure('invalid_signature_manifest')
        version=hashlib.sha256(json.dumps(manifest,sort_keys=True).encode()).hexdigest()
        if version==self.definition_version: return
        self.definitions_dir.mkdir(mode=0o700,parents=True,exist_ok=True)
        for item in files:
            name=item['name']; digest=item.get('sha256'); size=item.get('bytes')
            if not isinstance(digest,str) or not re.fullmatch('[a-f0-9]{64}',digest) or type(size) is not int or not 1<=size<=300_000_000:
                raise ScanFailure('invalid_signature_manifest')
            target=self.definitions_dir/name
            if target.is_file() and target.stat().st_size==size and hashlib.sha256(target.read_bytes()).hexdigest()==digest: continue
            # The host is virtual. A Worker handler reads only immutable signature objects.
            url=f'http://signatures.nextshot.internal/{digest}/{name}'
            class NoRedirect(urllib.request.HTTPRedirectHandler):
                def redirect_request(self,*args): return None
            opener=urllib.request.build_opener(NoRedirect)
            try:
                with opener.open(url,timeout=30) as response, tempfile.NamedTemporaryFile(dir=self.definitions_dir,delete=False) as temporary:
                    pending=Path(temporary.name); received=0; hasher=hashlib.sha256()
                    while block:=response.read(1_048_576):
                        received+=len(block)
                        if received>size: raise ScanFailure('invalid_signature_database')
                        hasher.update(block); temporary.write(block)
                if received!=size or hasher.hexdigest()!=digest: raise ScanFailure('invalid_signature_database')
                verified=command(['sigtool','--info',str(pending)],timeout=30)
                if verified.returncode!=0 or b'Verification OK' not in verified.stdout:
                    raise ScanFailure('invalid_signature_database')
                pending.replace(target)
            except ScanFailure: raise
            except Exception as error: raise ScanFailure('signatures_unavailable') from error
            finally:
                if 'pending' in locals(): pending.unlink(missing_ok=True)
        self.definition_version=version

    def prepare_classifier(self):
        if self.model is not None: return
        try:
            manifest=strict_json((self.model_dir/'model-manifest.json').read_text())
            if manifest.get('model')!=MODEL_ID or manifest.get('revision')!=CLASSIFIER_REVISION:
                raise ScanFailure('classifier_artifact_mismatch')
            files=manifest.get('files')
            if not isinstance(files,dict) or not files or not any(name.endswith('.safetensors') for name in files):
                raise ScanFailure('classifier_artifact_mismatch')
            for name,digest in files.items():
                if '/' in name or '\\' in name or name.startswith('.') or not re.fullmatch('[a-f0-9]{64}',digest):
                    raise ScanFailure('classifier_artifact_mismatch')
                file=self.model_dir/name
                if file.is_symlink() or not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest()!=digest:
                    raise ScanFailure('classifier_artifact_mismatch')
            actual={p.name for p in self.model_dir.iterdir() if p.is_file() and p.name not in {'model-manifest.json','NOTICE.md'}}
            if actual!=set(files): raise ScanFailure('classifier_artifact_mismatch')
            os.environ.update({'HF_HUB_OFFLINE':'1','TRANSFORMERS_OFFLINE':'1','HF_HUB_DISABLE_TELEMETRY':'1'})
            import torch
            from transformers import AutoModelForSequenceClassification, AutoTokenizer
            torch.set_num_threads(1)
            self.tokenizer=AutoTokenizer.from_pretrained(str(self.model_dir),local_files_only=True,trust_remote_code=False)
            self.model=AutoModelForSequenceClassification.from_pretrained(str(self.model_dir),local_files_only=True,
                                                                         trust_remote_code=False,use_safetensors=True)
            self.model.eval()
        except ScanFailure: raise
        except Exception as error: raise ScanFailure('classifier_unavailable') from error

    def malware(self,data):
        self.malware_many([data])

    def malware_many(self,contents):
        if self.temporary_root is None or not self.temporary_root.is_dir():
            raise ScanFailure('job_directory_missing')
        if not isinstance(contents,list) or not contents or len(contents)>100 or any(not isinstance(data,bytes) for data in contents):
            raise ScanFailure('malware_scan_incomplete')
        if sum(len(data) for data in contents)>50_000_000:
            raise ScanFailure('malware_scan_incomplete')
        with tempfile.TemporaryDirectory(prefix='av-',dir=self.temporary_root) as folder:
            targets=[]
            for index,data in enumerate(contents,1):
                target=Path(folder)/f'input-{index}'
                target.write_bytes(data); targets.append(str(target))
            expected=set(targets)
            if not expected or len(expected)!=len(contents): raise ScanFailure('malware_scan_incomplete')
            # ClamAV counts internal format layers. The archive parser rejects nested archives.
            result=command(['clamscan','--database',str(self.definitions_dir),'--no-summary','--stdout',
                            '--max-filesize=50M','--max-scansize=50M','--max-files=100',
                            '--max-recursion=4','--max-scantime=30000','--alert-exceeds-max=yes',
                            '--alert-encrypted=yes','--tempdir',str(self.temporary_root),*targets],
                           timeout=40,temporary_root=self.temporary_root)
            output=result.stdout+result.stderr
            if result.returncode==1: raise ScanFailure('malware_detected')
            if result.returncode!=0 or any(term in output.lower() for term in
                    (b'warning',b'error',b'limit exceeded',b'not supported',b'skipped')):
                raise ScanFailure('malware_scan_incomplete')
            try: lines=[line for line in result.stdout.decode('utf-8',errors='strict').splitlines() if line]
            except UnicodeError as error: raise ScanFailure('malware_scan_incomplete') from error
            completed=[line[:-4] for line in lines if line.endswith(': OK')]
            if not completed or len(completed)!=len(expected) or set(completed)!=expected or len(lines)!=len(completed):
                raise ScanFailure('malware_scan_incomplete')

    def ocr(self,data):
        if self.temporary_root is None or not self.temporary_root.is_dir():
            raise ScanFailure('job_directory_missing')
        result=command(['tesseract','stdin','stdout','-l','eng','--psm','11'],timeout=20,input_data=data,temporary_root=self.temporary_root)
        if result.returncode!=0 or len(result.stdout)>100_000: raise ScanFailure('ocr_incomplete')
        try: return result.stdout.decode('utf-8',errors='strict')
        except UnicodeError as error: raise ScanFailure('ocr_incomplete') from error

    def classify(self,text):
        if self.model is None or self.tokenizer is None: raise ScanFailure('classifier_unavailable')
        import torch
        # Keep every token, including the tail. Windows overlap by 64 tokens.
        ids=self.tokenizer.encode(text,add_special_tokens=False,truncation=False)
        if len(ids)>100_000: raise ScanFailure('classifier_input_limit')
        detected=False
        for window in token_windows(ids):
            encoded=self.tokenizer.prepare_for_model(window,add_special_tokens=True,return_tensors='pt',truncation=False)
            if encoded['input_ids'].shape[-1]>512: raise ScanFailure('classifier_input_limit')
            with torch.inference_mode(): scores=torch.softmax(self.model(**encoded).logits,dim=-1)[0]
            labels={int(key):value.lower() for key,value in self.model.config.id2label.items()}
            malicious=[index for index,label in labels.items() if label in ('malicious','jailbreak','injection','label_1')]
            if len(malicious)!=1: raise ScanFailure('classifier_label_mismatch')
            if len(scores)!=len(labels) or not all(math.isfinite(float(value)) for value in scores):
                raise ScanFailure('classifier_output_invalid')
            if float(scores[malicious[0]])>=0.5: detected=True
        if detected: raise ScanFailure('prompt_injection')
