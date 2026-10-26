import test from 'node:test';
import assert from 'node:assert/strict';
import { validateReservation, validateScan, safeText, publicReceipt, uploadBytes, LIMITS, validDraft, CLASSIFIER_REVISION } from '../src/policy.js';
const request = () => ({source:'native',category:'other',message:'The Save button stays disabled.',idempotencyKey:crypto.randomUUID(),files:[]});
test('a useful anonymous message is accepted, but empty and oversized intake is rejected', () => {
  assert.equal(validateReservation(request()).source,'native');
  assert.throws(() => validateReservation({...request(),message:''}));
  assert.throws(() => validateReservation({...request(),message:'a'.repeat(100001)}));
  assert.throws(() => validateReservation({...request(),recipient:'victim@example.com'}));
});
test('file reservations bind exact bytes, hash, and permitted type', () => {
  const file = {name:'capture.png',bytes:100,sha256:'a'.repeat(64),contentType:'image/png'};
  assert.equal(validateReservation({...request(),files:[file]}).files.length,1);
  for (const changed of [{bytes:10000001},{sha256:'not a hash'},{contentType:'application/pdf'},{name:'../attack.png'}]) {
    assert.throws(() => validateReservation({...request(),files:[{...file,...changed}]}));
  }
});
test('malware and missing scan coverage never produce clearance', () => {
  assert.throws(() => validateScan({version:1,status:'passed',reasonCodes:[],text:'good',images:[]}));
  const result = {version:1,status:'passed',reasonCodes:[],text:'good',inspectionText:'good',images:[],scan:{engine:'ClamAV 1.4',definitionsAt:new Date().toISOString(),classifierRevision:CLASSIFIER_REVISION,policyVersion:'1'}};
  assert.equal(validateScan(result).status,'passed');
  assert.throws(() => validateScan({...result,reasonCodes:['malware']}));
  assert.throws(() => validateScan({...result,scan:{...result.scan,definitionsAt:'2020-01-01'}}));
  assert.throws(() => validateScan({...result,images:[{name:'evil.svg',contentType:'image/svg+xml',bodyBase64:'PHN2Zz4=',sha256:'a'.repeat(64)}]}));
});
test('byte limits use the actual stream rather than its content length', async () => {
  assert.equal((await uploadBytes(new Response(new Uint8Array(4)).body,4)).byteLength,4);
  await assert.rejects(uploadBytes(new Response(new Uint8Array(5)).body,4));
  assert.equal(LIMITS.fileBytes,10000000);
});
test('public receipts reveal no contact, text, findings, or storage keys', () => {
  assert.deepEqual(publicReceipt({id:'id',status:'held',message:'secret',reason_codes:'private_record',contact_email:'a@b.com',raw_key:'raw'}),{id:'id',status:'held'});
});
test('notification text defangs links and removes invisible control characters', () => {
  assert.equal(safeText('See https://evil.example/a\u202e'), 'See hxxps://evil[.]example/a');
});
test('issue drafts require bounded facts and a known severity', () => {
  const draft={title:'Save is disabled',category:'bug',reported:'Button stays disabled.',requested:'Enable Save.',steps:['Open capture.'],severity:'sev-blocker',captureReferences:[]};
  assert.equal(validDraft(draft).severity,'sev-blocker');
  assert.throws(() => validDraft({...draft,severity:'critical'}));
  assert.throws(() => validDraft({...draft,tools:[{name:'publish'}]}));
});
test('a stalled upload has a bounded read deadline',async()=>{
 const stream=new ReadableStream({start(){}});
 await assert.rejects(uploadBytes(stream,10,5),error=>error.code==='upload_timeout');
});
