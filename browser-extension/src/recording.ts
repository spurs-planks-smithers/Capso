import {newCapture,saveDraft} from './core/index.ts';
import type {Asset} from './core/model.ts';
let owner:{tabId:number;windowId:number;origin:string;started:number;paused:boolean;stopped:boolean}|undefined;
let timer:ReturnType<typeof setInterval>|undefined,busy=false;
// A restarted worker cannot safely resume a prior in-memory recorder owner.
const recovery=(async()=>{if(await chrome.permissions.contains({permissions:['offscreen']})&&await chrome.offscreen.hasDocument())await chrome.offscreen.closeDocument();})();
export const recorderCall=(type:string,values:Record<string,unknown>={})=>chrome.runtime.sendMessage({target:'recorder',type,...values});
export async function recordingStatus():Promise<any>{await recovery;return owner?{...owner,...await recorderCall('status')}:{stopped:true,frames:[]};}
export async function startRecording(tabId:number):Promise<void>{
  await recovery;
  if(owner)throw Error('Stop or discard the current recording first.');
  if(!(await chrome.storage.local.get('recordingEnabled')).recordingEnabled)throw Error('Enable the recording trial first.');
  const tab=await chrome.tabs.get(tabId);if(!tab.url||!/^https?:/.test(tab.url))throw Error('Choose a website tab.');
  if(!await chrome.permissions.contains({permissions:['offscreen'],origins:[new URL(tab.url).origin+'/*']}))throw Error('Recording needs explicit site and offscreen permission.');
  await chrome.offscreen.createDocument({url:'offscreen.html',reasons:[chrome.offscreen.Reason.BLOBS],justification:'Hold only explicitly recorded masked frames in memory and encode selected evidence.'});
  owner={tabId,windowId:tab.windowId,origin:new URL(tab.url).origin,started:Date.now(),paused:false,stopped:false};
  try{await chrome.scripting.executeScript({target:{tabId},files:['content.js']});await chrome.tabs.sendMessage(tabId,{type:'nextshot-record-observe'});
    await recorderCall('event',{at:0,kind:'coverage',label:'Sampled visual recording, at most one frame per second. Changed pages can skip frames. Form fields and embedded frames are covered. No audio or typed values. Isolated-world page errors and completed resource URLs only. Console, request methods/status, failed requests, and embedded-frame activity are unavailable.'});
    timer=setInterval(()=>{void sampleRecording();},1000);await sampleRecording();
  }catch(e){await discardRecording();throw e;}
}
export async function pauseRecording(reason='Recording paused.'):Promise<void>{if(!owner||owner.stopped)return;owner.paused=true;await recorderCall('event',{at:Date.now()-owner.started,kind:'gap',label:reason});}
export async function resumeRecording():Promise<void>{if(!owner||owner.stopped)return;const tab=await chrome.tabs.get(owner.tabId);if(new URL(tab.url??'').origin!==owner.origin)throw Error('The site changed. Stop and start a new recording.');owner.paused=false;}
export async function stopRecording():Promise<void>{if(!owner)return;owner.stopped=true;while(busy)await new Promise(r=>setTimeout(r,20));if(timer)clearInterval(timer);timer=undefined;await chrome.tabs.sendMessage(owner.tabId,{type:'nextshot-record-cleanup'}).catch(()=>{});}
export async function discardRecording():Promise<void>{await stopRecording();owner=undefined;if(await chrome.permissions.contains({permissions:['offscreen']})&&await chrome.offscreen.hasDocument())await chrome.offscreen.closeDocument();}
export async function sampleRecording():Promise<void>{
  if(!owner||owner.paused||owner.stopped||busy)return;busy=true;const current=owner;
  try{
    const active=(await chrome.tabs.query({active:true,windowId:current.windowId}))[0];
    if(active?.id!==current.tabId){await pauseRecording('Tab switch. Frames are missing until Resume.');return;}
    const tab=await chrome.tabs.get(current.tabId);if(new URL(tab.url??'').origin!==current.origin){await pauseRecording('Site changed. Stop and re-arm on the new site.');return;}
    const proof=await chrome.tabs.sendMessage(current.tabId,{type:'nextshot-record-frame'});if(!proof?.proofId)throw Error('Snapshot unavailable');
    let switched=false;const activation=()=>{switched=true;};chrome.tabs.onActivated.addListener(activation);
    try{
      const image=await chrome.tabs.captureVisibleTab(current.windowId,{format:'png'}),confirmed=await chrome.tabs.sendMessage(current.tabId,{type:'nextshot-confirm-capture',proofId:proof.proofId});
      const activeNow=(await chrome.tabs.query({active:true,windowId:current.windowId}))[0];
      if(switched||!confirmed?.ok||activeNow?.id!==current.tabId||current!==owner||current.stopped)throw Error('Page changed during snapshot');
      await recorderCall('frame',{image,proof,at:Date.now()-current.started});
    }finally{chrome.tabs.onActivated.removeListener(activation);await chrome.tabs.sendMessage(current.tabId,{type:'nextshot-record-release'}).catch(()=>{});}
  }catch{if(owner===current)await recorderCall('event',{at:Date.now()-current.started,kind:'gap',label:'Frame skipped because capture-time privacy proof was unavailable.'}).catch(()=>{});}
  finally{busy=false;}
}
export async function recordObservedEvent(tabId:number,kind:string,label:string):Promise<void>{if(owner?.tabId!==tabId||owner.paused||owner.stopped||!['click','error','request'].includes(kind))return;await recorderCall('event',{at:Date.now()-owner.started,kind,label});}
export async function selectRecording(start:number,end:number,issue:number):Promise<string>{
  if(!owner||!owner.stopped)throw Error('Stop recording before selecting evidence.');
  if(!Number.isFinite(issue)||issue<start||issue>end)throw Error('Choose an issue frame within the selected range.');
  const selected=await recorderCall('select',{start,end,issue});if(selected.error)throw Error(selected.error);
  const tab=await chrome.tabs.get(owner.tabId),capture=newCapture({title:'Sampled recording',url:tab.url,width:selected.frame.width,height:selected.frame.height});
  capture.actions=selected.actions;capture.diagnostics=[{at:start,kind:'coverage',text:'Sampled visual evidence, at most one frame per second. Fields and embedded frames are covered. Gaps are possible. No audio or typed values. Console, request headers/bodies, methods/status, and complete network coverage are unavailable.'},...selected.diagnostics];capture.clip={start,end,issue,steps:selected.actions};
  const bytes=new Uint8Array(selected.frame.bytes),assets:Asset[]=[{name:capture.imageFile,mime:'image/jpeg',bytes},{name:capture.cleanImageFile,mime:'image/jpeg',bytes}];
  if(selected.media){capture.clip.mediaFile=`${capture.id}-selected.webm`;capture.clip.mime='video/webm';assets.push({name:capture.clip.mediaFile,mime:'video/webm',bytes:new Uint8Array(selected.media)});}
  await saveDraft({capture,assets});await discardRecording();return capture.id;
}
chrome.tabs.onRemoved.addListener(id=>{if(owner?.tabId===id)void discardRecording();});
chrome.tabs.onUpdated.addListener((id,change)=>{if(owner?.tabId===id&&change.status==='loading')void pauseRecording('Navigation gap. Resume only after checking the site.');});
chrome.permissions.onRemoved.addListener(()=>{if(owner)void discardRecording();});
