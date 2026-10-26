import { enabled, LIMITS, fail, validateScan, toBase64, fromBase64, digest } from './policy.js';
import { query, nowSeconds, submission, listFiles, reserveBudget, hold, enqueue, purgeExpired } from './store.js';
import { contextualScreen, issueDraft } from './models.js';
import { notifyScreened, notifyHeld } from './notify.js';
export async function processSubmission(env,id,scan) {
  const row=await submission(env,id);if(!row||row.expires_at<=nowSeconds()||row.status!=='received')return;
  if(!enabled(env,'PROCESSING_ENABLED')||!enabled(env,'AI_SCREENING_ENABLED')){await hold(env,id,['processing_unavailable']);return;}
  const lease=await query(env,"UPDATE submissions SET status='scanning',scan_lease_until=? WHERE id=? AND status='received' RETURNING id",nowSeconds()+180,id).first();if(!lease)return;
  try{
    const files=await listFiles(env,id);
    // Reserve a conservative charge before scanner and model calls. Unused reservations are not refunded.
    await reserveBudget(env,100000+files.filter(f=>f.role!=='email-original').length*25000+(files.some(f=>f.content_type==='application/zip')?150000:0));
    const inputs=[];
    for(const file of files){if(file.status!=='uploaded')fail('upload_missing',503);const object=await env.RAW.get(file.raw_key);if(!object||object.size!==file.bytes)fail('upload_missing',503);const data=new Uint8Array(await object.arrayBuffer());if(await digest(data)!==file.sha256)fail('upload_mismatch',503);inputs.push({id:file.id,contentType:file.content_type,bodyBase64:toBase64(data),...(file.role==='email-original'?{role:'email-original'}:{})});}
    const job={submission:{id,category:row.category,message:row.message,contactEmail:row.contact_email},files:inputs};
    const result=validateScan(await scan(env,job));
    if(result.status!=='passed'){await hold(env,id,result.reasonCodes,result.status==='rejected'?'rejected':'held');return;}
    const findings=await contextualScreen(env,result.inspectionText,result.images);
    if(findings.length){await hold(env,id,findings);return;}
    for(const image of result.images){const data=fromBase64(image.bodyBase64);if(await digest(data)!==image.sha256)fail('rebuilt_mismatch',503);const fileID=crypto.randomUUID(),key=`${id}/${fileID}.jpg`;await query(env,'INSERT INTO derivatives(id,submission_id,name,storage_key,bytes,sha256) VALUES(?,?,?,?,?,?)',fileID,id,image.name,key,data.length,image.sha256).run();await env.REBUILT.put(key,data,{httpMetadata:{contentType:'image/jpeg'}});}
    let draft=null,draftStatus='unavailable';
    try{
      const proposed=await issueDraft(env,result.text,result.images.map(i=>i.name));
      const output=JSON.stringify(proposed);
      const checked=validateScan(await scan(env,{submission:{id,category:row.category,message:output,contactEmail:''},files:[]}));
      if(checked.status==='passed'&&(await contextualScreen(env,output)).length===0){draft=proposed;draftStatus='ready';}else draftStatus='held';
    }catch{draftStatus='held';}
    await query(env,"UPDATE submissions SET status='screened',screened_text=?,draft_json=?,draft_status=?,scan_metadata=?,scan_lease_until=NULL,expires_at=created_at+? WHERE id=? AND status='scanning'",result.text,draft?JSON.stringify(draft):null,draftStatus,JSON.stringify(result.scan),LIMITS.screenedDays*86400,id).run();
    await notifyScreened(env,await submission(env,id));
  }catch(error){const codes=['processing_budget','stale_signatures'].includes(error?.code)?[error.code]:['screening_incomplete'];await hold(env,id,codes);}
}
export async function maintenance(env) {
  await purgeExpired(env);
  await query(env,"UPDATE submissions SET status='held',reason_codes='[\"scan_interrupted\"]',scan_lease_until=NULL,expires_at=MIN(expires_at,created_at+?) WHERE status='scanning' AND scan_lease_until<?",LIMITS.heldDays*86400,nowSeconds()).run();
  if(enabled(env,'PROCESSING_ENABLED')){
    const outbox=(await query(env,"SELECT id FROM submissions WHERE status='received' AND queued=0 AND expires_at>? LIMIT 20",nowSeconds()).all()).results;
    for(const row of outbox){try{await enqueue(env,row.id);}catch{break;}}
  }
  const notices=(await query(env,"SELECT * FROM submissions WHERE status='screened' AND notified=0 LIMIT 20").all()).results;
  for(const row of notices)await notifyScreened(env,row);
  await notifyHeld(env);
}
