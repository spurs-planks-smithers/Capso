import {chordOf} from './chord.ts';
export interface KeyAction {selector:string;key:string;when?:()=>boolean;run?:()=>void;}
const mac=/Mac/i.test(navigator.platform);
export function keyLabel(key:string):string{
  return key.split('+').map(part=>part==='mod'?(mac?'⌘':'Ctrl'):part==='shift'?(mac?'⇧':'Shift'):part==='alt'?(mac?'⌥':'Alt'):part==='escape'?'Esc':part==='enter'?(mac?'Return':'Enter'):part==='space'?'Space':part.toUpperCase()).join(mac?'':'+');
}
export function isTyping(target:EventTarget|null):boolean{
  const element=target as HTMLElement|null;
  return !!element&&(element.isContentEditable||element.tagName==='SELECT'||element.tagName==='INPUT'||element.tagName==='TEXTAREA'&&!(element as HTMLTextAreaElement).readOnly);
}
export function mountActionKeys(actions:KeyAction[]):()=>void{
  const refresh=()=>{
    for(const element of document.querySelectorAll<HTMLElement>('button,summary')){
      if(!element.dataset.keyHint)element.dataset.focusKey='Enter';
      if(element.dataset.keyLabelOwned||!element.hasAttribute('aria-label')){element.setAttribute('aria-label',element.textContent?.trim()??'');element.dataset.keyLabelOwned='true';}
    }
    for(const action of actions){const element=document.querySelector<HTMLElement>(action.selector);if(element&&(!action.when||action.when())){element.dataset.keyHint=keyLabel(action.key);element.setAttribute('aria-keyshortcuts',action.key.replace('mod',mac?'Meta':'Control').replace('shift','Shift').replace('escape','Escape'));}}
  };
  const keydown=(event:KeyboardEvent)=>{
    if(event.defaultPrevented||event.isComposing||event.repeat)return;
    const key=chordOf(event,mac);if(!key)return;
    const action=actions.find(action=>action.key===key&&(!action.when||action.when()));if(!action)return;
    if(isTyping(event.target)&&!event.metaKey&&!event.ctrlKey)return;
    const element=document.querySelector<HTMLElement>(action.selector);
    if(!element||element.hidden||element.hasAttribute('disabled')||element.closest('[hidden]')||!element.getClientRects().length)return;
    event.preventDefault();if(action.run)action.run();else element.click();
  };
  refresh();document.addEventListener('keydown',keydown);
  const observer=typeof MutationObserver==='undefined'?undefined:new MutationObserver(refresh);observer?.observe(document.body,{childList:true,subtree:true});
  const cleanup=()=>{observer?.disconnect();document.removeEventListener('keydown',keydown);};addEventListener('pagehide',cleanup,{once:true});return refresh;
}
