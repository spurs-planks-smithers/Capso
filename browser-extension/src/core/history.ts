import type {ActionEvent,Diagnostic,ElementEvidence} from './model.ts';
import {redactSensitive,sanitizeURL} from './sanitize.ts';
export interface HistoryFrame {at:number;width:number;height:number;bytes:Uint8Array;elements?:ElementEvidence[];url?:string;title?:string;capturedAt?:string;metadataBytes?:number;}
const cost=(frame:HistoryFrame)=>frame.bytes.length+(frame.metadataBytes??0);
/** Independent JPEG frames allow safe eviction without a missing video keyframe. */
export class EvidenceHistory {
  frames:HistoryFrame[]=[];actions:ActionEvent[]=[];diagnostics:Diagnostic[]=[];bytes=0;full=false;
  readonly duration:number;readonly byteLimit:number;readonly eventLimit:number;readonly preserveStart:boolean;
  constructor(duration=60000,byteLimit=24000000,eventLimit=1000,preserveStart=false){this.duration=duration;this.byteLimit=byteLimit;this.eventLimit=eventLimit;this.preserveStart=preserveStart;}
  addFrame(frame:HistoryFrame):void {if(this.preserveStart&&(this.full||this.bytes+cost(frame)>this.byteLimit)){this.full=true;return;}if(cost(frame)>this.byteLimit)return;this.frames.push(frame);this.bytes+=cost(frame);this.prune(frame.at);}
  event(at:number,kind:string,label:string):void {
    if(!Number.isFinite(at)||at<0)return;
    if(this.preserveStart&&(this.full||(kind==='click'?this.actions.length:this.diagnostics.length)>=this.eventLimit)){this.full=true;return;}
    if(kind==='click')this.actions.push({at,kind,label:redactSensitive(label,200)});
    else this.diagnostics.push({at,kind:kind==='request'?'request':kind==='gap'?'gap':kind==='coverage'?'coverage':'error',text:kind==='request'?'Observed resource completion. Method, status, headers, and body unavailable.':redactSensitive(label,500),...(kind==='request'?{url:sanitizeURL(label)}:{})});
    this.prune(at);
  }
  prune(now:number):void {if(this.preserveStart)return;while(this.frames.length&&(this.frames[0].at<now-this.duration||this.bytes>this.byteLimit)){this.bytes-=cost(this.frames.shift()!);}this.actions=this.actions.filter(e=>e.at>=now-this.duration).slice(-this.eventLimit);this.diagnostics=this.diagnostics.filter(e=>e.at>=now-this.duration).slice(-this.eventLimit);}
  select(start:number,end:number):{frames:HistoryFrame[];actions:ActionEvent[];diagnostics:Diagnostic[]} {
    if(!Number.isFinite(start)||!Number.isFinite(end)||start<0||end<start)throw Error('Invalid recording range');
    return {frames:this.frames.filter(f=>f.at>=start&&f.at<=end),actions:this.actions.filter(e=>e.at>=start&&e.at<=end),diagnostics:this.diagnostics.filter(e=>e.at>=start&&e.at<=end)};
  }
  limit(at:number,text:string):void {this.full=true;const marker:Diagnostic={at,kind:'coverage',text};if(this.diagnostics.length>=this.eventLimit)this.diagnostics[this.eventLimit-1]=marker;else this.diagnostics.push(marker);}
  clear():void {this.full=false;this.frames=[];this.actions=[];this.diagnostics=[];this.bytes=0;}
}
