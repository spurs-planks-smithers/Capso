import { api } from './api.js';
import { review } from './review.js';
import { inbound } from './email.js';
import { processSubmission, maintenance } from './pipeline.js';
import { enabled, response } from './policy.js';
import { scan } from './container.js';
export { Scanner, ContainerProxy } from './container.js';
function protectedResponse(response){const out=new Response(response.body,response);out.headers.set('X-Content-Type-Options','nosniff');out.headers.set('Referrer-Policy','no-referrer');out.headers.set('X-Frame-Options','DENY');out.headers.set('X-Robots-Tag','noindex, nofollow');out.headers.set('Permissions-Policy','camera=(), microphone=(), geolocation=()');out.headers.set('Content-Security-Policy',"default-src 'self'; script-src 'self' https://challenges.cloudflare.com; frame-src https://challenges.cloudflare.com; connect-src 'self' https://challenges.cloudflare.com; img-src 'self' data:; style-src 'self'; font-src 'self'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; form-action 'self'");return out;}
export default {
  async fetch(request,env){
    const path=new URL(request.url).pathname;let result;
    if(path.startsWith('/v1/'))result=await api(request,env);
    else if(path==='/review'||path.startsWith('/review/'))result=await review(request,env);
    else if(path==='/config')result=response({enabled:enabled(env,'INTAKE_ENABLED'),turnstileSiteKey:env.TURNSTILE_SITE_KEY||'',maxFileBytes:10000000});
    else if(path==='/health')result=response({service:'nextshot-feedback',accepting:enabled(env,'INTAKE_ENABLED'),processing:enabled(env,'PROCESSING_ENABLED')});
    else if(['GET','HEAD'].includes(request.method))result=await env.ASSETS.fetch(request);
    else result=response({error:'not_found'},404);
    return protectedResponse(result);
  },
  async queue(batch,env){for(const message of batch.messages){const id=message.body?.id;if(typeof id!=='string'){message.ack();continue;}try{await processSubmission(env,id,scan);message.ack();}catch{message.retry({delaySeconds:60});}}},
  async scheduled(event,env,ctx){ctx.waitUntil(maintenance(env));},
  async email(message,env){await inbound(message,env);},
};
