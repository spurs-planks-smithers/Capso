import type {ActionEvent,Diagnostic,ElementEvidence} from './model.ts';
import {redactSensitive,sanitizeURL} from './sanitize.ts';
export interface HistoryFrame {at:number;width:number;height:number;bytes:Uint8Array;elements?:ElementEvidence[];url?:string;title?:string;capturedAt?:string;metadataBytes?:number;alerts?:string[];}
const cost=(frame:HistoryFrame)=>frame.bytes.length+(frame.metadataBytes??0);
const eventBytes=(event:ActionEvent|Diagnostic)=>new TextEncoder().encode(JSON.stringify(event)).length;
const resourceText='Some evidence was omitted by browser resource limits.';
/** Independent JPEG frames allow safe eviction without a missing video keyframe. */
export class EvidenceHistory {
  frames:HistoryFrame[]=[];actions:ActionEvent[]=[];private records:Diagnostic[]=[];private frameBytes=0;full=false;
  private loss:{start:number;end:number;text:string}|undefined;
  // One fixed-size control marker survives even zero payload/event budgets.
  get diagnostics():Diagnostic[]{return this.loss?[...this.records,{at:this.loss.end,kind:'coverage',text:this.loss.text}]:this.records;}
  get bytes():number{return this.frameBytes+[...this.actions,...this.records].reduce((n,e)=>n+eventBytes(e),0);}
  readonly duration:number;readonly byteLimit:number;readonly eventLimit:number;readonly preserveStart:boolean;
  constructor(duration=60000,byteLimit=24000000,eventLimit=1000,preserveStart=false){this.duration=duration;this.byteLimit=Math.max(0,byteLimit);this.eventLimit=Math.max(0,eventLimit);this.preserveStart=preserveStart;}
  private resourceLoss(start:number,end:number):void{this.loss={start:Math.min(start,this.loss?.start??start),end:Math.max(end,this.loss?.end??end),text:this.loss?.text??resourceText};}
  private get payloadEvents():number{return Math.max(0,this.eventLimit-(this.loss?1:0));}
  addFrame(frame:HistoryFrame):void {
    this.prune(frame.at);
    if(cost(frame)>this.byteLimit||this.preserveStart&&(this.full||this.bytes+cost(frame)>this.byteLimit)){this.resourceLoss(frame.at,frame.at);if(this.preserveStart)this.full=true;this.prune(frame.at);return;}
    this.frames.push(frame);this.frameBytes+=cost(frame);this.prune(frame.at);
  }
  event(at:number,kind:string,label:string):void {
    if(!Number.isFinite(at)||at<0)return;
    this.prune(at);
    const event:ActionEvent|Diagnostic=kind==='click'?{at,kind,label:redactSensitive(label,200)}:{at,kind:kind==='request'?'request':kind==='gap'?'gap':kind==='coverage'?'coverage':'error',text:kind==='request'?'Observed resource completion. Method, status, headers, and body unavailable.':redactSensitive(label,500),...(kind==='request'?{url:sanitizeURL(label)}:{})};
    if(this.preserveStart&&(this.full||this.actions.length+this.records.length>=this.payloadEvents||this.bytes+eventBytes(event)>this.byteLimit)){this.full=true;this.resourceLoss(at,at);this.trimEvents(at);return;}
    if('label' in event)this.actions.push(event);else this.records.push(event);
    this.prune(at);
  }
  private trimEvents(now:number):void {
    while(this.actions.length+this.records.length>this.payloadEvents||this.bytes>this.byteLimit){
      const action=this.preserveStart?this.actions.at(-1):this.actions[0],record=this.preserveStart?this.records.at(-1):this.records[0];if(!action&&!record)break;
      const takeAction=action&&(!record||(this.preserveStart?action.at>=record.at:action.at<=record.at));
      const dropped=takeAction?(this.preserveStart?this.actions.pop()!:this.actions.shift()!):(this.preserveStart?this.records.pop()!:this.records.shift()!);
      this.resourceLoss(dropped.at,now);
    }
  }
  prune(now:number):void {
    if(!this.preserveStart){
      const cutoff=now-this.duration;
      while(this.frames.length&&this.frames[0].at<cutoff)this.frameBytes-=cost(this.frames.shift()!);
      this.actions=this.actions.filter(e=>e.at>=cutoff);this.records=this.records.filter(e=>e.at>=cutoff);
      if(this.loss&&this.loss.end<cutoff)this.loss=undefined;
      while(this.frames.length&&this.bytes>this.byteLimit){const dropped=this.frames.shift()!;this.frameBytes-=cost(dropped);this.resourceLoss(dropped.at,now);}
    }
    this.trimEvents(now);
  }
  select(start:number,end:number):{frames:HistoryFrame[];actions:ActionEvent[];diagnostics:Diagnostic[]} {
    if(!Number.isFinite(start)||!Number.isFinite(end)||start<0||end<start)throw Error('Invalid recording range');
    const diagnostics=this.records.filter(e=>e.at>=start&&e.at<=end);
    if(this.loss&&start<=this.loss.end&&end>=this.loss.start)diagnostics.push({at:Math.min(end,Math.max(start,this.loss.end)),kind:'coverage',text:this.loss.text});
    return {frames:this.frames.filter(f=>f.at>=start&&f.at<=end),actions:this.actions.filter(e=>e.at>=start&&e.at<=end),diagnostics};
  }
  limit(at:number,text:string):void {this.full=true;this.resourceLoss(at,at);this.loss!.text=redactSensitive(text,500)+' '+resourceText;this.trimEvents(at);}
  clear():void {this.full=false;this.frames=[];this.actions=[];this.records=[];this.frameBytes=0;this.loss=undefined;}
}
