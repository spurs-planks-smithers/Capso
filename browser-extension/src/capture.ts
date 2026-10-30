import {beginFrameContext,type FrameContext} from './frame-context.ts';
import {newCapture,saveDraft,sanitizeURL,sanitizeText,redactSensitive} from './core/index.ts';
import type {Capture,ElementEvidence} from './core/model.ts';

export async function selectBrowserArea(tabId:number):Promise<void>{
  const tab=await chrome.tabs.get(tabId);
  if(!tab.url||!/^https?:/.test(tab.url))throw new Error('Choose a website tab to capture.');
  await chrome.scripting.executeScript({target:{tabId},files:['content.js']});
  await chrome.tabs.sendMessage(tabId,{type:'nextshot-select'});
}

export async function captureRegion(tabId:number,windowId:number,message:any):Promise<{ok:true}> {
  const tab=await chrome.tabs.get(tabId);
  const active=(await chrome.tabs.query({active:true,windowId}))[0];if(active?.id!==tabId)throw new Error('Return to the selected tab and capture again.');
  const region=message.region;
  if(!region||![region.x,region.y,region.width,region.height,message.viewportWidth,message.viewportHeight].every(Number.isFinite)||region.width<8||region.height<8||region.x<0||region.y<0||region.x+region.width>message.viewportWidth+1||region.y+region.height>message.viewportHeight+1)throw new Error('Choose a larger visible area.');
  let switched=false,screenshot:string;
  const activation=(info:{tabId:number;windowId:number})=>{if(info.windowId===windowId&&info.tabId!==tabId)switched=true;};
  chrome.tabs.onActivated.addListener(activation);
  let frames:FrameContext|undefined;
  try{
    frames=await beginFrameContext(tabId);
    screenshot=await chrome.tabs.captureVisibleTab(windowId,{format:'png'});
    const confirmed=await chrome.tabs.sendMessage(tabId,{type:'nextshot-confirm-capture',proofId:message.proofId});
    const current=(await chrome.tabs.query({active:true,windowId}))[0];
    if(switched||current?.id!==tabId||!confirmed?.ok||frames&&!await frames.confirm())throw new Error('The selected page changed during capture. Capture this area again.');
  }finally{chrome.tabs.onActivated.removeListener(activation);await frames?.release();}
  if(frames){message={...message,elements:frames.elements,privateRects:frames.privateRects};}
  const image=await createImageBitmap(await (await fetch(screenshot)).blob());
  const scaleX=image.width/message.viewportWidth,scaleY=image.height/message.viewportHeight;
  if(Math.abs(scaleX-scaleY)>Math.max(scaleX,scaleY)*.01){image.close();throw new Error('This browser view cannot be captured safely. Use a standard tab view.');}
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
  // A screenshot draft is keyed by capture ID and kept by the retention rule, so it needs no tab association.
  await chrome.tabs.create({url:chrome.runtime.getURL(`review.html?draft=${capture.id}`)});
  return {ok:true};
}
