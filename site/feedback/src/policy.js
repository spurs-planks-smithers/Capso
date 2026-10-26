export const CLASSIFIER_REVISION = '11614a155199674a0a95e6602d6ab0417b790ed0';
export const LIMITS = Object.freeze({fileBytes:10_000_000, rawEmailBytes:15_000_000, textBytes:100_000, reservationBytes:125_000, files:20, reservationSeconds:600, signaturesSeconds:86400, screenedDays:90, heldDays:30});
export class IntakeError extends Error { constructor(code,status=400) { super(code); this.code=code; this.status=status; } }
export const fail=(code,status=400)=>{throw new IntakeError(code,status);};
export const enabled=(env,key)=>env[key]==='true';
export const bytes=text=>new TextEncoder().encode(text).byteLength;
export const hex=data=>Array.from(new Uint8Array(data),b=>b.toString(16).padStart(2,'0')).join('');
export const digest=async data=>hex(await crypto.subtle.digest('SHA-256',typeof data==='string'?new TextEncoder().encode(data):data));
export const isID=id=>typeof id==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(id);
export const isHash=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
export const email=value=>typeof value==='string'&&value.length<=254&&/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?\.[A-Za-z]{2,63}$/.test(value)&&!/[\r\n]/.test(value);
export function object(value,keys) { if (!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!keys.includes(k))) fail('invalid_fields'); return value; }
export function bounded(value,max=LIMITS.textBytes) { if(typeof value!=='string'||bytes(value)>max||value.includes('\0')) fail('invalid_text'); return value; }
export function validateReservation(input) {
  object(input,['source','category','message','contactEmail','idempotencyKey','files','turnstileToken']);
  if(!['web','native'].includes(input.source)||!['bug','feature','question','other'].includes(input.category)||!isID(input.idempotencyKey)) fail('invalid_submission');
  const message=bounded(input.message).trim();
  const contactEmail=input.contactEmail?.trim()||'';
  if(contactEmail&&!email(contactEmail)) fail('invalid_contact_email');
  if(!Array.isArray(input.files)||input.files.length>LIMITS.files) fail('invalid_files');
  let total=0;
  const files=input.files.map(file=>{
    object(file,['name','bytes','sha256','contentType']);
    if(typeof file.name!=='string'||!/^[\p{L}\p{N}][\p{L}\p{N}._ -]{0,159}$/u.test(file.name)||file.name.includes('..')) fail('invalid_filename');
    if(!Number.isSafeInteger(file.bytes)||file.bytes<1||file.bytes>LIMITS.fileBytes||!isHash(file.sha256)||!['image/png','image/jpeg','application/zip'].includes(file.contentType)) fail('invalid_file');
    total+=file.bytes;
    return {name:file.name,bytes:file.bytes,sha256:file.sha256,contentType:file.contentType};
  });
  if(total>LIMITS.fileBytes||(!message&&!files.length)||files.filter(f=>f.contentType==='application/zip').length>1||(files.some(f=>f.contentType==='application/zip')&&files.length!==1)) fail('invalid_files');
  return {source:input.source,category:input.category,message,contactEmail,idempotencyKey:input.idempotencyKey,files};
}
export async function uploadBytes(stream,max,timeoutMs=30000) {
  if(!stream) return new Uint8Array();
  const reader=stream.getReader(),chunks=[]; let length=0; const deadline=Date.now()+timeoutMs;
  try { while(true) { let timer;let part;try{part=await Promise.race([reader.read(),new Promise((_,reject)=>{timer=setTimeout(()=>reject(new IntakeError('upload_timeout',408)),Math.max(1,deadline-Date.now()));})]);}finally{clearTimeout(timer);}const {done,value}=part; if(done)break; length+=value.byteLength; if(length>max) { await reader.cancel(); fail('body_too_large',413); } chunks.push(value); } }
  catch(error){reader.cancel().catch(()=>{});throw error;}
  finally { reader.releaseLock(); }
  const out=new Uint8Array(length); let offset=0; for(const chunk of chunks){out.set(chunk,offset);offset+=chunk.byteLength;} return out;
}
export const toBase64=data=>{let text='';for(let i=0;i<data.length;i+=8192)text+=String.fromCharCode(...data.subarray(i,i+8192));return btoa(text);};
export function fromBase64(text) { if(typeof text!=='string'||text.length>20_000_000||text.length%4||!/^[A-Za-z0-9+/]*={0,2}$/.test(text)) fail('invalid_scan',503); try{return Uint8Array.from(atob(text),c=>c.charCodeAt(0));}catch{fail('invalid_scan',503);} }
export function validateScan(result,now=Date.now()) {
  object(result,['version','status','reasonCodes','text','inspectionText','images','scan']);
  if(result.version!==1||!['passed','held','rejected'].includes(result.status)||!Array.isArray(result.reasonCodes)||result.reasonCodes.length>20||result.reasonCodes.some(c=>typeof c!=='string'||!/^[-a-z0-9_]{1,64}$/.test(c))) fail('invalid_scan',503);
  if(result.status!=='passed') {if(!result.reasonCodes.length)fail('invalid_scan',503);return result;}
  if(result.reasonCodes.length||!result.scan||typeof result.scan.engine!=='string'||!/clamav/i.test(result.scan.engine)||result.scan.classifierRevision!==CLASSIFIER_REVISION||result.scan.policyVersion!=='1') fail('incomplete_scan',503);
  const at=Date.parse(result.scan.definitionsAt); if(!Number.isFinite(at)||at>now+300000||now-at>LIMITS.signaturesSeconds*1000) fail('stale_signatures',503);
  bounded(result.text);bounded(result.inspectionText);
  if(!Array.isArray(result.images)||result.images.length>20)fail('invalid_scan',503);
  const names=new Set();let total=0;
  for(const image of result.images){object(image,['name','contentType','bodyBase64','sha256']);if(!/^capture-[1-9][0-9]*\.jpg$/.test(image.name)||names.has(image.name)||image.contentType!=='image/jpeg'||!isHash(image.sha256))fail('invalid_scan',503);names.add(image.name);const data=fromBase64(image.bodyBase64);if(data.length<4||data[0]!==255||data[1]!==216||data[2]!==255)fail('invalid_scan',503);total+=data.length;}
  if(total>LIMITS.fileBytes)fail('rebuilt_too_large',503);return result;
}
export const publicReceipt=row=>({id:row.id,status:row.status});
export function safeText(input,max=100000) {
  return String(input||'').slice(0,max).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2060-\u206f]/g,'').replace(/https?:\/\//gi,v=>v.toLowerCase()==='https://'?'hxxps://':'hxxp://').replace(/\b([a-z0-9-]+)\.([a-z0-9.-]*[a-z][a-z0-9.-]*)(?=\b)/gi,(_,a,b)=>`${a}[.]${b.replaceAll('.','[.]')}`);
}
export function validDraft(value) {
  object(value,['title','category','reported','requested','steps','severity','captureReferences']);
  bounded(value.title,160);bounded(value.reported,6000);bounded(value.requested,6000);
  if(!value.title.trim()||!['bug','feature','question','other'].includes(value.category)||!['sev-blocker','sev-bug','sev-polish','sev-nit'].includes(value.severity)||!Array.isArray(value.steps)||value.steps.length>12||!Array.isArray(value.captureReferences)||value.captureReferences.length>20)fail('invalid_draft',503);
  value.steps.forEach(v=>bounded(v,500));value.captureReferences.forEach(v=>{if(typeof v!=='string'||!/^capture-[1-9][0-9]*\.jpg$/.test(v))fail('invalid_draft',503);});return value;
}
export function preliminaryFindings(text) {
  const codes=[];
  if(/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\b(?:sk-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16}|gh[pousr]_[A-Za-z0-9]{20,})\b/i.test(text))codes.push('credential');
  if(/\b\d{3}-\d{2}-\d{4}\b/.test(text))codes.push('government_identifier');
  if(/\bignore\s+(?:all\s+)?(?:previous|prior|system)\s+instructions\b|\b(?:reveal|print|exfiltrate)\s+(?:the\s+)?(?:system prompt|api key|passwords?)\b/i.test(text))codes.push('prompt_injection');
  return codes;
}
export const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function response(data,status=200,headers={}) { return new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store',...headers}}); }
