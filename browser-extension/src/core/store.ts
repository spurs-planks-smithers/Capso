import {newRound} from './model.ts';
import type {Round,Capture,Asset,Draft} from './model.ts';
import {validateCapture,validateRound} from './validate.ts';
import {captureRound} from './bundle.ts';
import {safeFileName} from './sanitize.ts';

const databaseName='nextshot-browser-v1';
let database:Promise<IDBDatabase>|undefined;
function open():Promise<IDBDatabase> {
  return database??=new Promise((resolve,reject)=>{
    const request=indexedDB.open(databaseName,1);
    request.onupgradeneeded=()=>{for(const name of ['rounds','assets','state','drafts'])request.result.createObjectStore(name);};
    request.onsuccess=()=>resolve(request.result);request.onerror=()=>{database=undefined;reject(request.error);};
  });
}
function value<T>(request:IDBRequest<T>):Promise<T> {return new Promise((resolve,reject)=>{request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);});}
function complete(transaction:IDBTransaction):Promise<void> {return new Promise((resolve,reject)=>{transaction.oncomplete=()=>resolve();transaction.onerror=()=>reject(transaction.error);transaction.onabort=()=>reject(transaction.error??new Error('Save aborted'));});}
export async function rounds():Promise<Round[]> {
  const db=await open();const records=await value(db.transaction('rounds').objectStore('rounds').getAll());
  return records.map(validateRound).sort((a,b)=>b.createdAt.localeCompare(a.createdAt));
}
export async function roundById(id:string):Promise<Round|undefined> {
  const db=await open(),r=await value(db.transaction('rounds').objectStore('rounds').get(id));return r?validateRound(r):undefined;
}
export async function assetsForRound(round:Round):Promise<Asset[]> {
  const db=await open(),names=new Set(round.captures.flatMap(c=>[c.imageFile,c.cleanImageFile,...(c.clip?.mediaFile?[c.clip.mediaFile]:[])]));
  const rows=await Promise.all([...names].map(async name=>value<Asset|undefined>(db.transaction('assets').objectStore('assets').get(name))));
  if(rows.some(r=>!r))throw new Error('Some saved evidence is unavailable');return rows as Asset[];
}
export async function saveDraft(draft:Draft):Promise<void> {
  const capture=validateCapture(draft.capture),assets=referencedAssets(capture,draft.assets);const db=await open(),tx=db.transaction('drafts','readwrite'),done=complete(tx);tx.objectStore('drafts').put({capture,assets},capture.id);await done;
}
export async function getDraft(id:string):Promise<Draft|undefined> {const db=await open(),draft=await value<Draft|undefined>(db.transaction('drafts').objectStore('drafts').get(id));if(!draft)return;const capture=validateCapture(draft.capture);return {capture,assets:referencedAssets(capture,draft.assets)};}
export async function discardDraft(id:string):Promise<void> {const db=await open(),tx=db.transaction('drafts','readwrite'),done=complete(tx);tx.objectStore('drafts').delete(id);await done;}
export async function pruneDrafts(retained:string[]):Promise<void> {
  const db=await open(),tx=db.transaction('drafts','readwrite'),done=complete(tx),store=tx.objectStore('drafts');
  const keep=new Set(retained);for(const id of await value<IDBValidKey[]>(store.getAllKeys()))if(!keep.has(String(id)))store.delete(id);await done;
}
function validateAssets(assets:Asset[]):void {
  if(!assets.length||assets.length>100)throw new Error('Missing evidence assets');let total=0;const names=new Set();
  for(const a of assets){safeFileName(a.name);if(names.has(a.name)||!(a.bytes instanceof Uint8Array)||!['image/jpeg','image/png','image/webp','image/gif','video/webm','video/mp4'].includes(a.mime))throw new Error('Invalid evidence asset');names.add(a.name);total+=a.bytes.length;if(total>128*1024*1024)throw new Error('Evidence exceeds processing limit');}
}
function referencedAssets(capture:Capture,assets:Asset[]):Asset[] {
  const wanted=new Set([capture.imageFile,capture.cleanImageFile,...(capture.clip?.mediaFile?[capture.clip.mediaFile]:[])]);
  const selected=assets.filter(a=>wanted.has(a.name));validateAssets(selected);
  const names=new Set(selected.map(a=>a.name));for(const name of wanted)if(!names.has(name))throw new Error('Missing capture evidence');
  return selected;
}
async function fingerprint(capture:Capture,assets:Asset[]):Promise<string> {
  const entries=await Promise.all([...assets].sort((a,b)=>a.name.localeCompare(b.name)).map(async a=>{
    const digest=await crypto.subtle.digest('SHA-256',new Uint8Array(a.bytes).buffer);
    return [a.name,a.mime,...new Uint8Array(digest)].join(':');
  }));
  const bytes=new TextEncoder().encode(JSON.stringify(capture)+'\n'+entries.join('\n'));
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),n=>n.toString(16).padStart(2,'0')).join('');
}
export async function saveCapture(input:Capture,inputAssets:Asset[]):Promise<Round> {
  const capture=validateCapture(input),assets=referencedAssets(capture,inputAssets);
  const identity=await fingerprint(capture,assets);
  const db=await open(),tx=db.transaction(['rounds','assets','state','drafts'],'readwrite'),done=complete(tx);
  const store=tx.objectStore('rounds'),state=tx.objectStore('state');
  const existing=await value<Round[]>(store.getAll());
  const duplicate=existing.find(r=>r.captures.some(c=>c.id===capture.id));
  if(duplicate){
    const saved=duplicate.captures.find(c=>c.id===capture.id);
    const oldIdentity=await value<string|undefined>(state.get(`fingerprint:${capture.id}`));
    if(JSON.stringify(saved)!==JSON.stringify(capture)||oldIdentity!==identity){tx.abort();await done.catch(()=>{});throw new Error('Capture identity already saved with different evidence');}
    await done;return validateRound(duplicate);
  }
  let round:Round;
  if(capture.kind==='rolling')round=captureRound(capture);
  else {
    const activeId=await value<string|undefined>(state.get('activeRound'));
    round=existing.find(r=>r.id===activeId&&!r.endedAt)??newRound();
    round.captures.push(capture);state.put(round.id,'activeRound');
  }
  store.put(round,round.id);state.put(identity,`fingerprint:${capture.id}`);for(const a of assets)tx.objectStore('assets').put(a,a.name);tx.objectStore('drafts').delete(capture.id);await done;return round;
}
export async function endRound():Promise<void> {
  const db=await open(),tx=db.transaction(['state','rounds'],'readwrite'),done=complete(tx),state=tx.objectStore('state');
  const id=await value<string|undefined>(state.get('activeRound'));
  if(id){const store=tx.objectStore('rounds'),round=await value<Round|undefined>(store.get(id));if(round){round.endedAt=new Date().toISOString();store.put(round,id);}state.delete('activeRound');}
  await done;
}
