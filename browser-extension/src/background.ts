import {selectBrowserArea,captureRegion} from './capture.ts';
import {assistanceMessage,trustedAssistancePage,cancelAllAssistance,cancelTabAssistance} from './assistance.ts';
import {armRolling,stopRolling,openRolling,rollingStatus,rollingPause,pauseForSelection,rollingEvent,rollingPreview,rollingSelection,finishRollingReview} from './rolling.ts';
import {startRecording,pauseRecording,resumeRecording,stopRecording,discardRecording,recordingStatus,selectRecording,recordObservedEvent} from './recording.ts';
import {discardDraft,pruneDrafts} from './core/index.ts';
import {registerIntents,prepareIntent,finishIntent} from './intents.ts';

async function draftAssociations():Promise<Record<string,string>> {return ((await chrome.storage.session.get('draftTabs')).draftTabs??{}) as Record<string,string>;}
async function cleanDrafts():Promise<void> {
  const tabs=await chrome.tabs.query({}),live=new Set(tabs.map(t=>String(t.id))),associations=await draftAssociations();
  for(const tab of Object.keys(associations))if(!live.has(tab))delete associations[tab];
  await chrome.storage.session.set({draftTabs:associations});await pruneDrafts(Object.values(associations));
}
chrome.runtime.onStartup.addListener(()=>{void cleanDrafts();});
chrome.runtime.onInstalled.addListener(()=>{void chrome.storage.local.setAccessLevel({accessLevel:'TRUSTED_CONTEXTS'});});
async function startCapture(tabId:number):Promise<void> {
  const tab=await chrome.tabs.get(tabId);
  if(!tab.url||!/^https?:/.test(tab.url))throw new Error('Choose a website tab to capture.');
  await pauseForSelection();try{await selectBrowserArea(tabId);}catch(e){await rollingPause('selection',false);throw e;}
}
registerIntents(async intent=>{
  if(intent.kind==='frames')await chrome.storage.local.set({embeddedPreviewsEnabled:true});
  if(intent.kind==='capture'||intent.kind==='frames')await startCapture(intent.tabId!);
  else if(intent.kind==='rolling')await armRolling(intent.tabId!);
  else if(intent.kind==='recording')await startRecording(intent.tabId!);
  else if(intent.kind==='native')await chrome.storage.local.set({nativeSave:true});
  else if(intent.kind==='apple')await chrome.storage.local.set({browserAppleIntelligence:true});
  else if(intent.kind==='jev'){
    // Interactive sign-in must not hold the capture permission queue.
    void assistanceMessage({action:'signin'},{id:chrome.runtime.id,url:chrome.runtime.getURL('popup.html')})
      .then(async result=>{if(!(result as {signedIn?:boolean})?.signedIn)await chrome.storage.session.set({intentError:'Sign-in did not complete. Local suggestions stay available.'});})
      .catch(()=>chrome.storage.session.set({intentError:'Sign-in is unavailable. Local suggestions stay available.'}));
  }
});
chrome.commands.onCommand.addListener(async command=>{
  if(command==='rolling-round'){await openRolling().catch(()=>{});return;}if(command!=='capture')return;
  const [tab]=await chrome.tabs.query({active:true,currentWindow:true});if(tab?.id)await startCapture(tab.id).catch(()=>{});
});
chrome.tabs.onRemoved.addListener(tabId=>{cancelTabAssistance(tabId);void(async()=>{const associations=await draftAssociations(),id=associations[tabId];if(id){await discardDraft(id);delete associations[tabId];await chrome.storage.session.set({draftTabs:associations});}})();});
chrome.permissions.onRemoved.addListener(()=>{cancelAllAssistance();void cleanDrafts();});
chrome.runtime.onMessage.addListener((message,sender,respond)=>{
  if(!message||typeof message!=='object'||typeof message.type!=='string')return;
  if(message.type==='nextshot-assistance'&&trustedAssistancePage(sender)){const current=async()=>{if(message.selection?.purpose!=='steps')return true;const s=await rollingStatus();return s.id===message.selection.rollingID&&s.reasons.includes('review');};assistanceMessage(message,sender,current).then(respond,e=>respond({error:e.message}));return true;}
  const trustedPage=sender.url?.startsWith(chrome.runtime.getURL(''));
  if(message.type==='nextshot-intent'&&trustedPage){prepareIntent(message.kind,message.tabId).then(respond,e=>respond({error:e.message}));return true;}
  if(message.type==='nextshot-intent-finish'&&trustedPage){finishIntent(message.id).then(()=>respond({ok:true}),e=>respond({error:e.message}));return true;}
  if(message.type==='nextshot-record-event'&&sender.tab?.id&&sender.frameId===0){void recordObservedEvent(sender.tab.id,message.kind,message.label);void rollingEvent(sender.tab.id,message.kind,message.label);return;}
  if(message.type==='nextshot-selection-ended'&&sender.tab?.id){void rollingStatus().then(s=>{if(s.tabId===sender.tab?.id)void rollingPause('selection',false);});return;}
  if(message.type==='nextshot-rolling'&&trustedPage){if(['stop','cancel','select'].includes(message.action))cancelAllAssistance();const run=async()=>{switch(message.action){case 'status':return rollingStatus();case 'open':await openRolling();break;case 'stop':await stopRolling();break;case 'cancel':await finishRollingReview();break;case 'pause':await rollingPause('manual',true);break;case 'resume':await rollingPause('manual',false);break;case 'preview':return rollingPreview(message.at);case 'select':{const id=await rollingSelection(message.start,message.end,message.issue,message.steps,message.identity,message.revision);if(sender.tab?.id){const associations=await draftAssociations();associations[sender.tab.id]=id;await chrome.storage.session.set({draftTabs:associations});}return {id};}default:throw Error('Unknown Rolling Round action');}return {ok:true};};run().then(respond,e=>respond({error:e.message}));return true;}
  if(message.type==='nextshot-record'&&trustedPage&&!sender.url?.endsWith('offscreen.html')){
    const run=async()=>{switch(message.action){case 'start':await startRecording(Number(message.tabId));break;case 'pause':await pauseRecording();break;case 'resume':await resumeRecording();break;case 'stop':await stopRecording();break;case 'discard':await discardRecording();break;case 'select':{const id=await selectRecording(message.start,message.end,message.issue);if(Number.isInteger(message.reviewTab)){const tab=await chrome.tabs.get(message.reviewTab);if(tab.url===sender.url){const associations=await draftAssociations();associations[message.reviewTab]=id;await chrome.storage.session.set({draftTabs:associations});}}return {id};}case 'status':return recordingStatus();default:throw Error('Unknown recording action');}return {ok:true};};
    run().then(respond,e=>respond({error:e.message}));return true;
  }
  if(message.type==='nextshot-start'&&trustedPage){
    startCapture(Number(message.tabId)).then(()=>respond({ok:true}),error=>respond({error:String(error.message)}));return true;
  }
  if(message.type==='nextshot-region'&&sender.tab?.id&&sender.frameId===0&&/^https?:/.test(sender.url??'')){
    captureRegion(sender.tab.id,sender.tab.windowId,message).then(result=>respond(result),error=>respond({error:String(error.message)}));return true;
  }
  if(message.type==='nextshot-forget-draft'&&trustedPage){cancelAllAssistance();draftAssociations().then(async associations=>{const rolling=await rollingStatus();if(rolling.draftId===message.id)await finishRollingReview();for(const [tab,id] of Object.entries(associations))if(id===message.id)delete associations[tab];await chrome.storage.session.set({draftTabs:associations});respond({ok:true});});return true;}
});
