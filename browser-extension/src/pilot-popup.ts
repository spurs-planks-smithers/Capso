import {rounds,renderPrompt,endRound,assetsForRound,exportBundle} from './core/index.ts';
const status=document.querySelector<HTMLElement>('#status')!,capture=document.querySelector<HTMLButtonElement>('#capture')!;
let tabId:number|undefined;
async function captureIntent(kind:'capture'|'frames'):Promise<void>{
  const intent=await chrome.runtime.sendMessage({type:'nextshot-intent',kind,tabId});if(intent.error)throw Error(intent.error);
  if(intent.needsPermission&&!await chrome.permissions.request(intent.permissions))throw Error('Permission was declined. Saved feedback stays available.');
  await chrome.runtime.sendMessage({type:'nextshot-intent-finish',id:intent.id});window.close();
}
capture.onclick=()=>{capture.disabled=true;void captureIntent('capture').catch(error=>{status.textContent=error.message;capture.disabled=false;});};
async function load():Promise<void>{
  const [tab]=await chrome.tabs.query({active:true,currentWindow:true});tabId=tab?.id;
  if(!tabId||!tab.url||!/^https?:/.test(tab.url)){capture.disabled=true;status.textContent='Open a website tab to capture.';}
  const error=(await chrome.storage.session.get('intentError')).intentError;
  if(typeof error==='string'){status.textContent=error;await chrome.storage.session.remove('intentError');}
  const shortcut=document.querySelector<HTMLElement>('#shortcut')!;
  const command=(await chrome.commands.getAll()).find(c=>c.name==='capture');
  shortcut.textContent=command?.shortcut?`Shortcut: ${command.shortcut}`:'Use Capture an area to start.';
  const frame=tabId?(await chrome.storage.session.get('frameOrigins:'+tabId))['frameOrigins:'+tabId] as {url?:string;origins?:string[]}|undefined:undefined;
  if(frame?.url===tab?.url&&frame?.origins?.length){
    const button=document.querySelector<HTMLButtonElement>('#preview')!;button.hidden=false;
    button.onclick=()=>{void captureIntent('frames').catch(error=>{status.textContent=error.message;});};
  }
  const saved=await rounds();document.querySelector<HTMLElement>('#saved')!.hidden=!saved.length;
  for(const round of saved.slice(0,8)){
    const row=document.createElement('div');row.className='round';
    const title=document.createElement('button');title.className='round-title';title.textContent=`${round.endedAt?'':'Active: '}${round.name} (${round.captures.length})`;
    title.onclick=()=>{void chrome.tabs.create({url:chrome.runtime.getURL(`review.html?round=${round.id}`)});};
    const copy=document.createElement('button');copy.textContent='Copy prompt';copy.onclick=()=>{void navigator.clipboard.writeText(renderPrompt(round)).then(()=>{status.textContent='Prompt copied.';},()=>{status.textContent='Open the round and use Copy prompt.';});};
    const zip=document.createElement('button');zip.textContent='Export';zip.onclick=()=>{void(async()=>{const bytes=exportBundle(round,await assetsForRound(round));const url=URL.createObjectURL(new Blob([new Uint8Array(bytes).buffer],{type:'application/zip'}));const a=document.createElement('a');a.href=url;a.download=`nextshot-round-${round.createdAt.slice(0,16).replace(/[:T]/g,'-')}.zip`;a.click();setTimeout(()=>URL.revokeObjectURL(url),60000);status.textContent='Export download started.';})().catch(error=>{status.textContent=error.message;});};
    row.append(title,copy,zip);document.querySelector('#rounds')!.append(row);
  }
  const end=document.querySelector<HTMLButtonElement>('#end')!;end.hidden=!saved.some(r=>!r.endedAt);
  end.onclick=()=>{void endRound().then(()=>{status.textContent='Round ended. Your next capture starts a new one.';end.hidden=true;});};
}
void load().catch(error=>{status.textContent=error.message;});
