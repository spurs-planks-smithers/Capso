import {mountActionKeys} from './ui/keyboard.ts';
import {mountFramePermissions} from './frame-permissions.ts';
import {mountCaptureShortcut} from './shortcut.ts';
import {mountResume} from './resume.ts';
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
  const tab=tabId?await chrome.tabs.get(tabId):(await chrome.tabs.query({active:true,currentWindow:true}))[0];tabId=tab?.id;tabURL=tab?.url;await mountFramePermissions(tabId,status);
  if(!tabId||!tabURL?.startsWith('http')){capture.disabled=true;status.textContent='Choose a website tab to capture.';}
  await mountResume(document.querySelector<HTMLButtonElement>('#resume')!,status);
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
  const title=document.createElement('button');title.className='round-title';title.dataset.focusKey='Enter';title.textContent=`${round.endedAt?'':'Active: '}${round.name} (${round.captures.length})`;
  title.onclick=()=>{void chrome.tabs.create({url:chrome.runtime.getURL(`review.html?round=${round.id}`)});};
  const copy=document.createElement('button');copy.textContent='Copy instructions';copy.dataset.action='copy';copy.dataset.keyHint='C';copy.onclick=async()=>{await navigator.clipboard.writeText(renderPrompt(round));status.textContent='Instructions copied. Paste them into your coding agent and attach the ZIP.';};
  const zip=document.createElement('button');zip.textContent='Download ZIP';zip.dataset.action='zip';zip.dataset.keyHint='X';zip.onclick=async()=>{
    try{const bytes=exportBundle(round,await assetsForRound(round));const url=URL.createObjectURL(new Blob([new Uint8Array(bytes).buffer],{type:'application/zip'}));const a=document.createElement('a');a.href=url;a.download=`nextshot-round-${round.createdAt.slice(0,16).replace(/[:T]/g,'-')}.zip`;a.click();setTimeout(()=>URL.revokeObjectURL(url),60000);status.textContent='ZIP download started. Find it in Chrome Downloads.';}
    catch(error){status.textContent=error instanceof Error?error.message:'Export failed.';}
  };
  row.append(title,copy,zip);document.querySelector('#rounds')!.append(row);
}
void load().catch(error=>{status.textContent=error.message;});
mountCaptureShortcut(document.querySelector<HTMLElement>('#shortcut')!,document.querySelector<HTMLButtonElement>('#shortcut-setup')!,capture);

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

const rollingTrial=document.querySelector<HTMLInputElement>('#rolling-trial')!,arm=document.querySelector<HTMLButtonElement>('#rolling-arm')!,openRolling=document.querySelector<HTMLButtonElement>('#rolling-open')!,stopRolling=document.querySelector<HTMLButtonElement>('#rolling-stop')!;
async function refreshRolling():Promise<void>{const flag=!!(await chrome.storage.local.get('rollingEnabled')).rollingEnabled;rollingTrial.checked=flag;const s=await chrome.runtime.sendMessage({type:'nextshot-rolling',action:'status'});arm.hidden=!flag;openRolling.hidden=stopRolling.hidden=!s.id;if(s.id){arm.textContent=s.reasons.includes('navigation')?'Re-arm current site':'Replace armed tab';status.textContent=s.reasons.length?'Rolling Round paused. History stays in memory.':'Rolling Round armed. Last 60 recorded seconds stay in memory.';}}
rollingTrial.onchange=async()=>{await chrome.storage.local.set({rollingEnabled:rollingTrial.checked});if(!rollingTrial.checked)await chrome.runtime.sendMessage({type:'nextshot-rolling',action:'stop'});await refreshRolling();};
arm.onclick=async()=>{try{await requestAction('rolling');window.close();}catch(e){status.textContent=e instanceof Error?e.message:'Arming unavailable';}};
openRolling.onclick=async()=>{const r=await chrome.runtime.sendMessage({type:'nextshot-rolling',action:'open'});if(r.error)status.textContent=r.error;else window.close();};
stopRolling.onclick=async()=>{await chrome.runtime.sendMessage({type:'nextshot-rolling',action:'stop'});await refreshRolling();};
void refreshRolling();

const assistanceMode=document.querySelector<HTMLSelectElement>('#assistance-mode')!;
const assistanceStatus=document.querySelector<HTMLElement>('#assistance-status')!;
async function refreshAssistance():Promise<void>{
  const settings=await chrome.runtime.sendMessage({type:'nextshot-assistance',action:'status'});
  if(settings.error){assistanceStatus.textContent='Local suggestions stay available.';return;}
  assistanceMode.value=settings.assistanceMode;
  document.querySelector<HTMLElement>('#jev-settings')!.hidden=settings.assistanceMode!=='jev';
  document.querySelector<HTMLElement>('#apple-help')!.hidden=settings.assistanceMode!=='apple';
  document.querySelector<HTMLElement>('#apple-grant')!.hidden=settings.assistanceMode!=='apple';
  for(const [id,key] of [['jev-enabled','jevEnabled'],['jev-page-consent','jevConsentPageData'],['jev-note-consent','jevConsentReviewerText']])document.querySelector<HTMLInputElement>('#'+id)!.checked=settings[key]===true;
  document.querySelector<HTMLElement>('#jev-signout')!.hidden=!settings.signedIn;
  document.querySelector<HTMLElement>('#jev-signin')!.hidden=settings.signedIn;
  assistanceStatus.textContent=settings.assistanceMode==='apple'?(settings.browserAppleIntelligence?'Apple assistance runs only during review.':'Apple trial stays off until Dev review.'):settings.assistanceMode==='jev'?(settings.signedIn?'Signed in. Jev still requires enablement and page consent.':'Invited sign-in is optional. Local suggestions stay available.'):'Local suggestions stay available.';
}
assistanceMode.onchange=async()=>{await chrome.storage.local.set({assistanceMode:assistanceMode.value});await refreshAssistance();};
for(const [id,key] of [['jev-enabled','jevEnabled'],['jev-page-consent','jevConsentPageData'],['jev-note-consent','jevConsentReviewerText']]){
  const input=document.querySelector<HTMLInputElement>('#'+id)!;
  input.onchange=async()=>{await chrome.storage.local.set({[key]:input.checked});await refreshAssistance();};
}
document.querySelector<HTMLButtonElement>('#jev-signin')!.onclick=async()=>{try{await requestAction('jev');await refreshAssistance();}catch(e){assistanceStatus.textContent=e instanceof Error?e.message:'Sign-in unavailable. Local suggestions remain.';}};
document.querySelector<HTMLButtonElement>('#jev-signout')!.onclick=async()=>{await chrome.runtime.sendMessage({type:'nextshot-assistance',action:'signout'});await refreshAssistance();};
document.querySelector<HTMLButtonElement>('#apple-grant')!.onclick=async()=>{try{await requestAction('apple');await refreshAssistance();}catch(e){assistanceStatus.textContent=e instanceof Error?e.message:'Apple assistance unavailable.';}};
void refreshAssistance().catch(()=>{assistanceStatus.textContent='Local suggestions stay available.';});

mountActionKeys([{selector:'#keyboard-help summary',key:'q'},{selector:'#end',key:'e'},{selector:'#shortcut-setup',key:'f'},{selector:'.round:focus-within [data-action=copy]',key:'c'},{selector:'.round:focus-within [data-action=zip]',key:'x'},{selector:'#record-start',key:'r'},{selector:'#record-review',key:'v'},{selector:'#rolling-arm',key:'a'},{selector:'#rolling-open',key:'g'},{selector:'#rolling-stop',key:'shift+x'},{selector:'#apple-grant',key:'b'},{selector:'#jev-signin',key:'s'},{selector:'#jev-signout',key:'shift+s'},{selector:'#assistance-settings summary',key:'t'}]);
