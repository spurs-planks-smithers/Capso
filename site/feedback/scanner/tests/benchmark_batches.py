"""Real hard-phase benchmark. This does not approve a submission or bypass a model gate."""
import io
import json
import shutil
import sys
import tempfile
import time
import zipfile
from pathlib import Path
sys.path.insert(0,'/app')
from PIL import Image,ImageDraw,ImageFont
import engines as engine_module
from engines import ProductionEngines
from scan import ScanState,Limits,ScanFailure,sensitive_reasons

start=time.monotonic()
original_command=engine_module.command

def diagnostic_command(args,**kwargs):
    result=original_command(args,**kwargs)
    if result.returncode and args[0]=='clamscan':
        findings=[line.split(': ',1)[-1] for line in result.stdout.decode(errors='replace').splitlines() if 'FOUND' in line]
        print(json.dumps({'syntheticClamAVFindings':findings,'seconds':round(time.monotonic()-start,2)}),file=sys.stderr)
    return result

engine_module.command=diagnostic_command
with tempfile.TemporaryDirectory(prefix='nextshot-benchmark-') as folder:
    root=Path(folder); definitions=root/'definitions'; definitions.mkdir()
    manifest=json.loads(Path('/verified/manifest.json').read_text())
    for item in manifest['files']:
        shutil.copyfile(Path('/verified/definitions')/item['sha256']/item['name'],definitions/item['name'])
    class Measured(ProductionEngines):
        batches=0
        def malware_many(self,contents):
            self.batches+=1
            return super().malware_many(contents)
    engine=Measured(definitions_dir=definitions,temporary_root=root)
    engine.prepare_definitions(manifest)
    definitions_seconds=time.monotonic()-start
    image=Image.new('RGB',(1568,768),'white')
    ImageDraw.Draw(image).text((20,35),'Save button needs more width.',fill='black',font=ImageFont.load_default(size=28))
    encoded=io.BytesIO();image.save(encoded,'JPEG'); jpeg=encoded.getvalue()
    members={'README.md':b'Nextshot synthetic feedback export','manifest.md':b'Synthetic captures for component timing.'}
    captures=[]
    for index in range(1,21):
        name=f'{index}-synthetic.jpg'; clean=f'{index}-synthetic-clean.jpg'
        members[name]=jpeg;members[clean]=jpeg;members[f'{index}-synthetic-prompt.md']=b'Widen the save button.'
        captures.append({'index':index,'imageFile':name,'cleanImageFile':clean,'size':{'width':1568,'height':768},
                         'capturedAt':'2026-10-26T12:00:00Z','note':'Save button needs more width.',
                         'marks':[{'kind':'counter','badge':1,'box':{'x1':1,'y1':1,'x2':10,'y2':10},
                                   'instruction':'Widen the save button.'}]})
    model={'schemaVersion':1,'name':'synthetic','slug':'synthetic','folderName':'synthetic',
           'startedAt':'2026-10-26T12:00:00Z','captures':captures}
    members['feedback.json']=json.dumps(model).encode()
    archive=io.BytesIO()
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as output:
        for name,data in members.items():output.writestr('synthetic/'+name,data)
    phase_start=time.monotonic()
    engine.malware_many([archive.getvalue(),b'Save button needs more width.'])
    raw_seconds=time.monotonic()-phase_start
    phase_start=time.monotonic()
    state=ScanState(engine,Limits()); state.archive(archive.getvalue())
    member_decode_ocr_seconds=time.monotonic()-phase_start
    assert len(state.images)==20 and engine.batches==2
    assert not sensitive_reasons('\n'.join(state.inspection))
    hard_phase_seconds=time.monotonic()-start
    assert hard_phase_seconds<120,'The hard phase exceeds the job time budget.'
    eicar=(b'X5O!P%@AP[4\\PZX54(P^)7CC)7}'+b'$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*')
    try:engine.malware_many([b'Ordinary first member.',eicar])
    except ScanFailure as error:assert error.reason=='malware_detected'
    else:raise AssertionError('The last batch member did not trigger malware detection.')
    try:engine.prepare_classifier()
    except ScanFailure as error:
        assert error.reason=='classifier_unavailable'
        classifier='blocked_missing_approved_artifacts'
    else:classifier='available_not_benchmarked'
    print(json.dumps({'scope':'hard_phase_component_only','captures':20,'imageWidth':1568,'imageHeight':768,'archiveMembers':len(members),
          'coreAntivirusProcesses':2,'definitionsSeconds':round(definitions_seconds,2),
          'rawBatchSeconds':round(raw_seconds,2),'memberDecodeOCRSeconds':round(member_decode_ocr_seconds,2),
          'hardPhaseSeconds':round(hard_phase_seconds,2),'badLastMemberDetected':True,
          'classifier':classifier,'completeFeasibility':False}))
