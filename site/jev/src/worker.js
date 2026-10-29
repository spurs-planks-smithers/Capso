import {createRemoteJWKSet,jwtVerify} from 'jose';
import {CLIENT,REDIRECT,RESERVE,validate,priceReady,boundedJSON,digest,random,canonical} from './policy.js';
import {refine} from './provider.js';
const jwks=new Map();
const now=()=>Math.floor(Date.now()/1000);
function reply(body,status=200){return Response.json(body,{status,headers:{'Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff','Access-Control-Allow-Origin':'chrome-extension://ghmidcmcjigfckaiopacgpfaffofgjel','Access-Control-Allow-Headers':'Authorization, Content-Type','Access-Control-Allow-Methods':'GET, POST, OPTIONS'}});}
const fallback=(reason,status=200)=>reply({version:1,available:false,fallback:'local',reason},status);
function configured(e){return /^https:\/\/[a-z0-9.-]+$/.test(e.SERVICE_ISSUER??'')&&/^[a-z0-9-]+\.cloudflareaccess\.com$/.test(e.ACCESS_TEAM_DOMAIN??'')&&!!e.ACCESS_AUDIENCE;}
async function access(req,e){
 const token=req.headers.get('Cf-Access-Jwt-Assertion');if(!token)throw Error('denied');
 const issuer=`https://${e.ACCESS_TEAM_DOMAIN}`;
 if(!jwks.has(issuer))jwks.set(issuer,createRemoteJWKSet(new URL(issuer+'/cdn-cgi/access/certs'),{timeoutDuration:3000}));
 const {payload}=await jwtVerify(token,jwks.get(issuer),{issuer,audience:e.ACCESS_AUDIENCE,algorithms:['RS256'],requiredClaims:['sub','exp','iat']});
 const hash=await digest(issuer+'\n'+payload.sub);
 return e.DB.prepare('SELECT id FROM users WHERE identity_hash=? AND enabled=1').bind(hash).first();
}
async function session(req,e){
 const value=req.headers.get('Authorization')??'';if(!/^Bearer [A-Za-z0-9_-]{43}$/.test(value))return null;
 return e.DB.prepare('SELECT u.id,u.monthly_limit,s.hash,s.family FROM sessions s JOIN users u ON u.id=s.user_id JOIN families f ON f.id=s.family WHERE f.revoked=0 AND s.hash=? AND s.expires>? AND s.revoked=0 AND u.enabled=1 AND s.issuer=? AND s.audience=?').bind(await digest(value.slice(7)),now(),e.SERVICE_ISSUER,CLIENT).first();
}
async function issueTokens(e,userID,family,refreshExpires){
 const token=random(),refresh=random();
 await e.DB.batch([
  e.DB.prepare('INSERT INTO sessions(hash,user_id,issuer,audience,family,expires) VALUES(?,?,?,?,?,?)').bind(await digest(token),userID,e.SERVICE_ISSUER,CLIENT,family,now()+3600),
  e.DB.prepare('INSERT INTO refresh_tokens(hash,user_id,family,expires) VALUES(?,?,?,?)').bind(await digest(refresh),userID,family,refreshExpires)
 ]);
 return reply({access_token:token,refresh_token:refresh,token_type:'Bearer',expires_in:3600,scope:'jev:refine',issuer:e.SERVICE_ISSUER,audience:CLIENT});
}
async function revokeFamily(e,family){await e.DB.batch([e.DB.prepare('UPDATE families SET revoked=1 WHERE id=?').bind(family),e.DB.prepare('UPDATE sessions SET revoked=1 WHERE family=?').bind(family),e.DB.prepare('UPDATE refresh_tokens SET revoked=1 WHERE family=?').bind(family)]);}
export async function handle(req,e){
 const url=new URL(req.url);
 if(req.method==='OPTIONS')return reply({});
 if(!configured(e)||url.origin!==e.SERVICE_ISSUER)return fallback('unconfigured',503);
 if(url.pathname==='/auth/authorize'&&req.method==='GET'){
  const p=url.searchParams;
  if(p.get('client_id')!==CLIENT||p.get('redirect_uri')!==REDIRECT||p.get('response_type')!=='code'||p.get('code_challenge_method')!=='S256'||p.get('scope')!=='jev:refine'||!/^[A-Za-z0-9_-]{43}$/.test(p.get('code_challenge')??'')||!/^[A-Za-z0-9_-]{32,128}$/.test(p.get('state')??''))return fallback('invalid_authorization',400);
  const user=await access(req,e);if(!user)return fallback('denied',403);
  const code=random();await e.DB.prepare('INSERT INTO codes(hash,user_id,challenge,expires) VALUES(?,?,?,?)').bind(await digest(code),user.id,p.get('code_challenge'),now()+120).run();
  const redirect=new URL(REDIRECT);redirect.searchParams.set('code',code);redirect.searchParams.set('state',p.get('state'));redirect.searchParams.set('iss',e.SERVICE_ISSUER);
  return new Response(null,{status:302,headers:{Location:redirect.href,'Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
 }
 if(url.pathname==='/auth/token'&&req.method==='POST'){
  const p=await boundedJSON(req,2048);
  if(p.grant_type==='refresh_token'){
   if(p.client_id!==CLIENT || !/^[A-Za-z0-9_-]{43}$/.test(p.refresh_token??''))return fallback('invalid_grant',400);
   const hash=await digest(p.refresh_token);
   const row=await e.DB.prepare('UPDATE refresh_tokens SET used=1 WHERE hash=? AND used=0 AND revoked=0 AND family IN(SELECT id FROM families WHERE revoked=0) AND expires>? AND user_id IN(SELECT id FROM users WHERE enabled=1) RETURNING user_id,family,expires').bind(hash,now()).first();
   if(!row){const prior=await e.DB.prepare('SELECT family,used FROM refresh_tokens WHERE hash=?').bind(hash).first();if(prior?.used)await revokeFamily(e,prior.family);return fallback('invalid_grant',400);}
   return issueTokens(e,row.user_id,row.family,row.expires);
  }
  if(p.grant_type!=='authorization_code'||p.client_id!==CLIENT||p.redirect_uri!==REDIRECT||!/^[A-Za-z0-9_-]{43}$/.test(p.code??'')||!/^[A-Za-z0-9._~-]{43,128}$/.test(p.code_verifier??''))return fallback('invalid_grant',400);
  const hash=await digest(p.code_verifier);const challenge=btoa(String.fromCharCode(...Uint8Array.from(hash.match(/../g),x=>parseInt(x,16)))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
  const code=await e.DB.prepare('UPDATE codes SET used=1 WHERE hash=? AND used=0 AND expires>? AND challenge=? AND user_id IN(SELECT id FROM users WHERE enabled=1) RETURNING user_id').bind(await digest(p.code),now(),challenge).first();
  if(!code)return fallback('invalid_grant',400);
  const family=random();await e.DB.prepare('INSERT INTO families(id) VALUES(?)').bind(family).run();
  return issueTokens(e,code.user_id,family,now()+30*86400);
 }
 const user=await session(req,e);if(!user)return fallback('unauthorized',401);
 if(url.pathname==='/auth/revoke'&&req.method==='POST'){await revokeFamily(e,user.family);return reply({revoked:true});}
 const month=new Date().toISOString().slice(0,7);
 if(url.pathname==='/v1/availability'&&req.method==='GET'){
  const usage=await e.DB.prepare('SELECT COALESCE(SUM(reserved),0) AS used FROM requests WHERE user_id=? AND month=?').bind(user.id,month).first();
  const global=await e.DB.prepare('SELECT COALESCE(SUM(reserved),0) AS used FROM requests WHERE month=?').bind(month).first();
  const remainingRequests=Math.floor(Math.max(0,Math.min(user.monthly_limit-usage.used,25000000-global.used))/RESERVE);
  return reply({version:1,available:remainingRequests>0&&e.PROCESSING_ENABLED==='true'&&priceReady(e)&&!!e.TYPESAFE_API_KEY,remainingRequests});
 }
 if(url.pathname!=='/v1/refine'||req.method!=='POST')return fallback('not_found',404);
 const input=validate(await boundedJSON(req,24576));const contentDigest=await digest(canonical(input));
 const old=await e.DB.prepare('SELECT user_id,digest FROM requests WHERE request_id=?').bind(input.requestID).first();
 if(old)return fallback(old.user_id===user.id&&old.digest===contentDigest?'already_attempted':'request_conflict',old.user_id===user.id&&old.digest===contentDigest?200:409);
 if(e.PROCESSING_ENABLED!=='true'||!priceReady(e)||!e.TYPESAFE_API_KEY)return fallback('disabled');
 try{await e.DB.prepare('INSERT INTO requests(request_id,user_id,digest,month,reserved,created) VALUES(?,?,?,?,?,?)').bind(input.requestID,user.id,contentDigest,month,RESERVE,now()).run();}catch{return fallback('admission_denied');}
 try{
  const result=await refine(input,e.TYPESAFE_API_KEY);
  await e.DB.prepare("UPDATE requests SET status='complete' WHERE request_id=?").bind(input.requestID).run();
  return reply({version:1,available:true,requestID:input.requestID,selectionVersion:input.selectionVersion,purpose:input.purpose,candidates:result});
 }catch{await e.DB.prepare("UPDATE requests SET status='uncertain' WHERE request_id=?").bind(input.requestID).run();return fallback('upstream_unavailable');}
}
export default {async fetch(req,e){try{return await handle(req,e);}catch{return fallback('invalid_or_unavailable',400);}}};
