import {redactSensitive,sanitizeText} from './core/sanitize.ts';
import type {Bounds,ElementEvidence} from './core/model.ts';
const state=globalThis as typeof globalThis&{__nextshotPageAdapter?:boolean};
let captureProof:{id:string;region:Bounds;fingerprint:string;url:string;dirty:boolean}|undefined;
if(!state.__nextshotPageAdapter){state.__nextshotPageAdapter=true;initialize();}
function initialize():void {
  let selecting=false;
  chrome.runtime.onMessage.addListener((message,_sender,respond)=>{
    if(message?.type==='nextshot-select'&&!selecting){selecting=true;select(()=>{selecting=false;});}
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
function selector(element:Element):string {
  const parts:string[]=[];let current:Element|null=element;
  for(let depth=0;current&&depth<5;depth++,current=current.parentElement){
    const tag=current.tagName.toLowerCase();
    if(current.id&&!/(?:token|secret|password)/i.test(current.id)){parts.unshift(`${tag}#${CSS.escape(current.id)}`);break;}
    const parent=current.parentElement;
    const siblings=parent?[...parent.children].filter(e=>e.tagName===current!.tagName):[];
    parts.unshift(tag+(siblings.length>1?`:nth-of-type(${siblings.indexOf(current)+1})`:''));
  }
  const root=element.getRootNode();
  return (root instanceof ShadowRoot?selector(root.host)+' >>> ':'')+parts.join(' > ');
}
function snapshot(region:Bounds,nodes=allElements()):ElementEvidence[] {
  const result:ElementEvidence[]=[];
  for(const e of nodes){
    if(result.length>=2000)break;
    if(['SCRIPT','STYLE','NOSCRIPT','INPUT','TEXTAREA','SELECT','IFRAME'].includes(e.tagName)||editable(e))continue;
    const bounds=rectOf(e);if(bounds.width<1||bounds.height<1||bounds.x>region.x+region.width||bounds.y>region.y+region.height||bounds.x+bounds.width<region.x||bounds.y+bounds.height<region.y)continue;
    if(getComputedStyle(e).visibility==='hidden')continue;
    const ownText=[...e.childNodes].filter(n=>n.nodeType===Node.TEXT_NODE).map(n=>n.textContent??'').join(' ');
    const label=redactSensitive(e.getAttribute('aria-label')||ownText,300).trim();
    result.push({id:`element-${result.length+1}`,selector:selector(e),tag:e.tagName.toLowerCase(),role:sanitizeText(e.getAttribute('role')??'',60),text:label,bounds});
  }
  return result;
}
function privateRects(nodes=allElements()):Bounds[]{return nodes.filter(e=>['INPUT','TEXTAREA','SELECT','IFRAME'].includes(e.tagName)||editable(e)).map(rectOf).filter(r=>r.width>0&&r.height>0);}
function fingerprint(region:Bounds):string {
  const nodes=allElements();
  return JSON.stringify({elements:snapshot(region,nodes),masks:privateRects(nodes),width:innerWidth,height:innerHeight,x:scrollX,y:scrollY});
}
function masks():HTMLElement[] {
  const covers:HTMLElement[]=[];
  for(const r of privateRects()){
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
    let cover:HTMLElement[]=[];let observer:MutationObserver|undefined;
    const animations=document.getAnimations().filter(a=>a.playState==='running');animations.forEach(a=>a.pause());
    try{
      cover=masks();root.style.visibility='hidden';
      await new Promise<void>(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve())));
      const elements=snapshot(region),proofId=crypto.randomUUID();captureProof={id:proofId,region,fingerprint:fingerprint(region),url:location.href,dirty:false};
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
    finally{observer?.disconnect();captureProof=undefined;cover.forEach(e=>e.remove());animations.forEach(a=>a.play());}
  };
}
