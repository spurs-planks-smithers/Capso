import { createRemoteJWKSet, jwtVerify } from 'jose';
import { fail } from './policy.js';
import { hmac, nowSeconds } from './store.js';
const keys=new Map();
export async function owner(request,env) {
  if(!/^[a-z0-9-]+\.cloudflareaccess\.com$/.test(env.ACCESS_TEAM_DOMAIN||'')||!env.ACCESS_AUD)fail('review_unavailable',503);
  const token=request.headers.get('Cf-Access-Jwt-Assertion');if(!token)fail('access_required',401);
  const issuer=`https://${env.ACCESS_TEAM_DOMAIN}`;
  if(!keys.has(issuer))keys.set(issuer,createRemoteJWKSet(new URL(`${issuer}/cdn-cgi/access/certs`),{timeoutDuration:5000,cooldownDuration:30000}));
  let payload;try{({payload}=await jwtVerify(token,keys.get(issuer),{issuer,audience:env.ACCESS_AUD,algorithms:['RS256'],requiredClaims:['exp','iat','sub','email'],clockTolerance:5}));}catch{fail('access_denied',403);}
  if(payload.email!=='drewschulz1@gmail.com')fail('access_denied',403);return payload;
}
export async function csrfToken(env,subject) {const time=nowSeconds();return `${time}.${await hmac(env.INTAKE_SECRET,`csrf:${subject}:${time}`)}`;}
export async function verifyCsrf(request,env,subject,token) {
  if(request.headers.get('Origin')!==new URL(request.url).origin||typeof token!=='string')fail('csrf_denied',403);
  const [time,signature,...rest]=token.split('.');if(rest.length||!/^\d{10}$/.test(time)||nowSeconds()-Number(time)>900||Number(time)>nowSeconds()||signature!==await hmac(env.INTAKE_SECRET,`csrf:${subject}:${time}`))fail('csrf_denied',403);
}
