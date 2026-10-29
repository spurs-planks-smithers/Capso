export type MarkKind='dot'|'arrow'|'box';
export interface Mark {id:number;kind:MarkKind;x:number;y:number;endX?:number;endY?:number;note:string;}
export interface Bounds {x:number;y:number;width:number;height:number;}
export interface ElementEvidence {id:string;selector:string;tag:string;role?:string;text?:string;bounds:Bounds;frameURL?:string;source?:string;}
export interface ActionEvent {at:number;kind:string;label:string;elementId?:string;}
export interface Diagnostic {at:number;kind:'error'|'request'|'coverage'|'gap';text:string;url?:string;method?:string;status?:number;duration?:number;}
export interface Clip {start:number;end:number;issue:number;steps:ActionEvent[];mediaFile?:string;mime?:string;}
export interface Capture {
  id:string;kind:'capture'|'rolling';createdAt:string;title:string;url?:string;
  width:number;height:number;imageFile:string;cleanImageFile:string;
  marks:Mark[];note:string;elements:ElementEvidence[];actions:ActionEvent[];diagnostics:Diagnostic[];
  viewport?:{width:number;height:number;scale:number;scrollX:number;scrollY:number;cropX:number;cropY:number};
  clip?:Clip;
}
export interface Round {schema:'nextshot.browser';schemaVersion:1;id:string;name:string;createdAt:string;endedAt?:string;captures:Capture[];}
export interface Asset {name:string;mime:string;bytes:Uint8Array;}
export interface Draft {capture:Capture;assets:Asset[];}

export function newRound():Round {
  const now=new Date().toISOString();
  return {schema:'nextshot.browser',schemaVersion:1,id:crypto.randomUUID(),name:'Browser feedback',createdAt:now,captures:[]};
}
export function newCapture(input:{url?:string;title:string;width:number;height:number}):Capture {
  const id=crypto.randomUUID();
  return {id,kind:'capture',createdAt:new Date().toISOString(),title:input.title.slice(0,200),url:input.url,
    width:input.width,height:input.height,imageFile:`${id}.jpg`,cleanImageFile:`${id}-clean.jpg`,marks:[],note:'',elements:[],actions:[],diagnostics:[]};
}
export function eventsWithin<T extends {at:number}>(events:T[],start:number,end:number):T[] {
  if(!Number.isFinite(start)||!Number.isFinite(end)||start<0||end<start)throw new Error('Invalid selected range');
  return events.filter(e=>Number.isFinite(e.at)&&e.at>=start&&e.at<=end);
}
