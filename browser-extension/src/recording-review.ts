import {mountActionKeys} from './ui/keyboard.ts';
const $=(id:string)=>document.getElementById(id)!;
const call=(action:string,extra:Record<string,unknown>={})=>chrome.runtime.sendMessage({type:'nextshot-record',action,...extra});
async function refresh():Promise<void>{
 const s=await call('status');if(s.error)throw Error(s.error);
 $('status').textContent=s.tabId?`${s.stopReason??(s.stopped?'Stopped':s.paused?'Paused':'Recording')}: ${s.frames.length} verified frames in memory. Captured evidence stays available until selection or discard.`:'No recording remains in memory.';
 $('selection').hidden=!s.stopped||!s.frames?.length;
 if(s.frames?.length){const first=s.frames[0].at/1000,last=s.frames.at(-1).at/1000;for(const [id,value] of [['start',first],['end',last],['issue',last]] as const){const input=$(id) as HTMLInputElement;if(!input.dataset.edited)input.value=String(value);}}
 $('events').replaceChildren();for(const e of [...s.actions??[],...s.diagnostics??[]].sort((a,b)=>a.at-b.at)){const row=document.createElement('li');row.textContent=`${(e.at/1000).toFixed(1)}s: ${e.label??e.text}${e.url?' '+e.url:''}`;$('events').append(row);}
}
for(const action of ['pause','resume','stop','discard'])$(action).onclick=()=>{void call(action).then(r=>{if(r.error)throw Error(r.error);return refresh();}).catch(e=>{$('status').textContent=e.message;});};
for(const id of ['start','end','issue'])$(id).oninput=()=>{$(id).dataset.edited='true';};
$('select').onclick=async()=>{const button=$('select') as HTMLButtonElement;button.disabled=true;try{const tab=await chrome.tabs.getCurrent();const r=await call('select',{reviewTab:tab?.id,...Object.fromEntries(['start','end','issue'].map(id=>[id,Number(($(id) as HTMLInputElement).value)*1000]))});if(r.error)throw Error(r.error);location.href=chrome.runtime.getURL(`review.html?draft=${r.id}`);}catch(e){$('status').textContent=e instanceof Error?e.message:'Selection failed';button.disabled=false;}};
void refresh();const timer=setInterval(()=>{void refresh();},1500);addEventListener('pagehide',()=>{clearInterval(timer);void call('discard');});

mountActionKeys([{selector:'#keyboard-help summary',key:'q'},{selector:'#pause',key:'a'},{selector:'#resume',key:'r'},{selector:'#stop',key:'s'},{selector:'#discard',key:'shift+x'},{selector:'#select',key:'mod+s'}]);
