import {rounds,renderPrompt,endRound,assetsForRound,exportBundle} from './core/index.ts';
import type {Round} from './core/model.ts';
const status=document.querySelector<HTMLElement>('#status')!;
const capture=document.querySelector<HTMLButtonElement>('#capture')!;
const native=document.querySelector<HTMLInputElement>('#native')!;
async function requestAction(kind:string):Promise<void>{
  const intent=await chrome.runtime.sendMessage({type:'nextshot-intent',kind,tabId});if(intent.error)throw Error(intent.error);
  if(intent.needsPermission){const granted=await chrome.permissions.request(intent.permissions);if(!granted)throw Error('Permission was declined. Existing feedback stays available.');await chrome.runtime.sendMessage({type:'nextshot-intent-finish',id:intent.id});}
}
native.onchange=async()=>{if(!native.checked){await chrome.storage.local.set({nativeSave:false});await chrome.storage.session.remove('pendingIntent');return;}try{await requestAction('native');}catch(e){native.checked=false;status.textContent=e instanceof Error?e.message:'Native save is unavailable.';}};
const query=new URLSearchParams(location.search);let tabId=query.has('tab')?Number(query.get('tab')):undefined;let tabURL:string|undefined;
async function load():Promise<void> {
  native.checked=!!(await chrome.storage.local.get('nativeSave')).nativeSave&&await chrome.permissions.contains({permissions:['nativeMessaging']});
  const tab=tabId?await chrome.tabs.get(tabId):(await chrome.tabs.query({active:true,currentWindow:true}))[0];tabId=tab?.id;tabURL=tab?.url;
  if(!tabId||!tabURL?.startsWith('http')){capture.disabled=true;status.textContent='Choose a website tab to capture.';}
  for(const round of (await rounds()).slice(0,8))addRound(round);
  const error=(await chrome.storage.session.get('intentError')).intentError;if(typeof error==='string'){status.textContent=error;await chrome.storage.session.remove('intentError');}
}
capture.onclick=async()=>{
  if(!tabId||!tabURL)return;capture.disabled=true;
  try{
    await requestAction('capture');window.close();
  }catch(error){status.textContent=error instanceof Error?error.message:'Capture is unavailable.';capture.disabled=false;}
};
document.querySelector<HTMLButtonElement>('#end')!.onclick=async()=>{await endRound();status.textContent='Browser round ended.';};
function addRound(round:Round):void {
  const row=document.createElement('div');row.className='round';
  const title=document.createElement('button');title.className='round-title';title.textContent=`${round.endedAt?'':'Active: '}${round.name} (${round.captures.length})`;
  title.onclick=()=>{void chrome.tabs.create({url:chrome.runtime.getURL(`review.html?round=${round.id}`)});};
  const copy=document.createElement('button');copy.textContent='Copy prompt';copy.onclick=async()=>{await navigator.clipboard.writeText(renderPrompt(round));status.textContent='Prompt copied.';};
  const zip=document.createElement('button');zip.textContent='Export';zip.onclick=async()=>{
    try{const bytes=exportBundle(round,await assetsForRound(round));const url=URL.createObjectURL(new Blob([new Uint8Array(bytes).buffer],{type:'application/zip'}));const a=document.createElement('a');a.href=url;a.download=`nextshot-round-${round.createdAt.slice(0,16).replace(/[:T]/g,'-')}.zip`;a.click();setTimeout(()=>URL.revokeObjectURL(url),60000);}
    catch(error){status.textContent=error instanceof Error?error.message:'Export failed.';}
  };
  row.append(title,copy,zip);document.querySelector('#rounds')!.append(row);
}
void load().catch(error=>{status.textContent=error.message;});

const trial=document.querySelector<HTMLInputElement>('#recording-trial')!,recordStart=document.querySelector<HTMLButtonElement>('#record-start')!,recordReview=document.querySelector<HTMLButtonElement>('#record-review')!;
void chrome.storage.local.get('recordingEnabled').then(v=>{trial.checked=!!v.recordingEnabled;recordStart.hidden=!trial.checked;});
trial.onchange=async()=>{await chrome.storage.local.set({recordingEnabled:trial.checked});recordStart.hidden=!trial.checked;if(!trial.checked)await chrome.runtime.sendMessage({type:'nextshot-record',action:'discard'});};
recordStart.onclick=async()=>{
 try{if(!tabId||!tabURL)throw Error('Choose a website tab.');
 await requestAction('recording');window.close();
 }catch(e){status.textContent=e instanceof Error?e.message:'Recording unavailable';}
};
recordReview.onclick=()=>{void chrome.tabs.create({url:chrome.runtime.getURL('recording.html')});};
void chrome.runtime.sendMessage({type:'nextshot-record',action:'status'}).then(r=>{recordReview.hidden=!r?.tabId;if(r?.tabId)recordStart.disabled=true;});
