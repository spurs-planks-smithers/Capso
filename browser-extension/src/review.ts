import type {AssistInput,AssistResult} from './assistance.ts';
import {getDraft,saveDraft,discardDraft,saveCapture,roundById,assetsForRound,renderPrompt,exportBundle,validateCapture} from './core/index.ts';
import type {Capture,Asset,Mark,MarkKind,ElementEvidence,Round} from './core/model.ts';
import {deliverNative} from './native.ts';
const $=<T extends HTMLElement=HTMLElement>(selector:string)=>document.querySelector<T>(selector)!;
const canvas=$<HTMLCanvasElement>('#canvas'),context=canvas.getContext('2d')!;
const note=$<HTMLTextAreaElement>('#note'),status=$('#status'),save=$<HTMLButtonElement>('#save');
let capture:Capture,assets:Asset[]=[],image:ImageBitmap,selected=0,tool:MarkKind='dot',saved:Round|undefined,saving=false;
const history:Mark[][]=[],redo:Mark[][]=[];let down:{x:number;y:number}|undefined;
let loaded=false,closing=false,draftRevision=0,queuedRevision=0,writtenRevision=0,draftTimer:ReturnType<typeof setTimeout>|undefined;
let draftQueue=Promise.resolve();
let assistanceRevision=0,assistanceRequest:string|undefined;
function cancelElementAssistance():void{assistanceRevision++;document.querySelectorAll('.assist-badge').forEach(el=>el.remove());const button=document.getElementById('suggest-match') as HTMLButtonElement|null;if(button){button.disabled=false;button.textContent='Suggest a match';}if(assistanceRequest){void chrome.runtime.sendMessage({type:'nextshot-assistance',action:'cancel',requestID:assistanceRequest}).catch(()=>{});assistanceRequest=undefined;}}
addEventListener('pagehide',()=>{cancelElementAssistance();void persistDraft().catch(()=>{});});
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden')void persistDraft().catch(()=>{});});
async function suggestElements(candidates:ElementEvidence[],button:HTMLButtonElement):Promise<void>{
  if(saving||saved)return;cancelElementAssistance();const revision=assistanceRevision,mark=selected,requestID=crypto.randomUUID();assistanceRequest=requestID;button.disabled=true;button.textContent='Checking selected text...';
  const rows=candidates.map((element,index)=>({id:`e${index}`,role:element.role||element.tag||'element',label:element.text||element.tag||'Unlabeled'}));
  const selection:AssistInput={purpose:'elements',requestID,selectionVersion:revision,timeline:[],diagnostics:[],candidates:rows,reviewerNote:note.value};
  try{const result:AssistResult=await chrome.runtime.sendMessage({type:'nextshot-assistance',action:'refine',selection});if(revision!==assistanceRevision||selected!==mark||saving||saved)return;
    button.textContent=result.reason==='insufficient_context'?'Add a note and allow reviewer notes in settings.':result.available&&result.ids.length?'Suggestions shown. Choose a match.':'Local matches remain available.';
    if(result.available)for(const [index,element] of candidates.entries()){const option=document.querySelector<HTMLButtonElement>(`[data-assist-element="${index}"]`);if(option&&result.ids.includes(`e${index}`)){const badge=document.createElement('small');badge.className='assist-badge';badge.textContent=` Suggested by ${result.source==='apple'?'Apple':'Jev'}`;option.append(badge);}}
  }catch{if(revision===assistanceRevision)button.textContent='Local matches remain available.';}finally{if(assistanceRequest===requestID)assistanceRequest=undefined;if(revision===assistanceRevision&&button.isConnected)button.disabled=false;}
}

function remember():void{history.push(structuredClone(capture.marks));redo.length=0;}
const journalKey=(id:string)=>`nextshot-editor:${id}`;
function clearJournal(id:string):void{try{sessionStorage.removeItem(journalKey(id));}catch{}}
function writeJournal():void{
  try{sessionStorage.setItem(journalKey(capture.id),JSON.stringify({imageFile:capture.imageFile,marks:capture.marks.map(m=>({...m,note:m.note.slice(0,10000)})),note:capture.note.slice(0,20000)}));}catch{}
}
function restoreJournal():boolean{
  try{const raw=sessionStorage.getItem(journalKey(capture.id));if(!raw)return false;const edits=JSON.parse(raw);if(edits.imageFile!==capture.imageFile)throw Error();capture=validateCapture({...capture,marks:edits.marks,note:edits.note});return true;}
  catch{clearJournal(capture.id);return false;}
}
function scheduleDraft():void{
  if(!loaded||saved||saving||closing)return;draftRevision++;writeJournal();
  if(draftTimer!==undefined)clearTimeout(draftTimer);
  draftTimer=setTimeout(()=>{draftTimer=undefined;void persistDraft().catch(()=>{if(!saved&&!saving&&!closing)status.textContent='Your latest edits are still open. Use Done to try saving again.';});},300);
}
function persistDraft():Promise<void>{
  if(draftTimer!==undefined){clearTimeout(draftTimer);draftTimer=undefined;}
  if(!loaded||saved||closing||draftRevision<=queuedRevision)return draftQueue;
  const revision=draftRevision,draft={capture:structuredClone(capture),assets};queuedRevision=revision;
  draftQueue=draftQueue.catch(()=>{}).then(()=>saveDraft(draft)).then(()=>{writtenRevision=revision;if(draftRevision===revision)clearJournal(capture.id);},error=>{if(queuedRevision===revision)queuedRevision=writtenRevision;throw error;});
  return draftQueue;
}
function saveNote():void {
  if(!loaded||saved||saving||closing)return;
  const mark=selected?capture.marks.find(m=>m.id===selected):undefined;
  if(selected&&!mark)return;
  if((mark?mark.note:capture.note)===note.value)return;
  if(mark)mark.note=note.value;else capture.note=note.value;scheduleDraft();
}
function markName(mark:Mark):string{return `${mark.kind==='dot'?'Dot':'Mark'} ${mark.id}`;}
function select(id:number,saveCurrent=true):void {
  if(saving||closing)return;cancelElementAssistance();if(saveCurrent)saveNote();
  selected=capture.marks.some(m=>m.id===id)?id:0;
  const mark=capture.marks.find(m=>m.id===selected);note.value=mark?.note??capture.note;
  note.maxLength=mark?10000:20000;
  $('#note-label').textContent=mark?`${markName(mark)}: what should change?`:'General note (optional)';
  renderControls();showElements();draw();
}
function renderControls():void{
  const tabs=$('#mark-tabs');tabs.replaceChildren();tabs.hidden=!capture.marks.length;
  for(const mark of capture.marks){const button=document.createElement('button');button.textContent=markName(mark);button.setAttribute('aria-pressed',String(selected===mark.id));button.disabled=saving||closing;button.onclick=()=>{select(mark.id);if(!saved)note.focus();};tabs.append(button);}
  const general=document.createElement('button');general.textContent='General note';general.setAttribute('aria-pressed',String(selected===0));general.disabled=saving||closing;general.onclick=()=>{select(0);if(!saved)note.focus();};tabs.append(general);
  for(const button of document.querySelectorAll<HTMLButtonElement>('[data-tool]'))button.disabled=!!saved||saving||closing;
  $('#undo').toggleAttribute('disabled',!!saved||saving||closing||!history.length);
  $('#redo').toggleAttribute('disabled',!!saved||saving||closing||!redo.length);
  note.readOnly=!!saved||saving||closing;save.disabled=!!saved||saving||closing;save.hidden=!!saved;
  $('#cancel').toggleAttribute('disabled',saving||closing);$('#cancel').textContent=saved?'Close':'Cancel';
  $('#saved-actions').hidden=!saved;
}
function markPoint(mark:Mark):{x:number;y:number}{
  return {x:mark.kind==='arrow'?mark.endX??mark.x:mark.kind==='box'?(mark.x+(mark.endX??mark.x))/2:mark.x,
    y:mark.kind==='arrow'?mark.endY??mark.y:mark.kind==='box'?(mark.y+(mark.endY??mark.y))/2:mark.y};
}
function matches(mark:Mark):ElementEvidence[] {
  const {x,y}=markPoint(mark);
  const elements=capture.elements.filter(e=>e.tag!=='html'&&e.tag!=='body');
  const inside=(e:ElementEvidence)=>x>=e.bounds.x&&x<=e.bounds.x+e.bounds.width&&y>=e.bounds.y&&y<=e.bounds.y+e.bounds.height;
  const meaningful=(e:ElementEvidence)=>!!(e.text?.trim()||e.role||['input','textarea','select'].includes(e.tag));
  const area=(e:ElementEvidence)=>e.bounds.width*e.bounds.height;
  const direct=elements.filter(inside).sort((a,b)=>area(a)-area(b));
  const interactive=direct.filter(e=>['button','a'].includes(e.tag)||['button','link','tab','menuitem'].includes(e.role??''));
  const named=direct.filter(e=>e.text?.trim()||['input','textarea','select'].includes(e.tag)||e.role==='textbox');
  if(interactive.length||named.length)return(interactive.length?interactive:named).slice(0,4);
  const distance=(e:ElementEvidence)=>Math.hypot(Math.max(e.bounds.x-x,0,x-e.bounds.x-e.bounds.width),Math.max(e.bounds.y-y,0,y-e.bounds.y-e.bounds.height));
  const radius=24*(capture.viewport?.scale??1);
  const nearby=elements.filter(e=>!inside(e)&&meaningful(e)&&distance(e)<=radius).sort((a,b)=>distance(a)-distance(b)||area(a)-area(b));
  const roleOnly=direct.filter(meaningful);
  return(nearby.length?nearby:roleOnly.length?roleOnly:direct).slice(0,4);
}
function reconcileMatches():void{
  if(saved)return;let changed=false;
  for(const mark of capture.marks){
    if(mark.elementId&&capture.elements.some(e=>e.id===mark.elementId))continue;
    const candidates=matches(mark),id=candidates.length===1?candidates[0].id:undefined;
    if(mark.elementId!==id){mark.elementId=id;changed=true;}
  }
  if(changed)scheduleDraft();
}
function elementName(element:ElementEvidence):string{
  const text=element.text?.trim().replace(/\s+/g,' ').slice(0,100);
  const kind=['input','textarea','select'].includes(element.tag)||element.role==='textbox'?'Form field':element.tag==='button'||element.role==='button'?'Button':element.tag==='a'||element.role==='link'?'Link':element.tag==='img'?'Image':'Page item';
  return text&&kind!=='Form field'?`${kind}: ${text}`:kind;
}
function showElements():void {
  const container=$('#elements'),choices=$('#target-choices');container.replaceChildren();choices.replaceChildren();$('#target-question').hidden=true;
  const mark=capture.marks.find(m=>m.id===selected);
  if(!mark){$('#element-hint').textContent='Page information is included automatically when available.';return;}
  const candidates=matches(mark),chosen=capture.elements.find(e=>e.id===mark.elementId);
  const optional=candidates.length>1&&!chosen&&!saved;$('#target-question').hidden=!optional;
  if(chosen){const {x,y}=markPoint(mark),b=chosen.bounds;$('#element-hint').textContent=x<b.x||x>b.x+b.width||y<b.y||y>b.y+b.height?'Suggested from a nearby page element.':'Matched from your mark.';}
  else $('#element-hint').textContent='Your image and note are included, even without a page match.';
  if(chosen&&!candidates.some(e=>e.id===chosen.id))candidates.unshift(chosen);
  for(const [index,element] of candidates.entries()){
    const button=document.createElement('button');button.dataset.assistElement=String(index);button.className='element-option';button.setAttribute('aria-pressed',String(mark.elementId===element.id));button.textContent=elementName(element);button.disabled=!!saved||saving||closing;
    button.onclick=()=>{if(saving||saved||closing)return;cancelElementAssistance();mark.elementId=element.id;scheduleDraft();showElements();};(optional?choices:container).append(button);
    const detail=document.createElement('p'),label=document.createElement('span'),selector=document.createElement('code');label.textContent=elementName(element);selector.textContent=element.selector;detail.append(label,selector);container.append(detail);
  }
  if(candidates.length>1&&!saved){const button=document.createElement('button');button.id='suggest-match';button.hidden=true;button.textContent='Suggest a match';button.disabled=saving||closing;button.onclick=()=>{void suggestElements(candidates,button);};(optional?choices:container).append(button);void chrome.storage.local.get('assistanceMode').then(v=>{if(button.isConnected)button.hidden=!['apple','jev'].includes(String(v.assistanceMode));}).catch(()=>{});}
}
function draw(highlight=true):void {
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
  const mark=capture.marks.find(m=>m.id===selected);
  if(highlight&&mark){context.strokeStyle='#2d66bc';context.lineWidth=Math.max(2,line);context.beginPath();context.arc(mark.x,mark.y,radius+line*2,0,Math.PI*2);context.stroke();}
  $('#hint').textContent=saved?'Your feedback is saved. Copy or export it when ready.':capture.marks.length?`Done saves and copies your feedback. ${/Mac/i.test(navigator.platform)?'Command':'Ctrl'}+S also works.`:'Click the image to add your first dot, then describe the change.';
}
function point(event:PointerEvent):{x:number;y:number}{const rect=canvas.getBoundingClientRect();return{x:Math.max(0,Math.min(canvas.width,(event.clientX-rect.left)*canvas.width/rect.width)),y:Math.max(0,Math.min(canvas.height,(event.clientY-rect.top)*canvas.height/rect.height))};}
canvas.onpointerdown=e=>{if(saving||closing)return;down=point(e);canvas.setPointerCapture(e.pointerId);};
canvas.onpointerup=e=>{
  if(saving||closing||!down)return;const start=down,end=point(e);down=undefined;
  const radius=Math.max(12,canvas.width/70),hit=[...capture.marks].reverse().find(m=>Math.hypot(m.x-end.x,m.y-end.y)<=radius*1.35);
  if(hit&&Math.hypot(start.x-end.x,start.y-end.y)<=radius){select(hit.id);if(!saved)note.focus();return;}
  if(saved||capture.marks.length>=100)return;
  saveNote();remember();const id=capture.marks.length+1;
  capture.marks.push({id,kind:tool,x:start.x,y:start.y,...(tool!=='dot'?{endX:end.x,endY:end.y}:{}),note:''});reconcileMatches();scheduleDraft();select(id,false);note.focus();
};
for(const button of document.querySelectorAll<HTMLButtonElement>('[data-tool]'))button.onclick=()=>{if(saved||saving||closing)return;tool=button.dataset.tool as MarkKind;for(const b of document.querySelectorAll('[data-tool]'))b.setAttribute('aria-pressed',String(b===button));};
$('#undo').onclick=()=>{if(!history.length||saved||saving||closing)return;saveNote();redo.push(structuredClone(capture.marks));capture.marks=history.pop()!;reconcileMatches();scheduleDraft();select(capture.marks.at(-1)?.id??0,false);};
$('#redo').onclick=()=>{if(!redo.length||saved||saving||closing)return;saveNote();history.push(structuredClone(capture.marks));capture.marks=redo.pop()!;reconcileMatches();scheduleDraft();select(capture.marks.at(-1)?.id??0,false);};
note.oninput=()=>{cancelElementAssistance();saveNote();};
save.onclick=async()=>{
  if(saved||saving||closing)return;cancelElementAssistance();saveNote();reconcileMatches();saving=true;renderControls();showElements();status.textContent='Saving feedback...';
  try{
    await persistDraft();draw(false);
    const annotated=await new Promise<Blob>((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(new Error('Cannot save annotated image')),'image/jpeg',.88));
    assets=assets.filter(a=>a.name!==capture.imageFile);assets.push({name:capture.imageFile,mime:annotated.type,bytes:new Uint8Array(await annotated.arrayBuffer())});
    capture=validateCapture(capture);saved=await saveCapture(capture,assets);clearJournal(capture.id);status.textContent='Feedback saved in this browser.';
    void chrome.runtime.sendMessage({type:'nextshot-forget-draft',id:capture.id}).catch(()=>{});
    try{await navigator.clipboard.writeText(renderPrompt(saved));status.textContent='Saved. Prompt copied. Paste it into your agent.';}catch{status.textContent='Feedback saved. Use Copy prompt or Export round to share it.';}
    void deliverNative(capture,assets).then(receipt=>{if(receipt)$('#delivery-status').textContent=receipt.state==='imported'?'Also saved in Nextshot Dev.':'Saved here. Nextshot Dev is unavailable.';}).catch(()=>{$('#delivery-status').textContent='Saved here. Nextshot Dev could not receive it.';});
  }catch(error){status.textContent=error instanceof Error?error.message:'Save failed. Your draft remains available.';}
  finally{saving=false;renderControls();showElements();draw();}
};
$('#copy').onclick=async()=>{if(saved){try{await navigator.clipboard.writeText(renderPrompt(saved));status.textContent='Prompt copied.';}catch{status.textContent='Your feedback is saved. Clipboard access is unavailable. Export the round to share it.';}}};
$('#export').onclick=async()=>{
  if(!saved)return;
  try{const bytes=exportBundle(saved,await assetsForRound(saved));const url=URL.createObjectURL(new Blob([new Uint8Array(bytes).buffer],{type:'application/zip'}));const a=document.createElement('a');a.href=url;a.download=`nextshot-round-${saved.createdAt.slice(0,16).replace(/[:T]/g,'-')}.zip`;a.click();setTimeout(()=>URL.revokeObjectURL(url),60000);status.textContent='Export download started.';}
  catch(error){status.textContent=error instanceof Error?error.message:'Export failed.';}
};
$('#cancel').onclick=async()=>{
  if(saving||closing)return;cancelElementAssistance();closing=true;renderControls();
  if(draftTimer!==undefined){clearTimeout(draftTimer);draftTimer=undefined;}
  try{await draftQueue.catch(()=>{});if(capture&&!saved)await discardDraft(capture.id);clearJournal(capture.id);window.close();}
  catch{closing=false;renderControls();scheduleDraft();status.textContent='The capture is still open. Try Cancel again when ready.';}
};
document.onkeydown=e=>{if((e.metaKey||e.ctrlKey)&&e.key==='s'){e.preventDefault();save.click();}if(e.target instanceof HTMLTextAreaElement||e.target instanceof HTMLInputElement)return;if(e.key==='ArrowLeft'){$('#undo').click();e.preventDefault();}if(e.key==='ArrowRight'){$('#redo').click();e.preventDefault();}if(e.key==='Escape')$('#cancel').click();};
async function load():Promise<void> {
  const query=new URLSearchParams(location.search),draftId=query.get('draft'),roundId=query.get('round');
  if(roundId){saved=await roundById(roundId);if(!saved?.captures.length)throw new Error('Round unavailable');capture=saved.captures.at(-1)!;assets=await assetsForRound(saved);}
  else{const draft=draftId?await getDraft(draftId):undefined;if(!draft){if(draftId)clearJournal(draftId);throw new Error('This unsaved capture is no longer available.');}capture=draft.capture;assets=draft.assets;}
  const clean=assets.find(a=>a.name===capture.cleanImageFile);if(!clean)throw new Error('Image unavailable');
  image=await createImageBitmap(new Blob([new Uint8Array(clean.bytes).buffer],{type:clean.mime}));canvas.width=capture.width;canvas.height=capture.height;
  $('#page-title').textContent=capture.title||'Browser feedback';
  if(capture.clip){
    const media=assets.find(a=>a.name===capture.clip?.mediaFile);
    const details=document.createElement('section'),label=document.createElement('p');label.textContent='Selected sampled evidence. Frames can contain gaps. Diagnostics cover only observed page errors and resource completions.';details.append(label);
    if(media){const video=media.mime==='image/gif'?document.createElement('img'):document.createElement('video');if(video instanceof HTMLVideoElement){video.controls=true;video.muted=true;}video.style.maxWidth='100%';const url=URL.createObjectURL(new Blob([new Uint8Array(media.bytes).buffer],{type:media.mime}));video.src=url;details.append(video);addEventListener('pagehide',()=>URL.revokeObjectURL(url),{once:true});}
    const events=document.createElement('ul');for(const e of [...capture.actions,...capture.diagnostics].sort((a,b)=>a.at-b.at)){const item=document.createElement('li');item.textContent=`${(e.at/1000).toFixed(1)}s: ${'label' in e?e.label:e.text}`;events.append(item);}details.append(events);status.after(details);
  }
  const recovered=!saved&&restoreJournal();loaded=true;if(recovered)scheduleDraft();reconcileMatches();select(capture.marks[0]?.id??0,false);
}
void load().catch(error=>{status.textContent=error.message;save.disabled=true;});

chrome.runtime.onMessage.addListener(m=>{if(m.type==='nextshot-rolling-invalidated'&&capture?.kind==='rolling'&&!saved){
  closing=true;if(draftTimer!==undefined){clearTimeout(draftTimer);draftTimer=undefined;}clearJournal(capture.id);assets=[];image?.close();
  void draftQueue.catch(()=>{}).then(()=>discardDraft(capture.id)).finally(()=>location.replace(chrome.runtime.getURL('rolling.html'))).catch(()=>{});
}});
