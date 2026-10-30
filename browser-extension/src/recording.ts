import {beginFrameContext,type FrameContext} from './frame-context.ts';
import {newCapture,saveDraft} from './core/index.ts';
import type {Asset} from './core/model.ts';
interface RecordingOwner {tabId:number;windowId:number;origin:string;started:number;paused:boolean;stopped:boolean;stopReason?:string;}
let owner:RecordingOwner|undefined;
let timer:ReturnType<typeof setInterval>|undefined,busy=false;
async function persistOwner():Promise<void>{
  if(owner)await chrome.storage.session.set({recordingOwner:owner});else await chrome.storage.session.remove('recordingOwner');
  await chrome.action.setBadgeText({text:!owner||owner.stopped?'':owner.paused?'II':'REC'});
  await chrome.action.setBadgeBackgroundColor({color:owner?.paused?'#815700':'#b02730'});
}
// Worker suspension preserves offscreen memory. Browser startup clears session metadata.
const recovery=(async()=>{
  const state=await chrome.storage.session.get(['recordingOwner','rollingOwner']);
  if(state.rollingOwner)return;
  const saved=state.recordingOwner as RecordingOwner|undefined;
  const exists=await chrome.permissions.contains({permissions:['offscreen']})&&await chrome.offscreen.hasDocument();
  if(saved&&exists){
    try{await chrome.tabs.get(saved.tabId);owner=saved;
      if(!owner.stopped){owner.paused=true;await persistOwner();await chrome.runtime.sendMessage({target:'recorder',type:'event',kind:'gap',label:'Recorder worker restarted. Resume to continue.'});}
      return;
    }catch{}
  }
  await chrome.storage.session.remove('recordingOwner');await chrome.action.setBadgeText({text:''});if(exists)await chrome.offscreen.closeDocument();
})();
chrome.runtime.onStartup.addListener(()=>{void recovery.then(()=>discardRecording());});
export const recorderCall=(type:string,values:Record<string,unknown>={})=>chrome.runtime.sendMessage({target:'recorder',type,...values});
export async function recordingStatus():Promise<any>{await recovery;return owner?{...owner,...await recorderCall('status')}:{stopped:true,frames:[]};}
export async function startRecording(tabId:number):Promise<void>{
  await recovery;
  if(owner||(await chrome.storage.session.get('rollingOwner')).rollingOwner)throw Error('Stop the current recording or Rolling Round first.');
  if(!(await chrome.storage.local.get('recordingEnabled')).recordingEnabled)throw Error('Enable the recording trial first.');
  const tab=await chrome.tabs.get(tabId);if(!tab.url||!/^https?:/.test(tab.url))throw Error('Choose a website tab.');
  if(!await chrome.permissions.contains({permissions:['offscreen'],origins:[new URL(tab.url).origin+'/*']}))throw Error('Recording needs explicit site and offscreen permission.');
  await chrome.offscreen.createDocument({url:'offscreen.html',reasons:[chrome.offscreen.Reason.BLOBS],justification:'Hold only explicitly recorded masked frames in memory and encode selected evidence.'});
  await recorderCall('configure',{rolling:false});
  owner={tabId,windowId:tab.windowId,origin:new URL(tab.url).origin,started:Date.now(),paused:false,stopped:false};
  await persistOwner();
  try{await chrome.scripting.executeScript({target:{tabId},files:['content.js']});await chrome.tabs.sendMessage(tabId,{type:'nextshot-record-observe'});
    await recorderCall('event',{at:0,kind:'coverage',label:'Sampled visual recording, at most one frame per second. Changed pages can skip frames. Form fields and embedded frames are covered. No audio or typed values. Isolated-world page errors and completed resource URLs only. Console, request methods/status, failed requests, and embedded-frame activity are unavailable.'});
    timer=setInterval(()=>{void sampleRecording();},1000);await sampleRecording();
  }catch(e){await discardRecording();throw e;}
}
export async function pauseRecording(reason='Recording paused.'):Promise<void>{await recovery;if(!owner||owner.stopped)return;owner.paused=true;await persistOwner();const result=await recorderCall('event',{kind:'gap',label:reason});if(result.full)void stopAtLimit();}
export async function resumeRecording():Promise<void>{await recovery;if(!owner||owner.stopped)return;const tab=await chrome.tabs.get(owner.tabId);if(new URL(tab.url??'').origin!==owner.origin)throw Error('The site changed. Stop and start a new recording.');await chrome.scripting.executeScript({target:{tabId:owner.tabId},files:['content.js']});await chrome.tabs.sendMessage(owner.tabId,{type:'nextshot-record-observe'});owner.paused=false;await persistOwner();if(!timer)timer=setInterval(()=>{void sampleRecording();},1000);}
const limitMessage='Recording stopped to preserve browser performance. Review the captured steps.';
async function stopAtLimit():Promise<void>{if(!owner||owner.stopped)return;owner.stopReason=limitMessage;await recorderCall('limit',{label:limitMessage});await stopRecording();}
export async function stopRecording():Promise<void>{await recovery;if(!owner)return;owner.stopped=true;await persistOwner();while(busy)await new Promise(r=>setTimeout(r,20));if(timer)clearInterval(timer);timer=undefined;await chrome.tabs.sendMessage(owner.tabId,{type:'nextshot-record-cleanup'}).catch(()=>{});}
export async function discardRecording():Promise<void>{await recovery;if(!owner)return;await stopRecording();owner=undefined;await persistOwner();if(await chrome.permissions.contains({permissions:['offscreen']})&&await chrome.offscreen.hasDocument())await chrome.offscreen.closeDocument();}
export async function sampleRecording():Promise<void>{
  if(!owner||owner.paused||owner.stopped||busy)return;busy=true;const current=owner;
  try{
    const active=(await chrome.tabs.query({active:true,windowId:current.windowId}))[0];
    if(active?.id!==current.tabId){await pauseRecording('Tab switch. Frames are missing until Resume.');return;}
    const tab=await chrome.tabs.get(current.tabId);if(new URL(tab.url??'').origin!==current.origin){await pauseRecording('Site changed. Stop and re-arm on the new site.');return;}
    const proof=await chrome.tabs.sendMessage(current.tabId,{type:'nextshot-record-frame'});if(!proof?.proofId)throw Error('Snapshot unavailable');
    let switched=false;const activation=()=>{switched=true;};chrome.tabs.onActivated.addListener(activation);
    let frames:FrameContext|undefined;
    try{
      frames=await beginFrameContext(current.tabId);
      const image=await chrome.tabs.captureVisibleTab(current.windowId,{format:'png'}),confirmed=await chrome.tabs.sendMessage(current.tabId,{type:'nextshot-confirm-capture',proofId:proof.proofId});
      const activeNow=(await chrome.tabs.query({active:true,windowId:current.windowId}))[0];
      if(switched||!confirmed?.ok||frames&&!await frames.confirm()||activeNow?.id!==current.tabId||current!==owner||current.stopped)throw Error('Page changed during snapshot');
      const retained=await recorderCall('frame',{image,proof:frames?{...proof,elements:frames.elements,privateRects:frames.privateRects}:proof});if(retained.full)void stopAtLimit();
    }finally{await frames?.release();chrome.tabs.onActivated.removeListener(activation);await chrome.tabs.sendMessage(current.tabId,{type:'nextshot-record-release'}).catch(()=>{});}
  }catch{if(owner===current){const result=await recorderCall('event',{kind:'gap',label:'Frame skipped because capture-time privacy proof was unavailable.'}).catch(()=>undefined);if(result?.full)void stopAtLimit();}}
  finally{busy=false;}
}
export async function recordObservedEvent(tabId:number,kind:string,label:string):Promise<void>{await recovery;if(owner?.tabId!==tabId||owner.paused||owner.stopped||!['click','error','request'].includes(kind))return;const result=await recorderCall('event',{kind,label});if(result.full)await stopAtLimit();}
export async function selectRecording(start:number,end:number,issue:number):Promise<string>{
  await recovery;
  if(!owner||!owner.stopped)throw Error('Stop recording before selecting evidence.');
  if(!Number.isFinite(issue)||issue<start||issue>end)throw Error('Choose an issue frame within the selected range.');
  const selected=await recorderCall('select',{start,end,issue});if(selected.error)throw Error(selected.error);
  const capture=newCapture({title:selected.frame.title||'Sampled recording',url:selected.frame.url,width:selected.frame.width,height:selected.frame.height});
  capture.elements=selected.frame.elements??[];capture.createdAt=selected.frame.capturedAt??capture.createdAt;
  capture.actions=selected.actions;capture.diagnostics=[{at:start,kind:'coverage',text:'Sampled visual evidence, at most one frame per second. Fields and embedded frames are covered. Gaps are possible. No audio or typed values. Console, request headers/bodies, methods/status, and complete network coverage are unavailable.'},...selected.diagnostics];capture.clip={start,end,issue,steps:selected.actions};
  const bytes=new Uint8Array(selected.frame.bytes),assets:Asset[]=[{name:capture.imageFile,mime:'image/jpeg',bytes},{name:capture.cleanImageFile,mime:'image/jpeg',bytes}];
  if(selected.media){capture.clip.mediaFile=`${capture.id}-selected.webm`;capture.clip.mime='video/webm';assets.push({name:capture.clip.mediaFile,mime:'video/webm',bytes:new Uint8Array(selected.media)});}
  await saveDraft({capture,assets});await discardRecording();return capture.id;
}
chrome.tabs.onRemoved.addListener(id=>{if(owner?.tabId===id)void discardRecording();});
chrome.tabs.onUpdated.addListener((id,change)=>{if(owner?.tabId===id&&change.status==='loading')void pauseRecording('Navigation gap. Resume only after checking the site.');});
chrome.permissions.onRemoved.addListener(()=>{if(owner)void discardRecording();});
