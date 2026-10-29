import {EvidenceHistory} from './core/history.ts';
import {encodeFrames} from './recording-codec.ts';
const history=new EvidenceHistory();
chrome.runtime.onMessage.addListener((m,s,respond)=>{
  if(s.id!==chrome.runtime.id||m?.target!=='recorder')return;
  void(async()=>{
    if(m.type==='frame'){
      const bitmap=await createImageBitmap(await(await fetch(m.image)).blob()),scale=Math.min(1,1280/bitmap.width,800/bitmap.height);
      const canvas=new OffscreenCanvas(Math.round(bitmap.width*scale),Math.round(bitmap.height*scale)),ctx=canvas.getContext('2d')!;
      ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);bitmap.close();ctx.fillStyle='#252527';
      for(const r of m.proof.privateRects)ctx.fillRect(r.x*canvas.width/m.proof.viewportWidth,r.y*canvas.height/m.proof.viewportHeight,r.width*canvas.width/m.proof.viewportWidth,r.height*canvas.height/m.proof.viewportHeight);
      const blob=await canvas.convertToBlob({type:'image/jpeg',quality:.72});history.addFrame({at:m.at,width:canvas.width,height:canvas.height,bytes:new Uint8Array(await blob.arrayBuffer())});return {ok:true};
    }
    if(m.type==='event'){history.event(m.at,m.kind,m.label);return {ok:true};}
    if(m.type==='status')return {frames:history.frames.map(f=>({at:f.at,width:f.width,height:f.height})),bytes:history.bytes,actions:history.actions,diagnostics:history.diagnostics};
    if(m.type==='clear'){history.clear();return {ok:true};}
    if(m.type==='select'){
      const selected=history.select(m.start,m.end),frame=selected.frames.reduce((best,f)=>Math.abs(f.at-m.issue)<Math.abs(best.at-m.issue)?f:best,selected.frames[0]);
      if(!frame)throw Error('No verified frames in this range.');
      let media:number[]|undefined;
      try{media=Array.from(await encodeFrames(selected.frames));}catch{selected.diagnostics.push({at:m.issue,kind:'coverage',text:'Animation unavailable. Selected still image is retained.'});}
      return {frame:{...frame,bytes:Array.from(frame.bytes)},media,actions:selected.actions,diagnostics:selected.diagnostics};
    }
    throw Error('Unknown recorder command');
  })().then(respond,e=>respond({error:String(e.message)}));return true;
});
