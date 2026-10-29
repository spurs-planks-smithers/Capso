import type {ActionEvent,Diagnostic} from './model.ts';
import {redactSensitive,sanitizeURL} from './sanitize.ts';
export interface HistoryFrame {at:number;width:number;height:number;bytes:Uint8Array;}
/** Independent JPEG frames allow safe eviction without a missing video keyframe. */
export class EvidenceHistory {
  frames:HistoryFrame[]=[];actions:ActionEvent[]=[];diagnostics:Diagnostic[]=[];bytes=0;full=false;
  constructor(readonly duration=60000,readonly byteLimit=24000000,readonly eventLimit=1000,readonly preserveStart=false){}
  addFrame(frame:HistoryFrame):void {if(this.preserveStart&&(this.full||this.bytes+frame.bytes.length>this.byteLimit)){this.full=true;return;}if(frame.bytes.length>this.byteLimit)return;this.frames.push(frame);this.bytes+=frame.bytes.length;this.prune(frame.at);}
  event(at:number,kind:string,label:string):void {
    if(!Number.isFinite(at)||at<0)return;
    if(this.preserveStart&&(this.full||(kind==='click'?this.actions.length:this.diagnostics.length)>=this.eventLimit)){this.full=true;return;}
    if(kind==='click')this.actions.push({at,kind,label:redactSensitive(label,200)});
    else this.diagnostics.push({at,kind:kind==='request'?'request':kind==='gap'?'gap':kind==='coverage'?'coverage':'error',text:kind==='request'?'Observed resource completion. Method, status, headers, and body unavailable.':redactSensitive(label,500),...(kind==='request'?{url:sanitizeURL(label)}:{})});
    this.prune(at);
  }
  prune(now:number):void {if(this.preserveStart)return;while(this.frames.length&&(this.frames[0].at<now-this.duration||this.bytes>this.byteLimit)){this.bytes-=this.frames.shift()!.bytes.length;}this.actions=this.actions.filter(e=>e.at>=now-this.duration).slice(-this.eventLimit);this.diagnostics=this.diagnostics.filter(e=>e.at>=now-this.duration).slice(-this.eventLimit);}
  select(start:number,end:number):{frames:HistoryFrame[];actions:ActionEvent[];diagnostics:Diagnostic[]} {
    if(!Number.isFinite(start)||!Number.isFinite(end)||start<0||end<start)throw Error('Invalid recording range');
    return {frames:this.frames.filter(f=>f.at>=start&&f.at<=end),actions:this.actions.filter(e=>e.at>=start&&e.at<=end),diagnostics:this.diagnostics.filter(e=>e.at>=start&&e.at<=end)};
  }
  limit(at:number,text:string):void {this.full=true;const marker:Diagnostic={at,kind:'coverage',text};if(this.diagnostics.length>=this.eventLimit)this.diagnostics[this.eventLimit-1]=marker;else this.diagnostics.push(marker);}
  clear():void {this.full=false;this.frames=[];this.actions=[];this.diagnostics=[];this.bytes=0;}
}
