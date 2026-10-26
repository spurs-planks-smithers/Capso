import { owner, csrfToken, verifyCsrf } from './access.js';
import { esc, fail, IntakeError, isID, uploadBytes, response, LIMITS } from './policy.js';
import { query, submission, nowSeconds, audit, enqueue } from './store.js';
const page=(title,body)=>new Response(`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${esc(title)} | Nextshot</title><link rel="stylesheet" href="/feedback.css"><main class="page"><header><a href="/review">Nextshot feedback</a><a href="https://nextshot.dev">Nextshot.dev</a></header>${body}</main></html>`,{headers:{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'}});
export async function review(request,env){
  try{
    const claims=await owner(request,env),path=new URL(request.url).pathname;
    if(path==='/review'&&request.method==='GET'){
      const rows=(await query(env,'SELECT id,source,category,status,created_at,expires_at FROM submissions WHERE expires_at>? ORDER BY created_at DESC LIMIT 100',nowSeconds()).all()).results;
      return page('Review',`<h1>Feedback review</h1><p>All submitted material remains untrusted. Only rebuilt files from completed scans are available.</p><table><thead><tr><th>Received (UTC)</th><th>Channel</th><th>Category</th><th>Status</th><th>Receipt</th></tr></thead><tbody>${rows.map(r=>`<tr><td>${new Date(r.created_at*1000).toISOString()}</td><td>${esc(r.source)}</td><td>${esc(r.category)}</td><td>${esc(r.status)}</td><td><a href="/review/${r.id}">${r.id.slice(0,8)}</a></td></tr>`).join('')||'<tr><td colspan="5">No submissions.</td></tr>'}</tbody></table>`);
    }
    const match=path.match(/^\/review\/([^/]+)(?:\/(files|recheck)(?:\/([^/]+))?)?$/);if(!match||!isID(match[1]))fail('not_found',404);
    const [,id,action,fileID]=match,row=await submission(env,id);if(!row||row.expires_at<=nowSeconds())fail('not_found',404);
    if(action==='files'&&request.method==='GET'&&isID(fileID)){
      if(row.status!=='screened')fail('not_found',404);
      const file=await query(env,'SELECT * FROM derivatives WHERE id=? AND submission_id=?',fileID,id).first();if(!file)fail('not_found',404);
      const object=await env.REBUILT.get(file.storage_key);if(!object)fail('not_found',404);
      await audit(env,id,'read_rebuilt');
      return new Response(object.body,{headers:{'Content-Type':'image/jpeg','Content-Length':String(file.bytes),'Content-Disposition':`attachment; filename="${file.name}"`,'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'}});
    }
    if(action==='recheck'&&!fileID&&request.method==='POST'){
      const body=await uploadBytes(request.body,2048),form=new URLSearchParams(new TextDecoder().decode(body));await verifyCsrf(request,env,claims.sub,form.get('csrf'));
      const reasons=JSON.parse(row.reason_codes);const hard=/malware|archive|encrypted|traversal|symlink|invalid|limit|mismatch|signature|parse|missing|bomb|unsupported|type/i;
      if(row.status!=='held'||reasons.some(c=>hard.test(c)))fail('recheck_not_permitted',409);
      const changed=await query(env,"UPDATE submissions SET status='received',queued=0,reason_codes='[]',notified=0 WHERE id=? AND status='held' RETURNING id",id).first();if(changed){await audit(env,id,'request_recheck');try{await enqueue(env,id);}catch{}}
      return new Response(null,{status:303,headers:{Location:`/review/${id}`,'Cache-Control':'no-store'}});
    }
    if(action||request.method!=='GET')fail('not_found',404);
    const files=(await query(env,'SELECT id,name,bytes FROM derivatives WHERE submission_id=?',id).all()).results;
    const codes=JSON.parse(row.reason_codes),csrf=await csrfToken(env,claims.sub);
    return page('Submission',`<h1>Feedback ${id.slice(0,8)}</h1><p><strong>${esc(row.status)}</strong> | ${new Date(row.created_at*1000).toISOString()} | Expires ${new Date(row.expires_at*1000).toISOString()}</p><p>Contact (unverified): ${esc(row.contact_email||'not supplied')}</p>${codes.length?`<p>Findings: ${codes.map(esc).join(', ')}</p>`:''}<h2>Untrusted submitted text</h2><pre>${esc(row.status==='screened'?row.screened_text:row.message||'Content remains quarantined.')}</pre>${row.status==='screened'?`<h2>Rebuilt files</h2><ul>${files.map(f=>`<li><a href="/review/${id}/files/${f.id}">${esc(f.name)}</a> (${f.bytes.toLocaleString('en-US')} bytes)</li>`).join('')||'<li>No files.</li>'}</ul><h2>Private issue draft</h2><p>${esc(row.draft_status||'not ready')}. Review before copying. No issue is published.</p><pre>${esc(row.draft_json?JSON.stringify(JSON.parse(row.draft_json),null,2):'No draft is available.')}</pre>`:''}${row.status==='held'?`<form method="post" action="/review/${id}/recheck"><input type="hidden" name="csrf" value="${esc(csrf)}"><p>A recheck runs every required control again. It cannot bypass malware or file validation.</p><button>Request recheck</button></form>`:''}`);
  }catch(error){return response({error:error instanceof IntakeError?error.code:'review_unavailable'},error instanceof IntakeError?error.status:503);}
}
