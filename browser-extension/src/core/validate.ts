import type {Capture,Round} from './model.ts';
import {sanitizeText,redactSensitive,sanitizeURL,safeFileName} from './sanitize.ts';

function finite(value:unknown,min=0,max=100000):number {
  if(typeof value!=='number'||!Number.isFinite(value)||value<min||value>max)throw new Error('Invalid evidence coordinate');
  return value;
}
export function validateCapture(input:unknown):Capture {
  if(!input||typeof input!=='object')throw new Error('Missing capture');
  const c=input as Capture;
  if(typeof c.id!=='string'||!/^[a-f0-9-]{36}$/.test(c.id))throw new Error('Invalid capture identity');
  if(!['capture','rolling'].includes(c.kind)||!Number.isFinite(Date.parse(c.createdAt)))throw new Error('Invalid capture');
  if(!Array.isArray(c.marks)||c.marks.length>100||!Array.isArray(c.elements)||c.elements.length>2000)throw new Error('Too much evidence');
  if(!Array.isArray(c.actions)||c.actions.length>2000||!Array.isArray(c.diagnostics)||c.diagnostics.length>1000)throw new Error('Too many events');
  if(!/\.(?:jpg|jpeg|png|webp)$/.test(c.imageFile)||!/\.(?:jpg|jpeg|png|webp)$/.test(c.cleanImageFile))throw new Error('Unsupported image asset');
  if(![c.imageFile,c.cleanImageFile].every(name=>name.startsWith(`${c.id}.`)||name.startsWith(`${c.id}-`)))throw new Error('Asset does not belong to capture');
  const width=finite(c.width,1,20000),height=finite(c.height,1,20000);
  const result:Capture={id:c.id,kind:c.kind,createdAt:c.createdAt,title:redactSensitive(c.title,200),url:sanitizeURL(c.url),
    width,height,imageFile:safeFileName(c.imageFile),cleanImageFile:safeFileName(c.cleanImageFile),note:sanitizeText(c.note,20000),
    marks:c.marks.map((m,i)=>{
      if(!['dot','arrow','box'].includes(m.kind)||m.id!==i+1)throw new Error('Invalid annotation');
      if(m.elementId&&!c.elements.some(e=>e.id===m.elementId))throw new Error('Unknown annotation element');
      return {id:m.id,kind:m.kind,x:finite(m.x,0,width),y:finite(m.y,0,height),endX:m.endX===undefined?undefined:finite(m.endX,0,width),endY:m.endY===undefined?undefined:finite(m.endY,0,height),note:sanitizeText(m.note,10000),elementId:m.elementId};
    }),
    elements:c.elements.map(e=>({id:sanitizeText(e.id,100),selector:redactSensitive(e.selector,500),tag:sanitizeText(e.tag,30),role:sanitizeText(e.role,60),text:redactSensitive(e.text,300),
      bounds:{x:finite(e.bounds.x,-100000),y:finite(e.bounds.y,-100000),width:finite(e.bounds.width,0),height:finite(e.bounds.height,0)},frameURL:sanitizeURL(e.frameURL),source:undefined})),
    actions:c.actions.map(a=>({at:finite(a.at,0,86400000),kind:sanitizeText(a.kind,40),label:redactSensitive(a.label,200),elementId:sanitizeText(a.elementId,100)})),
    diagnostics:c.diagnostics.map(d=>{
      if(!['error','request','coverage','gap'].includes(d.kind))throw new Error('Invalid diagnostic');
      return {at:finite(d.at,0,86400000),kind:d.kind,text:redactSensitive(d.text,1000),url:sanitizeURL(d.url),method:sanitizeText(d.method,12),status:d.status===undefined?undefined:finite(d.status,0,999),duration:d.duration===undefined?undefined:finite(d.duration,0,86400000)};
    })};
  if(c.viewport)result.viewport={width:finite(c.viewport.width,1),height:finite(c.viewport.height,1),scale:finite(c.viewport.scale,0.1,10),scrollX:finite(c.viewport.scrollX,-100000),scrollY:finite(c.viewport.scrollY,-100000),cropX:finite(c.viewport.cropX),cropY:finite(c.viewport.cropY)};
  if(c.clip){
    const {start,end,issue}=c.clip;finite(start,0,86400000);finite(end,start,86400000);finite(issue,start,end);
    if(c.clip.mediaFile&&!/\.(?:webm|mp4|gif)$/.test(c.clip.mediaFile))throw new Error('Unsupported animation asset');
    if(c.clip.mediaFile&&!c.clip.mediaFile.startsWith(`${c.id}-`))throw new Error('Animation does not belong to capture');
    result.clip={start,end,issue,steps:c.clip.steps.filter(e=>e.at>=start&&e.at<=end).slice(0,100).map(e=>({at:e.at,kind:sanitizeText(e.kind,40),label:redactSensitive(e.label,200),elementId:sanitizeText(e.elementId,100)})),mediaFile:c.clip.mediaFile?safeFileName(c.clip.mediaFile):undefined,mime:sanitizeText(c.clip.mime,80)};
    result.actions=result.actions.filter(e=>e.at>=start&&e.at<=end);
    result.diagnostics=result.diagnostics.filter(e=>e.at>=start&&e.at<=end);
  }
  return result;
}
export function validateRound(input:unknown):Round {
  const r=input as Round;
  if(!r||r.schema!=='nextshot.browser'||r.schemaVersion!==1||typeof r.id!=='string'||!/^[a-f0-9-]{36}$/.test(r.id)||!Array.isArray(r.captures)||r.captures.length>500)throw new Error('Unsupported browser round');
  if(!Number.isFinite(Date.parse(r.createdAt)))throw new Error('Invalid round time');
  if(r.endedAt&&!Number.isFinite(Date.parse(r.endedAt)))throw new Error('Invalid round end');
  const captures=r.captures.map(validateCapture);
  if(new Set(captures.map(c=>c.id)).size!==captures.length)throw new Error('Duplicate capture');
  return {schema:r.schema,schemaVersion:1,id:r.id,name:sanitizeText(r.name,200),createdAt:r.createdAt,endedAt:r.endedAt,captures};
}
