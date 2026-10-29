import {rounds,renderPrompt,endRound,assetsForRound,exportBundle} from './core/index.ts';
import type {Round} from './core/model.ts';
const status=document.querySelector<HTMLElement>('#status')!;
const capture=document.querySelector<HTMLButtonElement>('#capture')!;
const native=document.querySelector<HTMLInputElement>('#native')!;
native.onchange=async()=>{if(native.checked&&!await chrome.permissions.request({permissions:['nativeMessaging']}))native.checked=false;await chrome.storage.local.set({nativeSave:native.checked});};
const query=new URLSearchParams(location.search);let tabId=query.has('tab')?Number(query.get('tab')):undefined;let tabURL:string|undefined;
async function load():Promise<void> {
  native.checked=!!(await chrome.storage.local.get('nativeSave')).nativeSave;
  const tab=tabId?await chrome.tabs.get(tabId):(await chrome.tabs.query({active:true,currentWindow:true}))[0];tabId=tab?.id;tabURL=tab?.url;
  if(!tabId||!tabURL?.startsWith('http')){capture.disabled=true;status.textContent='Choose a website tab to capture.';}
  for(const round of (await rounds()).slice(0,8))addRound(round);
}
capture.onclick=async()=>{
  if(!tabId||!tabURL)return;capture.disabled=true;
  try{
    const origin=new URL(tabURL).origin+'/*';
    if(!await chrome.permissions.contains({origins:[origin]})){
      const granted=await chrome.permissions.request({origins:[origin]});if(!granted)throw new Error('Site access is needed to attach element details.');
    }
    const result=await chrome.runtime.sendMessage({type:'nextshot-start',tabId});if(result?.error)throw new Error(result.error);window.close();
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
