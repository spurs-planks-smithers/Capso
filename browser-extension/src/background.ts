import {startRecording,pauseRecording,resumeRecording,stopRecording,discardRecording,recordingStatus,selectRecording,recordObservedEvent} from './recording.ts';
import {newCapture,saveDraft,discardDraft,pruneDrafts,sanitizeURL,sanitizeText,redactSensitive} from './core/index.ts';
import type {Capture,ElementEvidence} from './core/model.ts';

async function draftAssociations():Promise<Record<string,string>> {return ((await chrome.storage.session.get('draftTabs')).draftTabs??{}) as Record<string,string>;}
async function cleanDrafts():Promise<void> {
  const tabs=await chrome.tabs.query({}),live=new Set(tabs.map(t=>String(t.id))),associations=await draftAssociations();
  for(const tab of Object.keys(associations))if(!live.has(tab))delete associations[tab];
  await chrome.storage.session.set({draftTabs:associations});await pruneDrafts(Object.values(associations));
}
chrome.runtime.onStartup.addListener(()=>{void cleanDrafts();});
chrome.runtime.onInstalled.addListener(()=>{void chrome.storage.local.setAccessLevel({accessLevel:'TRUSTED_CONTEXTS'});});
async function inject(tabId:number):Promise<void> {await chrome.scripting.executeScript({target:{tabId},files:['content.js']});}
async function startCapture(tabId:number):Promise<void> {
  const tab=await chrome.tabs.get(tabId);
  if(!tab.url||!/^https?:/.test(tab.url))throw new Error('Choose a website tab to capture.');
  await inject(tabId);await chrome.tabs.sendMessage(tabId,{type:'nextshot-select'});
}
chrome.commands.onCommand.addListener(async command=>{
  if(command!=='capture')return;
  const [tab]=await chrome.tabs.query({active:true,currentWindow:true});if(tab?.id)await startCapture(tab.id).catch(()=>{});
});
chrome.tabs.onRemoved.addListener(tabId=>{void(async()=>{const associations=await draftAssociations(),id=associations[tabId];if(id){await discardDraft(id);delete associations[tabId];await chrome.storage.session.set({draftTabs:associations});}})();});
chrome.permissions.onRemoved.addListener(()=>{void cleanDrafts();});
chrome.runtime.onMessage.addListener((message,sender,respond)=>{
  if(!message||typeof message!=='object'||typeof message.type!=='string')return;
  const trustedPage=sender.url?.startsWith(chrome.runtime.getURL(''));
  if(message.type==='nextshot-record-event'&&sender.tab?.id&&sender.frameId===0){void recordObservedEvent(sender.tab.id,message.kind,message.label);return;}
  if(message.type==='nextshot-record'&&trustedPage&&!sender.url?.endsWith('offscreen.html')){
    const run=async()=>{switch(message.action){case 'start':await startRecording(Number(message.tabId));break;case 'pause':await pauseRecording();break;case 'resume':await resumeRecording();break;case 'stop':await stopRecording();break;case 'discard':await discardRecording();break;case 'select':return {id:await selectRecording(message.start,message.end,message.issue)};case 'status':return recordingStatus();default:throw Error('Unknown recording action');}return {ok:true};};
    run().then(respond,e=>respond({error:e.message}));return true;
  }
  if(message.type==='nextshot-start'&&trustedPage){
    startCapture(Number(message.tabId)).then(()=>respond({ok:true}),error=>respond({error:String(error.message)}));return true;
  }
  if(message.type==='nextshot-region'&&sender.tab?.id&&sender.frameId===0&&/^https?:/.test(sender.url??'')){
    captureRegion(sender.tab.id,sender.tab.windowId,message).then(result=>respond(result),error=>respond({error:String(error.message)}));return true;
  }
  if(message.type==='nextshot-forget-draft'&&trustedPage){draftAssociations().then(async associations=>{for(const [tab,id] of Object.entries(associations))if(id===message.id)delete associations[tab];await chrome.storage.session.set({draftTabs:associations});respond({ok:true});});return true;}
});
async function captureRegion(tabId:number,windowId:number,message:any):Promise<{ok:true}> {
  const tab=await chrome.tabs.get(tabId);
  const active=(await chrome.tabs.query({active:true,windowId}))[0];if(active?.id!==tabId)throw new Error('Return to the selected tab and capture again.');
  const region=message.region;
  if(!region||![region.x,region.y,region.width,region.height,message.viewportWidth,message.viewportHeight].every(Number.isFinite)||region.width<8||region.height<8||region.x<0||region.y<0||region.x+region.width>message.viewportWidth+1||region.y+region.height>message.viewportHeight+1)throw new Error('Choose a larger visible area.');
  let switched=false,screenshot:string;
  const activation=(info:{tabId:number;windowId:number})=>{if(info.windowId===windowId&&info.tabId!==tabId)switched=true;};
  chrome.tabs.onActivated.addListener(activation);
  try{
    screenshot=await chrome.tabs.captureVisibleTab(windowId,{format:'png'});
    const confirmed=await chrome.tabs.sendMessage(tabId,{type:'nextshot-confirm-capture',proofId:message.proofId});
    const current=(await chrome.tabs.query({active:true,windowId}))[0];
    if(switched||current?.id!==tabId||!confirmed?.ok)throw new Error('The selected page changed during capture. Capture this area again.');
  }finally{chrome.tabs.onActivated.removeListener(activation);}
  const image=await createImageBitmap(await (await fetch(screenshot)).blob());
  const scaleX=image.width/message.viewportWidth,scaleY=image.height/message.viewportHeight;
  const width=Math.max(1,Math.round(region.width*scaleX)),height=Math.max(1,Math.round(region.height*scaleY));
  const canvas=new OffscreenCanvas(width,height),context=canvas.getContext('2d');if(!context)throw new Error('Cannot prepare image');
  context.drawImage(image,region.x*scaleX,region.y*scaleY,width,height,0,0,width,height);image.close();
  if(!Array.isArray(message.privateRects)||message.privateRects.length>2000)throw new Error('Private-region coverage is unavailable.');
  context.fillStyle='#252527';
  for(const r of message.privateRects){
    if(!r||![r.x,r.y,r.width,r.height].every(Number.isFinite)||r.width<0||r.height<0)throw new Error('Invalid private-region geometry');
    context.fillRect((r.x-region.x)*scaleX,(r.y-region.y)*scaleY,r.width*scaleX,r.height*scaleY);
  }
  const blob=await canvas.convertToBlob({type:'image/jpeg',quality:0.88});
  const capture=newCapture({url:sanitizeURL(tab.url),title:redactSensitive(tab.title,200),width,height});
  capture.viewport={width:message.viewportWidth,height:message.viewportHeight,scale:scaleX,scrollX:message.scrollX??0,scrollY:message.scrollY??0,cropX:region.x,cropY:region.y};
  capture.elements=(Array.isArray(message.elements)?message.elements:[]).slice(0,2000).map((e:any):ElementEvidence=>({id:sanitizeText(e.id,100),selector:redactSensitive(e.selector,500),tag:sanitizeText(e.tag,30),role:sanitizeText(e.role,60),text:redactSensitive(e.text,300),frameURL:sanitizeURL(e.frameURL),bounds:{x:(e.bounds.x-region.x)*scaleX,y:(e.bounds.y-region.y)*scaleY,width:e.bounds.width*scaleX,height:e.bounds.height*scaleY}}));
  capture.diagnostics=[{at:0,kind:'coverage',text:'Element context is a capture-time snapshot. Source locations are unavailable unless the site supplies reliable integration. Form fields and inaccessible embedded frames are covered.'}];
  const bytes=new Uint8Array(await blob.arrayBuffer());
  await saveDraft({capture,assets:[{name:capture.imageFile,mime:blob.type,bytes},{name:capture.cleanImageFile,mime:blob.type,bytes}]});
  const review=await chrome.tabs.create({url:chrome.runtime.getURL(`review.html?draft=${capture.id}`)});if(review.id){const associations=await draftAssociations();associations[review.id]=capture.id;await chrome.storage.session.set({draftTabs:associations});}
  return {ok:true};
}
