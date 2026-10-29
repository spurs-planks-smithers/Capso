import type {HistoryFrame} from './core/history.ts';
/** Encode only selected, privacy-masked JPEG frames. No audio track exists. */
export async function encodeFrames(frames:HistoryFrame[],range?:{start:number;end:number}):Promise<Uint8Array> {
 if(!frames.length)throw Error('No frames selected');
 const {width,height}=frames[0],start=range?.start??frames[0].at,duration=range?range.end-range.start:Math.max(1000,frames.at(-1)!.at-frames[0].at+1000);
 if(duration<=0||frames.some(f=>f.at<start||f.at>start+duration))throw Error('No animation interval selected');
 const Encoder=(globalThis as any).VideoEncoder,Frame=(globalThis as any).VideoFrame;
 if(!Encoder||!Frame)throw Error('Video encoding unavailable');
 const chunks:{data:Uint8Array;timestamp:number;type:string}[]=[];let failure:unknown;
 const config={codec:'vp8',width,height,bitrate:500000,framerate:1,latencyMode:'realtime'};
 if(!(await Encoder.isConfigSupported(config)).supported)throw Error('VP8 unavailable');
 const enc=new Encoder({output:(c:any)=>{const b=new Uint8Array(c.byteLength);c.copyTo(b);chunks.push({data:b,timestamp:c.timestamp,type:c.type});},error:(e:unknown)=>failure=e});
 const canvas=new OffscreenCanvas(width,height),ctx=canvas.getContext('2d')!;
 try {enc.configure(config);
 for(const source of frames){const image=await createImageBitmap(new Blob([new Uint8Array(source.bytes).buffer],{type:'image/jpeg'}));ctx.drawImage(image,0,0,width,height);image.close();const frame=new Frame(canvas,{timestamp:Math.round((source.at-start)*1000),duration:Math.max(1,Math.round(Math.min(1000,start+duration-source.at)*1000))});enc.encode(frame,{keyFrame:true});frame.close();if(enc.encodeQueueSize>4)await new Promise(r=>enc.addEventListener('dequeue',r,{once:true}));}
 await enc.flush();if(failure)throw failure;
 }finally{enc.close();}
 const cat=(...a:Uint8Array[])=>{const out=new Uint8Array(a.reduce((n,v)=>n+v.length,0));let p=0;for(const v of a){out.set(v,p);p+=v.length;}return out;};const hex=(s:string)=>Uint8Array.from(s.match(/../g)!.map(x=>parseInt(x,16)));const size=(n:number)=>{for(let k=1;k<=8;k++){if(n<2**(7*k)-1){const a=new Uint8Array(k);let v=n;for(let j=k-1;j>=0;j--){a[j]=v%256;v=Math.floor(v/256);}a[0]|=1<<(8-k);return a;}}throw Error('size');};const el=(id:string,v:Uint8Array)=>cat(hex(id),size(v.length),v);const uint=(n:number)=>{if(n<256)return Uint8Array.of(n);if(n<65536)return Uint8Array.of(n>>8,n&255);return Uint8Array.of(n>>>24,n>>>16&255,n>>>8&255,n&255);};const u=(id:string,n:number)=>el(id,uint(n));const str=(id:string,s:string)=>el(id,new TextEncoder().encode(s));const f64=(n:number)=>{const a=new Uint8Array(8);new DataView(a.buffer).setFloat64(0,n);return a;};
 const header=el('1a45dfa3',cat(u('4286',1),u('42f7',1),u('42f2',4),u('42f3',8),str('4282','webm'),u('4287',2),u('4285',2)));
 const info=el('1549a966',cat(u('2ad7b1',1000000),str('4d80','Nextshot'),str('5741','Nextshot'),el('4489',f64(duration))));
 const track=el('1654ae6b',el('ae',cat(u('d7',1),u('73c5',1),u('83',1),str('86','V_VP8'),el('e0',cat(u('b0',width),u('ba',height))))));
 const clusters=chunks.map(c=>el('1f43b675',cat(u('e7',Math.round(c.timestamp/1000)),el('a3',cat(Uint8Array.of(0x81,0,0,c.type==='key'?0x80:0),c.data)))));return cat(header,el('18538067',cat(info,track,...clusters)));
}
