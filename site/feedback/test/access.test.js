import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import { owner, csrfToken, verifyCsrf } from '../src/access.js';
const env={ACCESS_TEAM_DOMAIN:'feedback-owner.cloudflareaccess.com',ACCESS_AUD:'expected-audience',INTAKE_SECRET:'test-secret-with-at-least-thirty-two-characters'};
test('owner identity verifies a real signed Access token and rejects wrong audience or email',async()=>{
 const {publicKey,privateKey}=await generateKeyPair('RS256'),jwk=await exportJWK(publicKey);jwk.kid='test-key';jwk.alg='RS256';const original=globalThis.fetch;globalThis.fetch=async url=>{assert.equal(String(url),'https://feedback-owner.cloudflareaccess.com/cdn-cgi/access/certs');return new Response(JSON.stringify({keys:[jwk]}));};
 try{const token=async(email,aud=env.ACCESS_AUD)=>new SignJWT({email}).setProtectedHeader({alg:'RS256',kid:'test-key'}).setSubject('owner-id').setIssuer('https://feedback-owner.cloudflareaccess.com').setAudience(aud).setIssuedAt().setExpirationTime('1m').sign(privateKey);const req=async(email,aud)=>new Request('https://feedback.nextshot.dev/review',{headers:{'Cf-Access-Jwt-Assertion':await token(email,aud)}});assert.equal((await owner(await req('drewschulz1@gmail.com'),env)).sub,'owner-id');await assert.rejects(owner(await req('other@gmail.com'),env));await assert.rejects(owner(await req('drewschulz1@gmail.com','wrong'),env));}finally{globalThis.fetch=original;}
});
test('owner mutations require a fresh subject-bound token and exact same origin',async()=>{
 const token=await csrfToken(env,'owner-id');await verifyCsrf(new Request('https://feedback.nextshot.dev/review',{headers:{Origin:'https://feedback.nextshot.dev'}}),env,'owner-id',token);
 await assert.rejects(verifyCsrf(new Request('https://feedback.nextshot.dev/review',{headers:{Origin:'https://evil.example'}}),env,'owner-id',token));
 await assert.rejects(verifyCsrf(new Request('https://feedback.nextshot.dev/review',{headers:{Origin:'https://feedback.nextshot.dev'}}),env,'someone-else',token));
});
