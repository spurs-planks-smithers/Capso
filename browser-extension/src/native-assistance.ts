import type {JevSelection} from './jev-client.ts';
const HOST='com.drewschulz.nextshot.dev.browser';
export interface NativeSuggestion {available:boolean;ids:string[];}
function base64(bytes:Uint8Array):string {let result='';for(let at=0;at<bytes.length;at+=8192)result+=String.fromCharCode(...bytes.subarray(at,at+8192));return btoa(result);}
async function boundedMessage(message:object,signal:AbortSignal,timeout=30000):Promise<unknown>{
  if(signal.aborted)throw Error('canceled');
  let timer:ReturnType<typeof setTimeout>|undefined,cancel=()=>{};
  try{return await Promise.race([chrome.runtime.sendNativeMessage(HOST,message),new Promise<never>((_,reject)=>{cancel=()=>reject(Error('canceled'));signal.addEventListener('abort',cancel,{once:true});timer=setTimeout(()=>reject(Error('unavailable')),timeout);})]);}
  finally{if(timer)clearTimeout(timer);signal.removeEventListener('abort',cancel);}
}
/** Probe an already-running Dev app. Handshake and assist never launch the app. */
export async function nativeAssistance(selection:JevSelection,revision:number,issueAtMs:number|undefined,signal:AbortSignal):Promise<NativeSuggestion>{
  const unavailable={available:false,ids:[]};
  try{
    if(!await chrome.permissions.contains({permissions:['nativeMessaging']}))return unavailable;
    const ready=await boundedMessage({version:1,channel:'dev',operation:'handshake'},signal,8500) as {state?:string};
    if(ready?.state!=='ready'||signal.aborted)return unavailable;
    const request={version:1,requestID:selection.requestID,selectionVersion:revision,purpose:selection.purpose,...(issueAtMs!==undefined?{issueAt:issueAtMs/1000}:{}),timeline:selection.timeline.map(({id,timeMs,kind,label})=>({id,at:timeMs/1000,kind,label})),candidates:selection.candidates.map(({id,role,label})=>({id,role,label}))};
    const bytes=new TextEncoder().encode(JSON.stringify(request));if(bytes.length>32768)return unavailable;
    const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),n=>n.toString(16).padStart(2,'0')).join('');
    const reply=await boundedMessage({version:1,channel:'dev',operation:'assist',id:request.requestID,digest,payload:base64(bytes)},signal) as Record<string,unknown>;
    const allowed=new Set((selection.purpose==='steps'?selection.timeline:selection.candidates).map(row=>row.id));
    if(!reply||Object.keys(reply).some(k=>!['state','requestID','selectionVersion','capturedIDs','selectedIDs'].includes(k))||reply.state!=='refined'||reply.requestID!==request.requestID||reply.selectionVersion!==revision||!Array.isArray(reply.selectedIDs)||!Array.isArray(reply.capturedIDs)||reply.selectedIDs.length>12||new Set(reply.selectedIDs).size!==reply.selectedIDs.length||new Set(reply.capturedIDs).size!==allowed.size||reply.capturedIDs.length!==allowed.size||reply.capturedIDs.some(id=>typeof id!=='string'||!allowed.has(id))||reply.selectedIDs.some(id=>typeof id!=='string'||!allowed.has(id))||signal.aborted)return unavailable;
    return {available:true,ids:reply.selectedIDs as string[]};
  }catch{return unavailable;}
}
