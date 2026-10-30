import {listDrafts} from './core/index.ts';

/** Shows "Resume unsaved capture" when a screenshot draft exists. It focuses the open draft tab, or opens exactly one. */
export async function mountResume(button:HTMLButtonElement,status:HTMLElement):Promise<void> {
  const [draft]=await listDrafts();if(!draft)return;
  button.hidden=false;button.dataset.focusKey='Enter';button.textContent=`Resume unsaved capture${draft.title?`: ${draft.title.slice(0,40)}`:''}`;
  button.onclick=()=>{void(async()=>{
    const page=chrome.runtime.getURL('review.html');
    const open=(await chrome.tabs.query({url:page+'*'})).find(tab=>tab.url?.includes(`draft=${draft.id}`));
    if(open?.id){await chrome.tabs.update(open.id,{active:true});await chrome.windows.update(open.windowId,{focused:true});}
    else await chrome.tabs.create({url:`${page}?draft=${draft.id}`});
    window.close();
  })().catch(error=>{status.textContent=error.message;});};
}
