export const CLIENT = 'nextshot-chrome-dev';
export const REDIRECT = 'https://ghmidcmcjigfckaiopacgpfaffofgjel.chromiumapp.org/jev';
export const MODEL = 'jev-1.14.0';
export const RESERVE = 2688;
export const ENDPOINT = 'https://api.typesafe.ai/v1/systemone';
export function keys(value, allowed) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(k => !allowed.includes(k))) throw Error('invalid');
}
export function text(v, max=512) {
  if(typeof v !== 'string' || !v.length || v.length>max || /[\u0000-\u001f]/.test(v)) throw Error('invalid');
  if(/https?:|www\.|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|Bearer\s|(?:sk|pk|api)[_-][A-Za-z0-9]{16,}/i.test(v))throw Error('sensitive');
  return v;
}
export function id(v) { if(!/^[A-Za-z0-9_-]{1,64}$/.test(text(v,64))) throw Error('invalid'); return v; }
export function validate(v) {
  keys(v,['version','purpose','requestID','selectionVersion','reviewerNote','consent','timeline','diagnostics','candidates']);
  if(v.version!==1 || !['steps','elements'].includes(v.purpose)) throw Error('invalid');
  id(v.requestID); id(v.selectionVersion);
  keys(v.consent,['reviewerText','pageData']);
  if(v.consent.reviewerText!==undefined && typeof v.consent.reviewerText!=='boolean')throw Error('invalid');
  if(v.reviewerNote!==undefined){text(v.reviewerNote,1024);if(v.consent.reviewerText!==true)throw Error('consent');}
  if(v.consent.pageData!==true) throw Error('consent');
  for(const [field,max,fields] of [['timeline',32,['id','kind','label','timeMs']],['diagnostics',8,['id','kind','summary']],['candidates',16,['id','role','label']]]) {
    if(!Array.isArray(v[field]) || v[field].length>max) throw Error('invalid');
    const ids=new Set();
    for(const row of v[field]) {
      keys(row,fields); if(fields.some(k=>!Object.hasOwn(row,k)))throw Error('invalid'); id(row.id); if(ids.has(row.id)) throw Error('invalid'); ids.add(row.id);
      for(const [k,value] of Object.entries(row)) if(k==='timeMs') {if(!Number.isInteger(value)||value<0||value>60000) throw Error('invalid');} else text(value);
    }
  }
  if(!(v.purpose==='steps'?v.timeline:v.candidates).length) throw Error('invalid');
  return v;
}
export function priceReady(e) {
 return e.BILLING_BOUND_VERIFIED==='true' && e.PRICING_MODEL===MODEL && e.INPUT_MICRODOLLARS_PER_MILLION==='42000' && e.MAX_BILLABLE_INPUT_TOKENS==='64000' && e.OUTPUT_MICRODOLLARS_PER_MILLION==='0';
}
export async function boundedJSON(request,max) {
 const reader=request.body?.getReader(); if(!reader) throw Error('invalid');
 const chunks=[];let size=0;
 try {while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>max)throw Error('size');chunks.push(value);}} finally {await reader.cancel().catch(()=>{});}
 const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}
 return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
}
export async function digest(s) {return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s)))].map(b=>b.toString(16).padStart(2,'0')).join('');}
export function random() {return btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');}
export function canonical(v) {if(Array.isArray(v))return '['+v.map(canonical).join(',')+']';if(v&&typeof v==='object')return '{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}';return JSON.stringify(v);}
