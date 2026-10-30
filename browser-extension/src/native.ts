declare const __NEXTSHOT_BROWSER_ONLY__: boolean;
import type {Capture,Asset} from './core/model.ts';

export interface NativeReceipt {state:string;id?:string;digest?:string;folder?:string;captureIndex?:number;error?:string;}
function base64(bytes:Uint8Array):string {
  let text='';for(let offset=0;offset<bytes.length;offset+=8192)text+=String.fromCharCode(...bytes.subarray(offset,offset+8192));return btoa(text);
}
export async function deliverNative(capture:Capture,assets:Asset[]):Promise<NativeReceipt|undefined> {
  if(__NEXTSHOT_BROWSER_ONLY__)return;
  if(!(await chrome.storage.local.get('nativeSave')).nativeSave)return;
  if(!await chrome.permissions.contains({permissions:['nativeMessaging']}))return;
  const payload=new TextEncoder().encode(JSON.stringify({schema:'nextshot.browser',schemaVersion:1,capture,assets:assets.map(a=>({name:a.name,mime:a.mime,bytes:base64(a.bytes)}))}));
  if(payload.length>16*1024*1024)return {state:'failed',error:'oversized'};
  const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',payload)),n=>n.toString(16).padStart(2,'0')).join('');
  try {
    const receipt:NativeReceipt=await chrome.runtime.sendNativeMessage('com.drewschulz.nextshot.dev.browser',{version:1,channel:'dev',operation:'import',id:capture.id,digest,payload:base64(payload)});
    if(receipt.state==='imported'&&(receipt.id!==capture.id||receipt.digest!==digest))return {state:'failed',error:'receipt-mismatch'};
    return receipt;
  }catch{return {state:'failed',error:'unavailable'};}
}
