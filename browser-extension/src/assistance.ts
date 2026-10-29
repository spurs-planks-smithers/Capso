import {createJevClient,type JevSelection,type JevPolicy} from './jev-client.ts';
import {nativeAssistance} from './native-assistance.ts';
import {redactSensitive} from './core/sanitize.ts';
export type AssistanceMode='local'|'apple'|'jev';
export interface AssistInput extends Omit<JevSelection,'selectionVersion'> {selectionVersion:number;issueAtMs?:number;rollingID?:string;}
export interface AssistResult {available:boolean;source:'local'|'apple'|'jev';ids:string[];reason?:string;}
const local=(reason='local'):AssistResult=>({available:false,source:'local',ids:[],reason});
let client:ReturnType<typeof createJevClient>|undefined;
const jev=()=>client??=createJevClient();
const active=new Map<string,{requestID:string;controller:AbortController}>();
const settingsKeys=['assistanceMode','jevEnabled','jevConsentPageData','jevConsentReviewerText','browserAppleIntelligence'];
chrome.storage.onChanged.addListener((changes,area)=>{if(area==='local'&&settingsKeys.some(key=>Object.hasOwn(changes,key)))cancelAllAssistance();});
export function assistanceText(value:unknown,max=512):string{
  return redactSensitive(value,max).replace(/[\u0000-\u001f\u007f]/g,' ').replace(/https?:\/\/[^\s]+|www\.[^\s]+/gi,'[link]').replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi,'[contact]').replace(/Bearer\s+\[redacted\]/gi,'[credential]').trim().slice(0,max)||'Unlabeled';
}
function actionText(value:unknown):string{
  // Older in-memory timelines can contain local CSS locators.
  if(typeof value==='string'&&(/:nth-of-type\(|\s>{1,3}\s|^[a-z][a-z0-9-]*[#.[]/i.test(value)))return 'Click captured control';
  return assistanceText(value);
}
export async function assistanceSettings(){
  const value=await chrome.storage.local.get(settingsKeys);
  return {assistanceMode:(typeof value.assistanceMode==='string'&&['apple','jev'].includes(value.assistanceMode)?value.assistanceMode:'local') as AssistanceMode,jevEnabled:value.jevEnabled===true,jevConsentPageData:value.jevConsentPageData===true,jevConsentReviewerText:value.jevConsentReviewerText===true,browserAppleIntelligence:value.browserAppleIntelligence===true};
}
/** Only exact top-level settings/review pages can invoke assistance. */
export function trustedAssistancePage(sender:chrome.runtime.MessageSender):boolean{
  if(sender.id!==chrome.runtime.id||sender.frameId!==undefined&&sender.frameId!==0||!sender.url)return false;
  try{const url=new URL(sender.url);return ['popup.html','review.html','rolling.html'].some(name=>url.protocol+'//'+url.host+url.pathname===chrome.runtime.getURL(name));}catch{return false;}
}
function selection(input:AssistInput,policy:JevPolicy):JevSelection{
  if(!input||typeof input!=='object'||Object.keys(input).some(k=>!['purpose','requestID','selectionVersion','timeline','diagnostics','candidates','reviewerNote','issueAtMs','rollingID'].includes(k))||!Number.isSafeInteger(input.selectionVersion)||input.selectionVersion<0||!/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(input.requestID)||!['steps','elements'].includes(input.purpose)||!Array.isArray(input.timeline)||input.timeline.length>32||!Array.isArray(input.diagnostics)||input.diagnostics.length>8||!Array.isArray(input.candidates)||input.candidates.length>16||input.issueAtMs!==undefined&&(!Number.isFinite(input.issueAtMs)||input.issueAtMs<0||input.issueAtMs>60000))throw Error('invalid');
  const id=(value:unknown)=>{if(typeof value!=='string'||!/^[A-Za-z0-9_-]{1,64}$/.test(value))throw Error('invalid');return value;};
  const rowKeys=(row:object,keys:string[])=>{if(!row||Object.keys(row).some(k=>!keys.includes(k))||keys.some(k=>!Object.hasOwn(row,k)))throw Error('invalid');};
  const value:JevSelection={purpose:input.purpose,requestID:input.requestID,selectionVersion:`r${input.selectionVersion}`,...(input.issueAtMs!==undefined?{issueTimeMs:input.issueAtMs}:{}),
    timeline:input.timeline.map(row=>{rowKeys(row,['id','kind','label','timeMs']);if(!Number.isInteger(row.timeMs)||row.timeMs<0||row.timeMs>60000)throw Error('invalid');return {id:id(row.id),kind:assistanceText(row.kind,64),label:actionText(row.label),timeMs:row.timeMs};}),
    diagnostics:input.diagnostics.map(row=>{rowKeys(row,['id','kind','summary']);return {id:id(row.id),kind:assistanceText(row.kind,64),summary:assistanceText(row.summary)};}),
    candidates:input.candidates.map(row=>{rowKeys(row,['id','role','label']);return {id:id(row.id),role:assistanceText(row.role,64),label:assistanceText(row.label)};})};
  for(const rows of [value.timeline,value.diagnostics,value.candidates])if(new Set(rows.map(row=>row.id)).size!==rows.length)throw Error('invalid');
  if(!(value.purpose==='steps'?value.timeline:value.candidates).length)throw Error('invalid');
  if(input.reviewerNote!==undefined&&typeof input.reviewerNote!=='string')throw Error('invalid');
  if(policy.jevConsentReviewerText&&input.reviewerNote?.trim())value.reviewerNote=assistanceText(input.reviewerNote,1024);
  return value;
}
export function cancelAssistance(owner:string,requestID?:string):void{const prior=active.get(owner);if(prior&&(!requestID||prior.requestID===requestID)){prior.controller.abort();active.delete(owner);}}
export function cancelAllAssistance():void{for(const owner of active.keys())cancelAssistance(owner);}
export function cancelTabAssistance(tabId:number):void{for(const owner of active.keys())if(owner.startsWith(String(tabId)+'/'))cancelAssistance(owner);}
export async function runAssistance(owner:string,input:AssistInput,isReviewCurrent:()=>Promise<boolean>=async()=>true):Promise<AssistResult>{
  cancelAssistance(owner);const controller=new AbortController(),entry={requestID:input?.requestID,controller};active.set(owner,entry);
  const current=()=>active.get(owner)===entry&&!controller.signal.aborted;
  try{
    const settings=await assistanceSettings();if(settings.assistanceMode==='local')return local();
    const selected=selection(input,settings);if(input.purpose==='elements'&&!selected.reviewerNote)return local('insufficient_context');if(!current()||!await isReviewCurrent())return local('stale');
    if(settings.assistanceMode==='apple'&&settings.browserAppleIntelligence&&input.purpose==='steps'){const result=await nativeAssistance(selected,input.selectionVersion,input.issueAtMs,controller.signal);if(!current()||!await isReviewCurrent())return local('stale');if(result.available){const latest=await assistanceSettings();return latest.assistanceMode==='apple'&&latest.browserAppleIntelligence?{available:true,source:'apple',ids:result.ids}:local('settings_changed');}}
    if(settings.assistanceMode!=='jev')return local('unavailable');
    // Jev requires explicit selection, enablement, authentication, and content consent.
    if(!settings.jevEnabled||!settings.jevConsentPageData)return local('unavailable');
    if(!await chrome.permissions.contains({permissions:['identity'],origins:['https://jev.nextshot.dev/*']}))return local('reconnect_required');
    const beforeSend=async()=>{const latest=await assistanceSettings();return current()&&latest.assistanceMode===settings.assistanceMode&&latest.jevEnabled&&latest.jevConsentPageData&&latest.jevConsentReviewerText===settings.jevConsentReviewerText&&await chrome.permissions.contains({permissions:['identity'],origins:['https://jev.nextshot.dev/*']});};
    const result=await jev().refine(selected,settings,{signal:controller.signal,stillCurrent:current,beforeSend});
    if(!current()||!await isReviewCurrent())return local('stale');
    const latest=await assistanceSettings();if(latest.assistanceMode!==settings.assistanceMode||!latest.jevEnabled||!latest.jevConsentPageData||latest.jevConsentReviewerText!==settings.jevConsentReviewerText)return local('settings_changed');
    return result.available?{available:true,source:'jev',ids:result.candidates.filter(row=>row.confidence>=.9).map(row=>row.id)}:local(result.reason);
  }catch{return local('unavailable');}finally{if(active.get(owner)===entry)active.delete(owner);}
}
export async function assistanceMessage(message:any,sender:chrome.runtime.MessageSender,isReviewCurrent:()=>Promise<boolean>=async()=>true):Promise<unknown>{
  if(!trustedAssistancePage(sender))throw Error('Untrusted assistance page');
  const owner=String(sender.tab?.id??sender.documentId??'popup')+new URL(sender.url!).pathname;
  switch(message.action){
    case 'status':return {...await assistanceSettings(),...(await chrome.permissions.contains({permissions:['identity']})?await jev().status():{signedIn:false,needsReconnect:true,accessExpired:false})};
    case 'signin':{if(!sender.url?.startsWith(chrome.runtime.getURL('popup.html')))throw Error('Sign in from settings');if(!await chrome.permissions.contains({permissions:['identity'],origins:['https://jev.nextshot.dev/*']}))return {signedIn:false};return jev().signIn();}
    case 'signout':cancelAllAssistance();await jev().signOut();return {ok:true};
    case 'cancel':cancelAssistance(owner,message.requestID);return {ok:true};
    case 'refine':if(new URL(sender.url!).pathname==='/popup.html')throw Error('Review only');return runAssistance(owner,message.selection,isReviewCurrent);
    default:throw Error('Unknown assistance action');
  }
}
