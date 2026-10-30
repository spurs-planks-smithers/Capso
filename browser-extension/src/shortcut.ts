export function captureKey(shortcut:string):string {
  return /Mac/i.test(navigator.platform)?shortcut.replace(/\bAlt\b/g,'Option').replace(/\bMacCtrl\b/g,'Control'):shortcut;
}

/** Query only while this interface is open. Respect keys assigned by Chrome or its user. */
export function mountCaptureShortcut(label:HTMLElement,setup:HTMLButtonElement,captureButton?:HTMLButtonElement):void {
  const refresh=async()=>{
    try{
      const command=(await chrome.commands.getAll()).find(c=>c.name==='capture');
      label.textContent=command?.shortcut?`Capture in Chrome: ${captureKey(command.shortcut)}`:'Choose a shortcut to capture without opening the extension.';
      setup.textContent=command?.shortcut?'Change shortcut':'Set capture shortcut';
      if(captureButton){if(command?.shortcut)captureButton.dataset.keyHint=captureKey(command.shortcut);else delete captureButton.dataset.keyHint;}
    }catch{label.textContent='Capture shortcuts are managed in Chrome.';setup.textContent='Shortcut settings';}
    setup.hidden=false;
  };
  setup.onclick=()=>{void chrome.tabs.create({url:'chrome://extensions/shortcuts'}).catch(()=>{label.textContent='Open chrome://extensions/shortcuts to choose a capture key.';});};
  document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')void refresh();});
  void refresh();
}
