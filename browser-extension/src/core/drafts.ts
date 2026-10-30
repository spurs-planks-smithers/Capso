export interface DraftInfo {id:string;updatedAt:number;bytes:number;}
export interface DraftLimits {maxAgeMs:number;maxCount:number;maxBytes:number;}
export const draftLimits:DraftLimits={maxAgeMs:7*24*60*60*1000,maxCount:5,maxBytes:64*1024*1024};

/** Rolling and recording drafts hold screen video. They stay bound to their review tab in the Dev profile and follow the tab rule, not the retention rule. */
export function isTabBoundDraft(capture:{kind?:string;clip?:unknown}|undefined):boolean {return capture?.kind==='rolling'||!!capture?.clip;}

/** Returns the IDs of unsaved drafts to delete. The newest live draft is always kept, so one large draft is never lost to the size cap. */
export function draftsToDiscard(drafts:DraftInfo[],now:number,limits:DraftLimits=draftLimits):string[]{
  const discard:string[]=[],live:DraftInfo[]=[];
  for(const draft of drafts){
    if(!Number.isFinite(draft.updatedAt)||now-draft.updatedAt>limits.maxAgeMs)discard.push(draft.id);else live.push(draft);
  }
  live.sort((a,b)=>b.updatedAt-a.updatedAt);
  let bytes=0;
  for(const [index,draft] of live.entries()){
    bytes+=draft.bytes;
    if(index>0&&(index>=limits.maxCount||bytes>limits.maxBytes))discard.push(draft.id);
  }
  return discard;
}
