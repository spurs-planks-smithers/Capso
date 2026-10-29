import {EvidenceHistory} from './core/history.ts';
import {compactGIF} from './rolling-gif.ts';
import {encodeFrames} from './recording-codec.ts';
import {newCapture,validateCapture,sanitizeURL,redactSensitive} from './core/index.ts';
let history=new EvidenceHistory(Infinity,24000000,1000,true),rolling=false,started=performance.now();
chrome.runtime.onMessage.addListener((m,s,respond)=>{
  if(s.id!==chrome.runtime.id||(s.url&&!s.url.startsWith(chrome.runtime.getURL('')))||m?.target!=='recorder')return;
  void(async()=>{
    if(m.type==='configure'){rolling=m.rolling===true;started=performance.now();history=new EvidenceHistory(rolling?60000:Infinity,24000000,1000,!rolling);return {ok:true};}
    // The offscreen clock survives worker suspension and ignores system clock changes.
    const at=rolling?m.at:Math.max(0,performance.now()-started);
    if(m.type==='preview'){const frame=history.frames.reduce((best,f)=>!best||Math.abs(f.at-m.at)<Math.abs(best.at-m.at)?f:best,undefined as typeof history.frames[number]|undefined);return frame?{at:frame.at,width:frame.width,height:frame.height,bytes:Array.from(frame.bytes)}:{error:'No verified frame remains.'};}
    if(m.type==='frame'){
      const bitmap=await createImageBitmap(await(await fetch(m.image)).blob()),scale=Math.min(1,1280/bitmap.width,800/bitmap.height);
      const sx=bitmap.width/m.proof.viewportWidth,sy=bitmap.height/m.proof.viewportHeight;
      if(Math.abs(sx-sy)>Math.max(sx,sy)*.01){bitmap.close();throw Error('Browser viewport geometry is unverified.');}
      const canvas=new OffscreenCanvas(Math.round(bitmap.width*scale),Math.round(bitmap.height*scale)),ctx=canvas.getContext('2d')!;
      ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);bitmap.close();ctx.fillStyle='#252527';
      for(const r of m.proof.privateRects)ctx.fillRect(r.x*canvas.width/m.proof.viewportWidth,r.y*canvas.height/m.proof.viewportHeight,r.width*canvas.width/m.proof.viewportWidth,r.height*canvas.height/m.proof.viewportHeight);
      const capture=newCapture({title:'',width:canvas.width,height:canvas.height});
      capture.elements=(m.proof.elements??[]).filter((e:any)=>e.tag!=='html'&&e.tag!=='body').slice(0,300).map((e:any)=>({...e,bounds:{x:e.bounds.x*canvas.width/m.proof.viewportWidth,y:e.bounds.y*canvas.height/m.proof.viewportHeight,width:e.bounds.width*canvas.width/m.proof.viewportWidth,height:e.bounds.height*canvas.height/m.proof.viewportHeight}}));
      const elements=validateCapture(capture).elements,metadataBytes=new TextEncoder().encode(JSON.stringify(elements)).length;
      const blob=await canvas.convertToBlob({type:'image/jpeg',quality:.72});history.addFrame({at,width:canvas.width,height:canvas.height,bytes:new Uint8Array(await blob.arrayBuffer()),elements,metadataBytes,url:sanitizeURL(m.proof.url),title:redactSensitive(m.proof.title,200),alerts:(m.proof.alerts??[]).slice(0,8).map((v:string)=>redactSensitive(v,200)),capturedAt:new Date().toISOString()});return {ok:true,full:history.full};
    }
    if(m.type==='event'){history.event(at,m.kind,m.label);return {ok:true,full:history.full};}
    if(m.type==='limit'){history.limit(at,m.label);return {ok:true};}
    if(m.type==='status')return {frames:history.frames.map(f=>({at:f.at,width:f.width,height:f.height,alerts:f.alerts})),bytes:history.bytes,full:history.full,actions:history.actions,diagnostics:history.diagnostics};
    if(m.type==='clear'){history.clear();return {ok:true,full:history.full};}
    if(m.type==='select'){
      const selected=history.select(m.start,m.end),frame=selected.frames.reduce((best,f)=>Math.abs(f.at-m.issue)<Math.abs(best.at-m.issue)?f:best,selected.frames[0]);
      if(!frame)throw Error('No verified frames in this range.');
      let media:number[]|undefined,mediaMime='video/webm';
      try{const gif=m.rolling?await compactGIF(selected.frames,m.start,m.end):undefined;if(gif){media=Array.from(gif);mediaMime='image/gif';}else media=Array.from(await encodeFrames(selected.frames,{start:m.start,end:m.end}));}catch{selected.diagnostics.push({at:m.issue,kind:'coverage',text:'Animation unavailable. Selected still image is retained.'});}
      // Leave room for the coordinator's coverage row and retain an explicit omission warning.
      if(selected.diagnostics.length>999){
        const resource=selected.diagnostics.find(d=>d.kind==='coverage'&&d.text.includes('resource limits'));
        selected.diagnostics=[...selected.diagnostics.filter(d=>d!==resource).slice(-998),{at:resource?.at??m.issue,kind:'coverage',text:resource?resource.text+' Additional selected diagnostics were omitted.':'Some selected diagnostics were omitted by browser resource limits.'}];
      }
      const representatives=[selected.frames[0],frame,...selected.actions.slice(-8).map(e=>selected.frames.reduce((best,f)=>Math.abs(f.at-e.at)<Math.abs(best.at-e.at)?f:best,selected.frames[0])),selected.frames.at(-1)].filter(Boolean);
      const keyFrames=[...new Set(representatives)].sort((a,b)=>a!.at-b!.at).slice(0,12).map(f=>({...f,bytes:Array.from(f!.bytes)}));
      const stillBytes=keyFrames.reduce((n,f)=>n+f.bytes.length,frame.bytes.length*2)+new TextEncoder().encode(JSON.stringify([selected.actions,selected.diagnostics])).length+20000;
      if(m.rolling&&media&&stillBytes+media.length>5000000)media=undefined;
      return {frame:{...frame,bytes:Array.from(frame.bytes)},keyFrames:m.rolling?keyFrames:[],media,mediaMime,actions:selected.actions,diagnostics:selected.diagnostics};
    }
    throw Error('Unknown recorder command');
  })().then(respond,e=>respond({error:String(e.message)}));return true;
});
