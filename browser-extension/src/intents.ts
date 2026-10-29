/** Resume an explicit popup action after Chrome closes its permission sheet. */
export type IntentKind='capture'|'recording'|'rolling'|'native';
interface Intent {id:string;kind:IntentKind;tabId?:number;permissions:chrome.permissions.Permissions;expires:number;}
let run:(intent:Intent)=>Promise<void>,queue=Promise.resolve();
export function registerIntents(action:(intent:Intent)=>Promise<void>):void {
  run=action;chrome.permissions.onAdded.addListener(()=>{void finishIntent();});
}
export async function prepareIntent(kind:IntentKind,tabId?:number):Promise<{id:string;needsPermission:boolean;permissions:chrome.permissions.Permissions}> {
  if(!['capture','recording','rolling','native'].includes(kind))throw Error('Unknown requested action');
  let permissions:chrome.permissions.Permissions;
  if(kind==='native')permissions={permissions:['nativeMessaging']};
  else{
    if(!Number.isInteger(tabId))throw Error('Choose a website tab.');
    const tab=await chrome.tabs.get(tabId!);if(!tab.url||!/^https?:/.test(tab.url))throw Error('Choose a website tab.');
    permissions={permissions:['recording','rolling'].includes(kind)?['offscreen']:[],origins:[new URL(tab.url).origin+'/*']};
  }
  const intent:Intent={id:crypto.randomUUID(),kind,tabId,permissions,expires:Date.now()+120000};
  await chrome.storage.session.set({pendingIntent:intent});
  const needsPermission=!await chrome.permissions.contains(permissions);
  if(!needsPermission)await finishIntent(intent.id);
  return {id:intent.id,needsPermission,permissions};
}
export function finishIntent(id?:string):Promise<void> {
  const operation=queue.then(async()=>{
    const intent=(await chrome.storage.session.get('pendingIntent')).pendingIntent as Intent|undefined;
    if(!intent||id&&intent.id!==id)return;
    if(intent.expires<Date.now()){await chrome.storage.session.remove('pendingIntent');return;}
    if(!await chrome.permissions.contains(intent.permissions))return;
    await chrome.storage.session.remove('pendingIntent');
    try{await run(intent);}catch(error){await chrome.storage.session.set({intentError:error instanceof Error?error.message:'The requested action is unavailable.'});}
  });
  queue=operation.catch(()=>{});return operation;
}
