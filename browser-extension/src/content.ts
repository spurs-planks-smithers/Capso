import {redactSensitive,sanitizeText} from './core/sanitize.ts';
import type {Bounds,ElementEvidence} from './core/model.ts';
const state=globalThis as typeof globalThis&{__nextshotPageAdapter?:boolean};
let captureProof:{id:string;region:Bounds;fingerprint:string;url:string;dirty:boolean}|undefined;
if(!state.__nextshotPageAdapter){state.__nextshotPageAdapter=true;initialize();}
function initialize():void {
  let selecting=false;
  let recordingCleanup:(()=>void)|undefined,frameCleanup:(()=>void)|undefined;
  chrome.runtime.onMessage.addListener((message,_sender,respond)=>{
    if(message?.type==='nextshot-record-observe'){
      recordingCleanup?.();
      const send=(kind:string,label:string)=>{void chrome.runtime.sendMessage({type:'nextshot-record-event',kind,label:redactSensitive(label,200)}).catch(()=>{});};
      const click=(e:MouseEvent)=>{const target=e.composedPath().find(v=>v instanceof Element) as Element|undefined;if(target)send('click',actionLabel(target));};
      const error=()=>send('error','A page error occurred. Error details are unavailable.');
      document.addEventListener('click',click,true);window.addEventListener('error',error);window.addEventListener('unhandledrejection',error);
      const resources=new PerformanceObserver(list=>{for(const entry of list.getEntries())if(entry instanceof PerformanceResourceTiming)send('request',entry.name);});
      resources.observe({type:'resource'});
      recordingCleanup=()=>{document.removeEventListener('click',click,true);window.removeEventListener('error',error);window.removeEventListener('unhandledrejection',error);resources.disconnect();};respond({ok:true});
    }
    if(message?.type==='nextshot-record-cleanup'){frameCleanup?.();recordingCleanup?.();recordingCleanup=undefined;respond({ok:true});}
    if(message?.type==='nextshot-record-release'){frameCleanup?.();respond({ok:true});}
    if(message?.type==='nextshot-record-frame'){
      void(async()=>{
        frameCleanup?.();const region={x:0,y:0,width:innerWidth,height:innerHeight};
        const privateNodes=allElements().filter(e=>['INPUT','TEXTAREA','SELECT','IFRAME'].includes(e.tagName)||editable(e));
        const roots=[document,...new Set(allElements().map(e=>e.getRootNode()).filter((r):r is ShadowRoot=>r instanceof ShadowRoot))];
        const movesPrivate=roots.some(root=>root.getAnimations().some(a=>{const target=a.effect instanceof KeyframeEffect?a.effect.target:null;return a.playState==='running'&&target instanceof Element&&privateNodes.some(e=>target.contains(e)||e.contains(target));}));
        if(movesPrivate){respond({error:'A private region is animated. This frame is skipped.'});return;}
        let observer:MutationObserver|undefined,stopMovement:(()=>void)|undefined;
        frameCleanup=()=>{observer?.disconnect();stopMovement?.();captureProof=undefined;frameCleanup=undefined;};
        try{
          await new Promise<void>(r=>requestAnimationFrame(()=>requestAnimationFrame(()=>r())));
          const proofId=crypto.randomUUID();captureProof={id:proofId,region,fingerprint:fingerprint(region),url:location.href,dirty:false};
          stopMovement=watchMovement(()=>{if(captureProof?.id===proofId)captureProof.dirty=true;});
          observer=new MutationObserver(records=>{if(captureProof&&records.some(r=>!(r.target instanceof Element?r.target:r.target.parentElement)?.closest('[data-nextshot-overlay]')))captureProof.dirty=true;});
          const options={subtree:true,attributes:true,childList:true,characterData:true};observer.observe(document.documentElement,options);
          for(const root of new Set(allElements().map(e=>e.getRootNode())))if(root instanceof ShadowRoot)observer.observe(root,options);
          respond({proofId,region,elements:snapshot(region),url:location.href,title:document.title,privateRects:privateRects(),alerts:allElements().filter(e=>e.matches('[role=alert],[aria-live=assertive]')).filter(e=>{const r=rectOf(e),s=getComputedStyle(e);return r.width>0&&r.height>0&&r.x<innerWidth&&r.y<innerHeight&&r.x+r.width>0&&r.y+r.height>0&&s.visibility==='visible'&&s.display!=='none'&&s.opacity!=='0';}).slice(0,8).map(e=>redactSensitive([...e.childNodes].filter(n=>n.nodeType===Node.TEXT_NODE).map(n=>n.textContent??'').join(' '),200)),viewportWidth:innerWidth,viewportHeight:innerHeight});
          const release=frameCleanup;setTimeout(()=>{if(frameCleanup===release)release?.();},1500);
        }catch{frameCleanup?.();respond({error:'Privacy snapshot unavailable'});}
      })();return true;
    }
  });
  chrome.runtime.onMessage.addListener((message,_sender,respond)=>{
    if(message?.type==='nextshot-select'&&!selecting){selecting=true;select(()=>{selecting=false;void chrome.runtime.sendMessage({type:'nextshot-selection-ended'}).catch(()=>{});});}
    if(message?.type==='nextshot-confirm-capture'){
      const proof=captureProof;
      respond({ok:!!proof&&!proof.dirty&&proof.id===message.proofId&&proof.url===location.href&&proof.fingerprint===fingerprint(proof.region)});return false;
    }
  });
}
function rectOf(element:Element):Bounds {const r=element.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height};}
function allElements():Element[] {
  const result:Element[]=[],pending:ParentNode[]=[document];
  while(pending.length){
    const root=pending.pop()!;
    for(const e of root.querySelectorAll('*')){
      if(e.closest('[data-nextshot-overlay]'))continue;
      result.push(e);if(result.length>20000)throw new Error('This page exceeds verified capture limits.');
      const shadow=(e instanceof HTMLElement?chrome.dom?.openOrClosedShadowRoot(e):null)??e.shadowRoot;if(shadow)pending.push(shadow);
    }
  }
  return result;
}
function editable(e:Element):boolean {return e instanceof HTMLElement&&e.isContentEditable;}
function watchMovement(dirty:()=>void):()=>void {
  const roots:EventTarget[]=[window,...new Set(allElements().map(e=>e.getRootNode()).filter((r):r is ShadowRoot=>r instanceof ShadowRoot))];
  if(visualViewport)roots.push(visualViewport);
  const events=['scroll','resize','animationstart','transitionrun'];
  for(const root of roots)for(const event of events)root.addEventListener(event,dirty,true);
  return()=>{for(const root of roots)for(const event of events)root.removeEventListener(event,dirty,true);};
}
function actionLabel(element:Element):string {
  const control=element.closest('button,a,[role=button],[role=link],[role=tab],[role=menuitem],[role=checkbox],[role=radio]')??element;
  if(['INPUT','TEXTAREA','SELECT'].includes(element.tagName)||editable(element)||element.closest('[contenteditable]'))return 'Click field';
  const role=control.getAttribute('role')??control.tagName.toLowerCase();
  if(!['button','a','link','tab','menuitem','checkbox','radio'].includes(role))return 'Click page element';
  let label=control.getAttribute('aria-label')??'';
  if(!label){
    const walker=document.createTreeWalker(control,NodeFilter.SHOW_TEXT);let node:Node|null,count=0;
    while((node=walker.nextNode())&&count++<100&&label.length<160){
      const parent=node.parentElement;if(!parent||parent.closest('input,textarea,select,[contenteditable]'))continue;
      const style=getComputedStyle(parent);if(style.display==='none'||style.visibility==='hidden')continue;
      label+=' '+(node.textContent??'');
    }
  }
  return 'Click '+(redactSensitive(label.replace(/\s+/g,' ').trim(),160)||role);
}
function selector(element:Element,includeIds=true):string {
  const parts:string[]=[];let current:Element|null=element;
  for(let depth=0;current&&depth<5;depth++,current=current.parentElement){
    const tag=current.tagName.toLowerCase();
    if(includeIds&&current.id&&!/(?:token|secret|password)/i.test(current.id)){parts.unshift(`${tag}#${CSS.escape(current.id)}`);break;}
    const parent=current.parentElement;
    const siblings=parent?[...parent.children].filter(e=>e.tagName===current!.tagName):[];
    parts.unshift(tag+(siblings.length>1?`:nth-of-type(${siblings.indexOf(current)+1})`:''));
  }
  const root=element.getRootNode();
  return (root instanceof ShadowRoot?selector(root.host,includeIds)+' >>> ':'')+parts.join(' > ');
}
function snapshot(region:Bounds,nodes=allElements()):ElementEvidence[] {
  const result:ElementEvidence[]=[];
  for(const e of nodes){
    if(result.length>=2000)break;
    if(['SCRIPT','STYLE','NOSCRIPT','IFRAME'].includes(e.tagName))continue;
    if(e.parentElement?.closest('select,textarea,[contenteditable]'))continue;
    const bounds=rectOf(e);if(bounds.width<1||bounds.height<1||bounds.x>region.x+region.width||bounds.y>region.y+region.height||bounds.x+bounds.width<region.x||bounds.y+bounds.height<region.y)continue;
    if(getComputedStyle(e).visibility==='hidden')continue;
    if(['INPUT','TEXTAREA','SELECT'].includes(e.tagName)||editable(e)){
      if(editable(e)&&e.parentElement&&editable(e.parentElement))continue;
      const role=(e.getAttribute('role')??'').split(/\s+/).find(r=>['textbox','searchbox','combobox','listbox','checkbox','radio','slider','spinbutton','switch'].includes(r))||(editable(e)?'textbox':'');
      result.push({id:`element-${result.length+1}`,selector:selector(e,false),tag:e.tagName.toLowerCase(),role,text:'',bounds});
      continue;
    }
    const ownText=[...e.childNodes].filter(n=>n.nodeType===Node.TEXT_NODE).map(n=>n.textContent??'').join(' ');
    const label=redactSensitive(e.getAttribute('aria-label')||ownText,300).trim();
    result.push({id:`element-${result.length+1}`,selector:selector(e),tag:e.tagName.toLowerCase(),role:sanitizeText(e.getAttribute('role')??'',60),text:label,bounds});
  }
  return result;
}
function privateRects(nodes=allElements()):Bounds[]{return nodes.filter(e=>['INPUT','TEXTAREA','SELECT','IFRAME'].includes(e.tagName)||editable(e)||e.parentElement?.closest('select,textarea,[contenteditable]')).map(rectOf).filter(r=>r.width>0&&r.height>0);}
function fingerprint(region:Bounds):string {
  const nodes=allElements();
  return JSON.stringify({elements:snapshot(region,nodes),masks:privateRects(nodes),width:innerWidth,height:innerHeight,x:scrollX,y:scrollY});
}
function masks():HTMLElement[] {
  const covers:HTMLElement[]=[];
  for(const r of privateRects(allElements().filter(e=>e.tagName!=='IFRAME'))){
    const cover=document.createElement('div');cover.dataset.nextshotOverlay='mask';
    Object.assign(cover.style,{position:'fixed',left:`${Math.max(0,r.x)}px`,top:`${Math.max(0,r.y)}px`,width:`${r.width}px`,height:`${r.height}px`,background:'#252527',zIndex:'2147483646',pointerEvents:'none'});
    document.documentElement.append(cover);covers.push(cover);
  }
  return covers;
}
function select(done:()=>void):void {
  const root=document.createElement('div');root.dataset.nextshotOverlay='selection';
  Object.assign(root.style,{position:'fixed',inset:'0',zIndex:'2147483647',cursor:'crosshair',background:'rgba(15,18,25,.14)',userSelect:'none'});
  const label=document.createElement('div');label.textContent='Drag to select an area. Esc cancels.';
  Object.assign(label.style,{position:'absolute',bottom:'28px',left:'50%',transform:'translateX(-50%)',padding:'10px 16px',borderRadius:'8px',background:'#fff',color:'#222',font:'14px -apple-system,BlinkMacSystemFont,sans-serif'});
  const box=document.createElement('div');Object.assign(box.style,{position:'absolute',border:'2px solid #2f6bd6',background:'rgba(255,255,255,.12)',pointerEvents:'none'});
  root.append(label,box);document.documentElement.append(root);
  let start:{x:number;y:number}|undefined;
  const cleanup=()=>{root.remove();document.removeEventListener('keydown',key,true);done();};
  const key=(e:KeyboardEvent)=>{if(e.key==='Escape'){e.preventDefault();e.stopPropagation();cleanup();}};
  document.addEventListener('keydown',key,true);
  root.onpointerdown=e=>{start={x:e.clientX,y:e.clientY};root.setPointerCapture(e.pointerId);e.preventDefault();};
  root.onpointermove=e=>{if(start)Object.assign(box.style,{left:`${Math.min(start.x,e.clientX)}px`,top:`${Math.min(start.y,e.clientY)}px`,width:`${Math.abs(e.clientX-start.x)}px`,height:`${Math.abs(e.clientY-start.y)}px`});};
  root.onpointerup=async e=>{
    if(!start)return;
    const region={x:Math.max(0,Math.min(start.x,e.clientX)),y:Math.max(0,Math.min(start.y,e.clientY)),width:Math.min(innerWidth,Math.abs(e.clientX-start.x)),height:Math.min(innerHeight,Math.abs(e.clientY-start.y))};
    if(region.width<8||region.height<8){label.textContent='Select an area at least 8 pixels wide and high.';start=undefined;return;}
    let cover:HTMLElement[]=[];let observer:MutationObserver|undefined,stopMovement:(()=>void)|undefined;
    const animations=document.getAnimations().filter(a=>a.playState==='running');animations.forEach(a=>a.pause());
    try{
      cover=masks();root.style.visibility='hidden';
      await new Promise<void>(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve())));
      const elements=snapshot(region),proofId=crypto.randomUUID();captureProof={id:proofId,region,fingerprint:fingerprint(region),url:location.href,dirty:false};
      stopMovement=watchMovement(()=>{if(captureProof?.id===proofId)captureProof.dirty=true;});
      observer=new MutationObserver(records=>{
        if(!captureProof)return;
        for(const record of records){
          const target=record.target instanceof Element?record.target:record.target.parentElement;
          if(!target||target.closest('[data-nextshot-overlay]'))continue;
          const r=target.getBoundingClientRect();
          if(target===document.body||target===document.documentElement||(r.x<region.x+region.width&&r.y<region.y+region.height&&r.right>region.x&&r.bottom>region.y))captureProof.dirty=true;
        }
      });
      observer.observe(document.documentElement,{subtree:true,childList:true,attributes:true,characterData:true});
      for(const root of new Set(allElements().map(e=>e.getRootNode())))if(root instanceof ShadowRoot)observer.observe(root,{subtree:true,childList:true,attributes:true,characterData:true});
      const result=await chrome.runtime.sendMessage({type:'nextshot-region',proofId,region,elements,privateRects:privateRects(),viewportWidth:innerWidth,viewportHeight:innerHeight,scrollX,scrollY});
      if(result?.error)throw new Error(result.error);
      cleanup();
    }catch(error){root.style.visibility='visible';label.textContent=error instanceof Error?error.message:'Capture failed. Try again.';start=undefined;}
    finally{observer?.disconnect();stopMovement?.();captureProof=undefined;cover.forEach(e=>e.remove());animations.forEach(a=>a.play());}
  };
}
