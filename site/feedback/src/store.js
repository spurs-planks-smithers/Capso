import { digest, hex, fail, LIMITS } from './policy.js';
export const nowSeconds=()=>Math.floor(Date.now()/1000);
export const query=(env,sql,...args)=>env.DB.prepare(sql).bind(...args);
export async function hmac(secret,value) { if(typeof secret!=='string'||secret.length<32)fail('not_configured',503);const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);return hex(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(value))); }
export const submission=(env,id)=>query(env,'SELECT * FROM submissions WHERE id=?',id).first();
export const listFiles=async(env,id)=>(await query(env,'SELECT * FROM files WHERE submission_id=? ORDER BY ordinal,id',id).all()).results;
export const tokenFor=(env,id,key)=>hmac(env.INTAKE_SECRET,`upload:${id}:${key}`);
export async function authorized(env,id,request) { const token=request.headers.get('Authorization')?.match(/^Bearer ([a-f0-9]{64})$/)?.[1];if(!token)fail('not_found',404);const row=await submission(env,id);if(!row||await digest(token)!==row.token_hash)fail('not_found',404);if(row.expires_at<=nowSeconds())fail('not_found',404);return row; }
export async function increment(env,key,limit,expiresAt) { const row=await query(env,'INSERT INTO counters(key,value,expires_at) VALUES(?,1,?) ON CONFLICT(key) DO UPDATE SET value=value+1 WHERE value<? RETURNING value',key,expiresAt,limit).first();if(!row)fail('rate_limited',429);return row.value; }
export async function admission(env,identity,hasFiles,source) {
  const now=nowSeconds(),hour=Math.floor(now/3600),day=Math.floor(now/86400);
  await increment(env,`h:${source==='email'?'email:':''}${identity}:${hour}`,5,(hour+2)*3600);
  await increment(env,`d:${source==='email'?'email:':''}${identity}:${day}`,20,(day+2)*86400);
  await increment(env,`global:${day}`,100,(day+2)*86400);
  if(hasFiles){await increment(env,`fh:${identity}:${hour}`,2,(hour+2)*3600);await increment(env,`fd:${identity}:${day}`,10,(day+2)*86400);await increment(env,`files:${day}`,50,(day+2)*86400);}
  if(source==='email')await increment(env,`email:${hour}`,15,(hour+2)*3600);
}
export async function reserveBudget(env,microdollars) {
  const month=new Date().toISOString().slice(0,7);
  const row=await query(env,'INSERT INTO budget(month,reserved_microdollars) SELECT ?,? WHERE ?<=35000000 ON CONFLICT(month) DO UPDATE SET reserved_microdollars=reserved_microdollars+excluded.reserved_microdollars WHERE reserved_microdollars+excluded.reserved_microdollars<=35000000 RETURNING reserved_microdollars',month,microdollars,microdollars).first();
  if(!row)fail('processing_budget',503);return row.reserved_microdollars;
}
export async function hold(env,id,codes,status='held') {
  const row=await submission(env,id);if(!row)return;
  await query(env,"UPDATE submissions SET status=?,reason_codes=?,scan_lease_until=NULL,expires_at=MIN(expires_at,created_at+?) WHERE id=? AND status!='screened'",status,JSON.stringify(codes),LIMITS.heldDays*86400,id).run();
}
export async function audit(env,id,action) { await query(env,'INSERT INTO audit(submission_id,action,at) VALUES(?,?,?)',id,action,nowSeconds()).run(); }
export async function enqueue(env,id) {
  await env.JOBS.send({id});await query(env,"UPDATE submissions SET queued=1 WHERE id=? AND status='received'",id).run();
}
export async function purgeExpired(env) {
  const rows=(await query(env,'SELECT id FROM submissions WHERE expires_at<=? LIMIT 100',nowSeconds()).all()).results;
  for(const row of rows){
    const originals=await listFiles(env,row.id),rebuilt=(await query(env,'SELECT storage_key FROM derivatives WHERE submission_id=?',row.id).all()).results;
    for(const file of originals)await env.RAW.delete(file.raw_key);
    for(const file of rebuilt)await env.REBUILT.delete(file.storage_key);
    await env.DB.batch([query(env,'DELETE FROM audit WHERE submission_id=?',row.id),query(env,'DELETE FROM derivatives WHERE submission_id=?',row.id),query(env,'DELETE FROM files WHERE submission_id=?',row.id),query(env,'DELETE FROM submissions WHERE id=?',row.id)]);
  }
  await query(env,'DELETE FROM counters WHERE expires_at<=?',nowSeconds()).run();
  await query(env,'DELETE FROM budget WHERE month<?',new Date(Date.now()-100*86400000).toISOString().slice(0,7)).run();
  await query(env,'DELETE FROM audit WHERE at<?',nowSeconds()-90*86400).run();
  return rows.length;
}
