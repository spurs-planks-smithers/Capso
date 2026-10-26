import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { api } from '../src/api.js';
import { processSubmission } from '../src/pipeline.js';
import { purgeExpired, query, reserveBudget, nowSeconds } from '../src/store.js';
import { digest, CLASSIFIER_REVISION } from '../src/policy.js';
import { review } from '../src/review.js';
function environment(){
 const sql=new DatabaseSync(':memory:');sql.exec(readFileSync(new URL('../schema.sql',import.meta.url),'utf8'));
 const statement=(text,args=[])=>({bind(...a){return statement(text,a);},async first(){return sql.prepare(text).get(...args)||null;},async all(){return {results:sql.prepare(text).all(...args)};},async run(){const out=sql.prepare(text).run(...args);return {meta:{changes:Number(out.changes)}};}});
 const DB={prepare:statement,async batch(statements){sql.exec('BEGIN');try{const out=[];for(const s of statements)out.push(await s.run());sql.exec('COMMIT');return out;}catch(e){sql.exec('ROLLBACK');throw e;}}};
 const bucket=()=>{const data=new Map();return {data,async put(key,body){data.set(key,new Uint8Array(body));},async get(key){const value=data.get(key);return value?{size:value.length,arrayBuffer:async()=>value.slice().buffer,body:new Response(value).body}:null;},async delete(key){data.delete(key);}};};
 const notices=[];
 return {DB,EDGE_LIMITER:{async limit(){return {success:true};}},RAW:bucket(),REBUILT:bucket(),INTAKE_SECRET:'test-only-secret-with-at-least-thirty-two-characters',INTAKE_ENABLED:'true',NATIVE_ENABLED:'true',PROCESSING_ENABLED:'true',AI_SCREENING_ENABLED:'true',NOTIFICATIONS_ENABLED:'true',JOBS:{sent:[],async send(value){this.sent.push(value);}},AI:{async run(){return {response:JSON.stringify({decision:'pass',reasons:[]})};}},CONTACT_NOTIFY:{async send(message){notices.push(message);}},notices,close:()=>sql.close()};
}
const request=(path,method='GET',value,token)=>new Request(`https://feedback.nextshot.dev${path}`,{method,headers:{'CF-Connecting-IP':'192.0.2.1',...(value&&!(value instanceof Uint8Array)?{'Content-Type':'application/json'}:{}),...(token?{Authorization:`Bearer ${token}`}:{})},...(value!==undefined?{body:value instanceof Uint8Array?value:JSON.stringify(value)}:{})});
async function reserve(env,data=[]){const payload={source:'native',category:'bug',message:'Save stays disabled.',idempotencyKey:crypto.randomUUID(),files:await Promise.all(data.map(async(bytes,n)=>({name:`capture-${n}.png`,bytes:bytes.length,sha256:await digest(bytes),contentType:'image/png'})))};const response=await api(request('/v1/reservations','POST',payload),env);assert.equal(response.status,201);return {payload,receipt:await response.json()};}
async function finish(env,receipt,data=[]){for(let n=0;n<data.length;n++){const res=await api(request(`/v1/submissions/${receipt.id}/files/${receipt.uploads[n].id}`,'PUT',data[n],receipt.token),env);assert.equal(res.status,200);}const res=await api(request(`/v1/submissions/${receipt.id}/complete`,'POST',undefined,receipt.token),env);assert.equal(res.status,202);}
const passed=text=>({version:1,status:'passed',reasonCodes:[],text,inspectionText:text,images:[],scan:{engine:'ClamAV',definitionsAt:new Date().toISOString(),classifierRevision:CLASSIFIER_REVISION,policyVersion:'1'}});
test('a complete native sequence can replay after a lost completion response without reopening files',async t=>{
 const env=environment();t.after(env.close);const data=[new Uint8Array([1,2,3]),new Uint8Array([4,5])],{payload,receipt}=await reserve(env,data);
 await finish(env,receipt,data);const before=Array.from(env.RAW.data.values(),v=>Array.from(v));
 const replay=await api(request('/v1/reservations','POST',payload),env);assert.equal(replay.status,200);assert.deepEqual(await replay.json(),receipt);
 await finish(env,receipt,data);assert.deepEqual(Array.from(env.RAW.data.values(),v=>Array.from(v)),before);assert.equal(env.JOBS.sent.length,1);
});
test('a changed idempotency payload and wrong upload bytes cannot replace a reservation',async t=>{
 const env=environment();t.after(env.close);const data=[new Uint8Array([1,2,3])],{payload,receipt}=await reserve(env,data);
 assert.equal((await api(request('/v1/reservations','POST',{...payload,message:'changed'}),env)).status,409);
 assert.equal((await api(request(`/v1/submissions/${receipt.id}/files/${receipt.uploads[0].id}`,'PUT',new Uint8Array([9,9,9]),receipt.token),env)).status,422);
 assert.equal(env.RAW.data.size,0);assert.equal((await api(request(`/v1/submissions/${receipt.id}/complete`,'POST',undefined,receipt.token),env)).status,409);
});
test('shared native admission rejects the sixth hourly submission even with spoofed app headers',async t=>{
 const env=environment();t.after(env.close);for(let n=0;n<5;n++)await reserve(env);
 const payload={source:'native',category:'other',message:'Question',idempotencyKey:crypto.randomUUID(),files:[]};const res=await api(request('/v1/reservations','POST',payload),env);assert.equal(res.status,429);
});
test('website messages require server Turnstile and a native source cannot skip its own launch gate',async t=>{
 const env=environment();t.after(env.close);const payload={source:'web',category:'other',message:'Question',idempotencyKey:crypto.randomUUID(),files:[]};assert.equal((await api(request('/v1/reservations','POST',payload),env)).status,403);
 env.NATIVE_ENABLED='false';assert.equal((await api(request('/v1/reservations','POST',{...payload,source:'native'}),env)).status,503);
});
test('scanner outages and incomplete model checks keep text and originals out of Gmail',async t=>{
 const env=environment();t.after(env.close);const {receipt}=await reserve(env);await finish(env,receipt);await processSubmission(env,receipt.id,async()=>{throw new Error('scanner unavailable');});
 const row=await query(env,'SELECT * FROM submissions WHERE id=?',receipt.id).first();assert.equal(row.status,'held');assert.equal(env.notices.length,0);assert.equal(env.REBUILT.data.size,0);
 const status=await api(request(`/v1/submissions/${receipt.id}`,'GET',undefined,receipt.token),env);assert.deepEqual(await status.json(),{id:receipt.id,status:'held'});
});
test('budget exhaustion stops processing before a scanner call',async t=>{
 const env=environment();t.after(env.close);const {receipt}=await reserve(env);await finish(env,receipt);await reserveBudget(env,35000000);let calls=0;await processSubmission(env,receipt.id,async()=>{calls++;return passed('text');});assert.equal(calls,0);assert.equal((await query(env,'SELECT status FROM submissions WHERE id=?',receipt.id).first()).status,'held');
});
test('completed screening permits reconstructed text only and suppresses malformed issue drafts',async t=>{
 const env=environment();t.after(env.close);const {receipt}=await reserve(env);await finish(env,receipt);await processSubmission(env,receipt.id,async()=>passed('Save stays disabled.'));
 const row=await query(env,'SELECT * FROM submissions WHERE id=?',receipt.id).first();assert.equal(row.status,'screened');assert.equal(row.draft_status,'held');assert.equal(env.notices.length,1);assert.equal(env.notices[0].to,'drewschulz1@gmail.com');assert.equal(env.notices[0].html,undefined);assert.equal(env.notices[0].attachments,undefined);assert.match(env.notices[0].text,/Save stays disabled/);
});
test('owner routes fail closed without Access configuration or valid identity',async t=>{
 const env=environment();t.after(env.close);assert.equal((await review(request('/review'),env)).status,503);env.ACCESS_TEAM_DOMAIN='team.cloudflareaccess.com';env.ACCESS_AUD='audience';assert.equal((await review(request('/review'),env)).status,401);
});
test('expiration removes originals, rebuilt files, content, drafts, and audit rows together',async t=>{
 const env=environment();t.after(env.close);const data=[new Uint8Array([1,2,3])],{receipt}=await reserve(env,data);await finish(env,receipt,data);
 await query(env,'INSERT INTO derivatives(id,submission_id,name,storage_key,bytes,sha256) VALUES(?,?,?,?,?,?)',crypto.randomUUID(),receipt.id,'capture-1.jpg','rebuilt-key',3,'a'.repeat(64)).run();await env.REBUILT.put('rebuilt-key',data[0]);await query(env,'INSERT INTO audit(submission_id,action,at) VALUES(?,?,?)',receipt.id,'read',nowSeconds()).run();await query(env,'UPDATE submissions SET expires_at=?,draft_json=? WHERE id=?',nowSeconds()-1,'private draft',receipt.id).run();
 assert.equal(await purgeExpired(env),1);assert.equal(env.RAW.data.size,0);assert.equal(env.REBUILT.data.size,0);assert.equal(await query(env,'SELECT * FROM submissions WHERE id=?',receipt.id).first(),null);assert.equal((await query(env,'SELECT * FROM audit').all()).results.length,0);
});
