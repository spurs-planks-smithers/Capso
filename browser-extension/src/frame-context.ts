import type {Bounds,ElementEvidence} from './core/model.ts';
import {redactSensitive,sanitizeURL} from './core/sanitize.ts';

interface Child {index:number;box:Bounds;viewport:Bounds;safe:boolean;origin?:string;}
interface Proof {token:string;path:number[];url:string;width:number;height:number;scrollX:number;scrollY:number;elements:ElementEvidence[];privateRects:Bounds[];children:Child[];}
interface FrameProof {frameId:number;documentId:string;proof:Proof;}
export interface FrameContext {
  elements:ElementEvidence[];privateRects:Bounds[];requiredOrigins:string[];
  /** Call after captureVisibleTab and before any image retention. False discards the screenshot. */
  confirm():Promise<boolean>;
  /** Always call in finally. Snapshots also expire after 1500 milliseconds. */
  release():Promise<void>;
}

/** Explicit operations only. No observers or injection remain between capture operations.
 * The returned masks replace the TOP frame masks, not unrelated caller masks.
 * Any unavailable proof leaves that iframe fully covered. Capture pixels only after this resolves.
 * This does not freeze the page or modify its DOM. Recording can use the same API.
 * The caller must still confirm its own region proof and screenshot scaling before retention.
 */
export async function beginFrameContext(tabId:number):Promise<FrameContext|undefined> {
  // Discover permission candidates only during an explicit capture or armed sample.
  try{const found=await chrome.scripting.executeScript({target:{tabId},func:()=>({url:location.href,origins:[...new Set([...document.querySelectorAll('iframe')].flatMap(e=>{try{const u=new URL(e.src,location.href);return /^https?:$/.test(u.protocol)?[u.origin+'/*']:[];}catch{return [];} }))]})});
    if(found[0]?.result)await chrome.storage.session.set({['frameOrigins:'+tabId]:found[0].result});
  }catch{}
  if(!(await chrome.storage.local.get('embeddedPreviewsEnabled')).embeddedPreviewsEnabled)return;
  const token=crypto.randomUUID();let frames:FrameProof[]=[];
  try {
    const results=await chrome.scripting.executeScript({target:{tabId,allFrames:true},func:frameProbe,args:['begin',token]});
    frames=results.flatMap(r=>r.result&&r.documentId?[{frameId:r.frameId,documentId:r.documentId,proof:r.result}]:[]);
    const top=frames.find(f=>f.frameId===0&&f.proof.path.length===0);
    if(!top){await cleanup();return;}
    const merged=composeFrameContext(frames.map(f=>f.proof));
    const tab=await chrome.tabs.get(tabId);await chrome.storage.session.set({['frameOrigins:'+tabId]:{url:tab.url,origins:merged.requiredOrigins}});
    return {...merged,confirm:async()=>{
      try {
        for(const frame of frames){
          const result=await chrome.scripting.executeScript({target:{tabId,documentIds:[frame.documentId]},func:frameProbe,args:['confirm',token]});
          if(result.length!==1||result[0]?.frameId!==frame.frameId||result[0]?.documentId!==frame.documentId||!result[0]?.result)return false;
        }
        return true;
      }catch{return false;}
    },release:cleanup};
  }catch{await cleanup();return;}
  async function cleanup():Promise<void>{
    // Best effort also cleans partial allFrames injection after a permission failure.
    try{await chrome.scripting.executeScript({target:{tabId,allFrames:true},func:frameProbe,args:['release',token]});}catch{}
  }
}

/** Pure composition, exported for controlled fixture verification. */
export function composeFrameContext(proofs:Proof[]):Pick<FrameContext,'elements'|'privateRects'|'requiredOrigins'> {
  const elements:ElementEvidence[]=[],privateRects:Bounds[]=[],origins=new Set<string>();
  const key=(path:number[])=>path.join('.');
  const groups=new Map<string,Proof[]>();for(const proof of proofs){const k=key(proof.path);groups.set(k,[...(groups.get(k)??[]),proof]);}
  const root=groups.get('');if(root?.length!==1)throw new Error('Top frame proof unavailable');
  const clip=(a:Bounds,b:Bounds):Bounds=>{const x=Math.max(a.x,b.x),y=Math.max(a.y,b.y);return{x,y,width:Math.max(0,Math.min(a.x+a.width,b.x+b.width)-x),height:Math.max(0,Math.min(a.y+a.height,b.y+b.height)-y)};};
  function visit(proof:Proof,x:number,y:number,visible:Bounds):void {
    const map=(b:Bounds)=>clip({x:b.x+x,y:b.y+y,width:b.width,height:b.height},visible);
    const prefix=proof.path.length?`frame[${key(proof.path)}]`:'top';
    const url=sanitizeURL(proof.url);
    for(const e of proof.elements){const bounds=map(e.bounds);if(bounds.width&&bounds.height)elements.push({...e,id:`${prefix}:${e.id}`,selector:redactSensitive(`${prefix} >>> ${e.selector}`,500),text:redactSensitive(e.text??'',300),frameURL:url,bounds});}
    for(const r of proof.privateRects){const b=map(r);if(b.width&&b.height)privateRects.push(b);}
    for(const child of proof.children){
      const matches=groups.get(key([...proof.path,child.index]));const nested=matches?.length===1?matches[0]:undefined;
      // CSS transforms, clipping uncertainty, viewport mismatch and denied frames retain the full cover.
      if(!nested||!child.safe||Math.abs(nested.width-child.viewport.width)>.5||Math.abs(nested.height-child.viewport.height)>.5){
        const b=map(child.box);if(b.width&&b.height)privateRects.push(b);if(child.origin)origins.add(child.origin);continue;
      }
      const viewport=map(child.viewport);visit(nested,x+child.viewport.x,y+child.viewport.y,viewport);
    }
  }
  visit(root[0],0,0,{x:0,y:0,width:root[0].width,height:root[0].height});
  return {elements,privateRects,requiredOrigins:[...origins]};
}

/** Serialized by chrome.scripting. Keep every page-side helper inside this function. */
export function frameProbe(action:'begin'|'confirm'|'release',token:string):Proof|undefined {
  type Saved={token:string;proof:Proof;fingerprint:string;dirty:boolean;stop:()=>void};
  const host=globalThis as typeof globalThis&{__nextshotFrameProof?:Saved};
  if(action==='release'){if(host.__nextshotFrameProof?.token===token)host.__nextshotFrameProof.stop();return;}
  const path=():number[]=>{const result:number[]=[];let child:Window=window;while(child!==child.parent){const parent=child.parent;let found=-1;for(let i=0;i<parent.length;i++)if(parent.frames[i]===child){found=i;break;}if(found<0||result.length>=12)throw Error('Unknown frame path');result.unshift(found);child=parent;}return result;};
  const rect=(e:Element):Bounds=>{const r=e.getBoundingClientRect();return{x:r.x,y:r.y,width:r.width,height:r.height};};
  const nodes=():Element[]=>{const result:Element[]=[],pending:ParentNode[]=[document];while(pending.length){for(const e of pending.pop()!.querySelectorAll('*')){if(e.closest('[data-nextshot-overlay]'))continue;if(result.length>=20000)throw Error('Frame too large');result.push(e);const shadow=(e instanceof HTMLElement?chrome.dom?.openOrClosedShadowRoot(e):null)??e.shadowRoot;if(shadow)pending.push(shadow);}}return result;};
  const selector=(e:Element):string=>{const parts:string[]=[];let current:Element|null=e;for(let i=0;current&&i<5;i++,current=current.parentElement){if(current.id&&!/(?:token|secret|password)/i.test(current.id)){parts.unshift(current.tagName.toLowerCase()+'#'+CSS.escape(current.id));break;}const parent=current.parentElement;const siblings=parent?[...parent.children].filter(n=>n.tagName===current!.tagName):[];parts.unshift(current.tagName.toLowerCase()+(siblings.length>1?`:nth-of-type(${siblings.indexOf(current)+1})`:''));}const root=e.getRootNode();return(root instanceof ShadowRoot?selector(root.host)+' >>> ':'')+parts.join(' > ');};
  const read=():Proof=>{
    if(!/^https?:$/.test(location.protocol)||visualViewport&&(visualViewport.scale!==1||visualViewport.offsetLeft!==0||visualViewport.offsetTop!==0))throw Error('Unsupported viewport');
    const all=nodes();
    // Conservatively reject animations in this frame. Never pause them in a recording.
    if([document,...new Set(all.map(e=>e.getRootNode()).filter((r):r is ShadowRoot=>r instanceof ShadowRoot))].some(root=>root.getAnimations().some(a=>a.playState==='running')))throw Error('Animated frame');
    const children:Child[]=[],privateRects:Bounds[]=[],elements:ElementEvidence[]=[];
    for(const e of all){
      const box=rect(e);if(box.width<=0||box.height<=0)continue;
      if(e instanceof HTMLIFrameElement||e instanceof HTMLFrameElement){
        let index=-1;for(let i=0;i<window.length;i++)if(window.frames[i]===e.contentWindow){index=i;break;}
        let safe=index>=0&&e instanceof HTMLIFrameElement&&!e.hasAttribute('sandbox')&&e.getRootNode()===document&&Math.abs(box.width-e.offsetWidth)<.5&&Math.abs(box.height-e.offsetHeight)<.5;
        for(let ancestor:Element|null=e;ancestor;ancestor=ancestor.parentElement){const s=getComputedStyle(ancestor);if(s.transform!=='none'||s.translate!=='none'||s.rotate!=='none'||s.scale!=='none'||s.perspective!=='none'||s.clipPath!=='none'||s.filter!=='none'||s.zoom!=='1'||s.borderRadius!=='0px'||s.maskImage!=='none')safe=false;const a=rect(ancestor);if(ancestor!==e&&([s.overflowX,s.overflowY].some(v=>['hidden','clip','scroll','auto'].includes(v)))&&(box.x<a.x||box.y<a.y||box.x+box.width>a.x+a.width||box.y+box.height>a.y+a.height))safe=false;}
        // Scrollbar/frame border geometry must agree with the child viewport.
        const viewport={x:box.x+e.clientLeft,y:box.y+e.clientTop,width:e.clientWidth,height:e.clientHeight};
        let origin:string|undefined;try{const u=new URL(e.getAttribute('src')??'',location.href);if(/^https?:$/.test(u.protocol))origin=`${u.origin}/*`;}catch{}
        children.push({index,box,viewport,safe,origin});continue;
      }
      if(['INPUT','TEXTAREA','SELECT'].includes(e.tagName)||e instanceof HTMLElement&&e.isContentEditable){privateRects.push(box);continue;}
      if(['SCRIPT','STYLE','NOSCRIPT'].includes(e.tagName)||getComputedStyle(e).visibility==='hidden'||elements.length>=2000)continue;
      // No parent textContent, private descendants must never enter evidence.
      const own=[...e.childNodes].filter(n=>n.nodeType===Node.TEXT_NODE).map(n=>n.textContent??'').join(' ');
      elements.push({id:`element-${elements.length+1}`,selector:selector(e),tag:e.tagName.toLowerCase(),role:(e.getAttribute('role')??'').slice(0,60),text:(e.getAttribute('aria-label')||own).slice(0,300),bounds:box});
    }
    return{token,path:path(),url:location.href,width:innerWidth,height:innerHeight,scrollX,scrollY,elements,privateRects,children};
  };
  try{
    if(action==='confirm'){const saved=host.__nextshotFrameProof;if(!saved||saved.token!==token||saved.dirty||JSON.stringify(read())!==saved.fingerprint)return;return saved.proof;}
    host.__nextshotFrameProof?.stop();const proof=read();
    const observer=new MutationObserver(records=>{if(records.some(r=>!(r.target instanceof Element?r.target:r.target.parentElement)?.closest('[data-nextshot-overlay]')))saved.dirty=true;});
    const roots:EventTarget[]=[window,...new Set(nodes().map(e=>e.getRootNode()).filter((r):r is ShadowRoot=>r instanceof ShadowRoot))];
    if(visualViewport)roots.push(visualViewport);
    const events=['scroll','resize','animationstart','transitionrun'],dirty=()=>{saved.dirty=true;};
    const saved:Saved={token,proof,fingerprint:JSON.stringify(proof),dirty:false,stop:()=>{observer.disconnect();for(const root of roots)for(const event of events)root.removeEventListener(event,dirty,true);if(host.__nextshotFrameProof===saved)delete host.__nextshotFrameProof;}};
    host.__nextshotFrameProof=saved;
    for(const root of roots)for(const event of events)root.addEventListener(event,dirty,true);
    const options={subtree:true,attributes:true,childList:true,characterData:true};observer.observe(document.documentElement,options);
    for(const root of new Set(nodes().map(e=>e.getRootNode())))if(root instanceof ShadowRoot)observer.observe(root,options);
    setTimeout(()=>saved.stop(),1500);return proof;
  }catch{if(host.__nextshotFrameProof?.token===token)host.__nextshotFrameProof.stop();return;}
}
