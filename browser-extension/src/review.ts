import {getDraft,saveDraft,discardDraft,saveCapture,roundById,assetsForRound,renderPrompt,exportBundle,validateCapture} from './core/index.ts';
import type {Capture,Asset,Mark,MarkKind,ElementEvidence,Round} from './core/model.ts';
import {deliverNative} from './native.ts';
const $=<T extends HTMLElement=HTMLElement>(selector:string)=>document.querySelector<T>(selector)!;
const canvas=$<HTMLCanvasElement>('#canvas'),context=canvas.getContext('2d')!;
const note=$<HTMLTextAreaElement>('#note'),status=$('#status'),save=$<HTMLButtonElement>('#save');
let capture:Capture,assets:Asset[]=[],image:ImageBitmap,selected=0,tool:MarkKind='dot',saved:Round|undefined,saving=false;
const history:Mark[][]=[],redo:Mark[][]=[];let down:{x:number;y:number}|undefined;
const choices=new Map<number,string>();
function remember():void{history.push(structuredClone(capture.marks));redo.length=0;}
function saveNote():void {if(!capture)return;if(selected)capture.marks[selected-1].note=note.value;else capture.note=note.value;}
function select(id:number):void {if(saving)return;saveNote();selected=id;note.value=id?capture.marks[id-1]?.note??'':capture.note;$('#note-label').textContent=id?`Mark ${id}: what should change?`:'General note';showElements();}
function matches(mark:Mark):ElementEvidence[] {
  const x=mark.kind==='arrow'?mark.endX??mark.x:mark.kind==='box'?(mark.x+(mark.endX??mark.x))/2:mark.x;
  const y=mark.kind==='arrow'?mark.endY??mark.y:mark.kind==='box'?(mark.y+(mark.endY??mark.y))/2:mark.y;
  const candidates=capture.elements.filter(e=>x>=e.bounds.x&&x<=e.bounds.x+e.bounds.width&&y>=e.bounds.y&&y<=e.bounds.y+e.bounds.height)
    .sort((a,b)=>a.bounds.width*a.bounds.height-b.bounds.width*b.bounds.height).filter(e=>e.tag!=='html'&&e.tag!=='body');
  const interactive=candidates.filter(e=>['button','a'].includes(e.tag)||['button','link','tab','menuitem'].includes(e.role??''));
  return (interactive.length?interactive:candidates).slice(0,4);
}
function showElements():void {
  const container=$('#elements');container.replaceChildren();
  if(!selected){$('#element-hint').textContent='Element details follow your mark.';return;}
  const candidates=matches(capture.marks[selected-1]);$('#element-hint').textContent=candidates.length>1?'Choose the element you mean.':candidates.length?'Matched from your mark.':'No reliable element match. The image and note remain usable.';
  if(candidates.length===1&&!choices.has(selected)){choices.set(selected,candidates[0].id);capture.marks[selected-1].elementId=candidates[0].id;}
  for(const element of candidates){
    const button=document.createElement('button');button.className='element-option'+(choices.get(selected)===element.id?' selected':'');button.textContent=element.selector+(element.text?`\n${element.text}`:'');
    button.onclick=()=>{if(saving||saved)return;choices.set(selected,element.id);capture.marks[selected-1].elementId=element.id;showElements();};container.append(button);
  }
}
function draw():void {
  if(!image)return;context.clearRect(0,0,canvas.width,canvas.height);context.drawImage(image,0,0);
  const line=Math.max(2,canvas.width/500),radius=Math.max(12,canvas.width/70);
  context.strokeStyle='#df3037';context.fillStyle='#df3037';context.lineWidth=line;context.lineCap='round';
  for(const mark of capture.marks){
    if(mark.kind==='box'){context.strokeRect(mark.x,mark.y,(mark.endX??mark.x)-mark.x,(mark.endY??mark.y)-mark.y);}
    if(mark.kind==='arrow'){
      const x=mark.endX??mark.x,y=mark.endY??mark.y,angle=Math.atan2(y-mark.y,x-mark.x),size=radius;
      context.beginPath();context.moveTo(mark.x,mark.y);context.lineTo(x,y);context.moveTo(x-size*Math.cos(angle-.45),y-size*Math.sin(angle-.45));context.lineTo(x,y);context.lineTo(x-size*Math.cos(angle+.45),y-size*Math.sin(angle+.45));context.stroke();
    }
    context.beginPath();context.arc(mark.x,mark.y,radius,0,Math.PI*2);context.fill();context.fillStyle='#fff';context.font=`600 ${radius*1.1}px -apple-system,sans-serif`;context.textAlign='center';context.textBaseline='middle';context.fillText(String(mark.id),mark.x,mark.y);context.fillStyle='#df3037';
  }
  $('#hint').textContent=capture.marks.length?'Add more marks, then save your notes. Command+S saves.':'Click to add your first numbered mark.';
}
function point(event:PointerEvent):{x:number;y:number}{const rect=canvas.getBoundingClientRect();return{x:Math.max(0,Math.min(canvas.width,(event.clientX-rect.left)*canvas.width/rect.width)),y:Math.max(0,Math.min(canvas.height,(event.clientY-rect.top)*canvas.height/rect.height))};}
canvas.onpointerdown=e=>{if(saved||saving)return;down=point(e);canvas.setPointerCapture(e.pointerId);};
canvas.onpointerup=e=>{
  if(saved||saving||!down||capture.marks.length>=100)return;
  saveNote();remember();const end=point(e),id=capture.marks.length+1;
  capture.marks.push({id,kind:tool,x:down.x,y:down.y,...(tool!=='dot'?{endX:end.x,endY:end.y}:{}),note:''});down=undefined;select(id);draw();note.focus();
};
for(const button of document.querySelectorAll<HTMLButtonElement>('[data-tool]'))button.onclick=()=>{tool=button.dataset.tool as MarkKind;for(const b of document.querySelectorAll('[data-tool]'))b.setAttribute('aria-pressed',String(b===button));};
$('#undo').onclick=()=>{if(!history.length||saved||saving)return;saveNote();redo.push(structuredClone(capture.marks));capture.marks=history.pop()!;selected=0;note.value=capture.note;choices.clear();select(0);draw();};
$('#redo').onclick=()=>{if(!redo.length||saved||saving)return;saveNote();history.push(structuredClone(capture.marks));capture.marks=redo.pop()!;selected=0;note.value=capture.note;select(capture.marks.length);draw();};
$('#previous').onclick=()=>select(selected>1?selected-1:0);$('#next').onclick=()=>select(selected<capture.marks.length?selected+1:0);$('#general').onclick=()=>select(0);
note.oninput=()=>saveNote();
save.onclick=async()=>{
  if(saved||saving)return;save.disabled=true;saveNote();saving=true;note.readOnly=true;status.textContent='Saving feedback...';
  try{
    const annotated=await new Promise<Blob>((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(new Error('Cannot save annotated image')),'image/jpeg',.88));
    assets=assets.filter(a=>a.name!==capture.imageFile);assets.push({name:capture.imageFile,mime:annotated.type,bytes:new Uint8Array(await annotated.arrayBuffer())});
    capture=validateCapture(capture);saved=await saveCapture(capture,assets);await chrome.runtime.sendMessage({type:'nextshot-forget-draft',id:capture.id});
    note.readOnly=true;save.textContent='Saved';$('#saved-actions').hidden=false;$('#cancel').textContent='Done';status.textContent='Feedback saved in this browser.';
    try{await navigator.clipboard.writeText(renderPrompt(saved));status.textContent='Prompt copied. Paste it into your agent.';}catch{status.textContent+=' Use Copy prompt when ready.';}
    void deliverNative(capture,assets).then(receipt=>{if(receipt?.state==='imported')status.textContent='Saved in Nextshot Dev. Prompt copied.';else if(receipt)status.textContent='Saved in this browser. Nextshot Dev is unavailable.';});
  }catch(error){status.textContent=error instanceof Error?error.message:'Save failed. Your draft remains available.';save.disabled=false;note.readOnly=false;}
  finally{saving=false;}
};
$('#copy').onclick=async()=>{if(saved){await navigator.clipboard.writeText(renderPrompt(saved));status.textContent='Prompt copied.';}};
$('#export').onclick=async()=>{
  if(!saved)return;
  try{const bytes=exportBundle(saved,await assetsForRound(saved));const url=URL.createObjectURL(new Blob([new Uint8Array(bytes).buffer],{type:'application/zip'}));const a=document.createElement('a');a.href=url;a.download=`nextshot-round-${saved.createdAt.slice(0,16).replace(/[:T]/g,'-')}.zip`;a.click();setTimeout(()=>URL.revokeObjectURL(url),60000);status.textContent='Round exported.';}
  catch(error){status.textContent=error instanceof Error?error.message:'Export failed.';}
};
$('#cancel').onclick=async()=>{if(saving)return;if(capture&&!saved)await discardDraft(capture.id);window.close();};
document.onkeydown=e=>{if((e.metaKey||e.ctrlKey)&&e.key==='s'){e.preventDefault();save.click();}if(e.target instanceof HTMLTextAreaElement||e.target instanceof HTMLInputElement)return;if(e.key==='ArrowLeft'){$('#undo').click();e.preventDefault();}if(e.key==='ArrowRight'){$('#redo').click();e.preventDefault();}if(e.key==='Escape')$('#cancel').click();};
async function load():Promise<void> {
  const query=new URLSearchParams(location.search),draftId=query.get('draft'),roundId=query.get('round');
  if(roundId){saved=await roundById(roundId);if(!saved?.captures.length)throw new Error('Round unavailable');capture=saved.captures.at(-1)!;assets=await assetsForRound(saved);save.disabled=true;save.textContent='Saved';note.readOnly=true;$('#saved-actions').hidden=false;$('#cancel').textContent='Done';}
  else{const draft=draftId?await getDraft(draftId):undefined;if(!draft)throw new Error('This unsaved capture is no longer available.');capture=draft.capture;assets=draft.assets;}
  const clean=assets.find(a=>a.name===capture.cleanImageFile);if(!clean)throw new Error('Image unavailable');
  image=await createImageBitmap(new Blob([new Uint8Array(clean.bytes).buffer],{type:clean.mime}));canvas.width=capture.width;canvas.height=capture.height;
  $('#page-title').textContent=capture.title||'Browser feedback';
  if(capture.clip){
    const media=assets.find(a=>a.name===capture.clip?.mediaFile);
    const details=document.createElement('section'),label=document.createElement('p');label.textContent='Selected sampled evidence. Frames can contain gaps. Diagnostics cover only observed page errors and resource completions.';details.append(label);
    if(media){const video=media.mime==='image/gif'?document.createElement('img'):document.createElement('video');if(video instanceof HTMLVideoElement){video.controls=true;video.muted=true;}video.style.maxWidth='100%';const url=URL.createObjectURL(new Blob([new Uint8Array(media.bytes).buffer],{type:media.mime}));video.src=url;details.append(video);addEventListener('pagehide',()=>URL.revokeObjectURL(url),{once:true});}
    const events=document.createElement('ul');for(const e of [...capture.actions,...capture.diagnostics].sort((a,b)=>a.at-b.at)){const item=document.createElement('li');item.textContent=`${(e.at/1000).toFixed(1)}s: ${'label' in e?e.label:e.text}`;events.append(item);}details.append(events);status.after(details);
  }
  select(0);draw();
}
void load().catch(error=>{status.textContent=error.message;save.disabled=true;});

chrome.runtime.onMessage.addListener(m=>{if(m.type==='nextshot-rolling-invalidated'&&capture?.kind==='rolling'&&!saved){assets=[];image?.close();location.replace(chrome.runtime.getURL('rolling.html'));}});
