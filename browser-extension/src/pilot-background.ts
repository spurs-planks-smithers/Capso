import {selectBrowserArea,captureRegion} from './capture.ts';
import {discardDraft,pruneDrafts} from './core/index.ts';

interface Intent {id:string;kind:'capture'|'frames';tabId:number;permissions:chrome.permissions.Permissions;expires:number;}
async function associations():Promise<Record<string,string>> {return ((await chrome.storage.session.get('draftTabs')).draftTabs??{}) as Record<string,string>;}
async function cleanDrafts():Promise<void>{
  const live=new Set((await chrome.tabs.query({})).map(t=>String(t.id))),drafts=await associations();
  for(const tab of Object.keys(drafts))if(!live.has(tab))delete drafts[tab];
  await chrome.storage.session.set({draftTabs:drafts});await pruneDrafts(Object.values(drafts));
}
chrome.runtime.onInstalled.addListener(()=>{void chrome.storage.local.setAccessLevel({accessLevel:'TRUSTED_CONTEXTS'});void chrome.storage.local.set({embeddedPreviewsEnabled:true});});
chrome.runtime.onStartup.addListener(()=>{void cleanDrafts();});
chrome.tabs.onRemoved.addListener(tabId=>{void(async()=>{const drafts=await associations(),id=drafts[tabId];if(id){await discardDraft(id);delete drafts[tabId];await chrome.storage.session.set({draftTabs:drafts});}})();});
chrome.permissions.onRemoved.addListener(()=>{void cleanDrafts();});
let queue=Promise.resolve();
function finishIntent(id?:string):Promise<void>{
  const operation=queue.then(async()=>{
    const intent=(await chrome.storage.session.get('pendingIntent')).pendingIntent as Intent|undefined;
    if(!intent||id&&id!==intent.id)return;
    if(intent.expires<Date.now()){await chrome.storage.session.remove('pendingIntent');return;}
    if(!['capture','frames'].includes(intent.kind)||!Number.isInteger(intent.tabId))throw Error('Invalid capture request.');
    if(!await chrome.permissions.contains(intent.permissions))return;
    await chrome.storage.session.remove('pendingIntent');await selectBrowserArea(intent.tabId);
  });
  queue=operation.catch(error=>chrome.storage.session.set({intentError:error instanceof Error?error.message:'Capture is unavailable.'}));
  return operation;
}
chrome.permissions.onAdded.addListener(()=>{void finishIntent().catch(()=>{});});
async function prepareIntent(kind:string,tabId:number):Promise<{id:string;needsPermission:boolean;permissions:chrome.permissions.Permissions}>{
  if(!['capture','frames'].includes(kind)||!Number.isInteger(tabId))throw Error('Choose a website tab to capture.');
  const tab=await chrome.tabs.get(tabId);if(!tab.url||!/^https?:/.test(tab.url))throw Error('Choose a website tab to capture.');
  let origins=[new URL(tab.url).origin+'/*'];
  if(kind==='frames'){
    const record=(await chrome.storage.session.get('frameOrigins:'+tabId))['frameOrigins:'+tabId] as {url?:string;origins?:unknown[]}|undefined;
    if(!record||record.url!==tab.url||!record.origins?.length)throw Error('Capture this page first to find its preview sites.');
    origins=record.origins.filter((v):v is string=>{try{const u=new URL(String(v));return typeof v==='string'&&/^https?:$/.test(u.protocol)&&v===u.origin+'/*';}catch{return false;}});
    if(origins.length!==record.origins.length)throw Error('Preview site permission is invalid.');
  }
  const intent:Intent={id:crypto.randomUUID(),kind:kind as Intent['kind'],tabId,permissions:{origins},expires:Date.now()+120000};
  await chrome.storage.session.set({pendingIntent:intent});const needsPermission=!await chrome.permissions.contains(intent.permissions);
  if(!needsPermission)await finishIntent(intent.id);
  return {id:intent.id,needsPermission,permissions:intent.permissions};
}
chrome.commands.onCommand.addListener(command=>{if(command==='capture')void(async()=>{const [tab]=await chrome.tabs.query({active:true,currentWindow:true});if(tab?.id)await selectBrowserArea(tab.id);})().catch(error=>chrome.storage.session.set({intentError:String(error.message)}));});
chrome.runtime.onMessage.addListener((message,sender,respond)=>{
  if(!message||typeof message.type!=='string')return;
  const trusted=sender.id===chrome.runtime.id&&sender.url?.startsWith(chrome.runtime.getURL(''));
  if(message.type==='nextshot-intent'&&trusted){prepareIntent(message.kind,message.tabId).then(respond,error=>respond({error:error.message}));return true;}
  if(message.type==='nextshot-intent-finish'&&trusted){finishIntent(message.id).then(()=>respond({ok:true}),error=>respond({error:error.message}));return true;}
  if(message.type==='nextshot-region'&&sender.id===chrome.runtime.id&&sender.tab?.id&&sender.frameId===0&&/^https?:/.test(sender.url??'')){
    captureRegion(sender.tab.id,sender.tab.windowId,message).then(respond,error=>respond({error:String(error.message)}));return true;
  }
  if(message.type==='nextshot-forget-draft'&&trusted){void(async()=>{const drafts=await associations();for(const [tab,id] of Object.entries(drafts))if(id===message.id)delete drafts[tab];await chrome.storage.session.set({draftTabs:drafts});respond({ok:true});})();return true;}
  if(message.type==='nextshot-assistance'&&trusted){respond({available:false,source:'local',ids:[],reason:'disabled'});}
});
