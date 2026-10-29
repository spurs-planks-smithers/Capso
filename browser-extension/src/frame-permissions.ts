/** Trusted popup controls. Permission requests occur only inside the button click. */
export async function mountFramePermissions(tabId:number|undefined,status:HTMLElement):Promise<void>{
  const section=document.createElement('div'),label=document.createElement('label'),toggle=document.createElement('input');toggle.type='checkbox';
  toggle.checked=!!(await chrome.storage.local.get('embeddedPreviewsEnabled')).embeddedPreviewsEnabled;
  label.append(toggle,' Embedded preview context trial');section.append(label);
  toggle.onchange=()=>{void chrome.storage.local.set({embeddedPreviewsEnabled:toggle.checked});};
  const record=tabId?(await chrome.storage.session.get('frameOrigins:'+tabId))['frameOrigins:'+tabId] as {origins?:string[]}|undefined:undefined;
  if(record?.origins?.length){
    const button=document.createElement('button');button.textContent='Allow embedded sites';
    const detail=document.createElement('p');detail.textContent=record.origins.join(', ');section.append(detail,button);
    button.onclick=async()=>{try{
      const intent=await chrome.runtime.sendMessage({type:'nextshot-intent',kind:'frames',tabId});if(intent.error)throw Error(intent.error);
      if(intent.needsPermission&&!await chrome.permissions.request(intent.permissions))throw Error('Embedded sites stay covered. Permission was declined.');
      await chrome.storage.local.set({embeddedPreviewsEnabled:true});
      await chrome.runtime.sendMessage({type:'nextshot-intent-finish',id:intent.id});window.close();
    }catch(error){status.textContent=error instanceof Error?error.message:'Embedded site permission is unavailable.';}};
  }
  status.before(section);
}
