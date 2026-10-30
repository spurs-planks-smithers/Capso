export interface ChordEvent {key:string;metaKey:boolean;ctrlKey:boolean;altKey:boolean;shiftKey:boolean;}

/**
 * Names a key press the way action keys are declared, for example "mod+s" or "shift+x".
 * `mod` is Command on Mac and Control elsewhere, never both. Returns an empty string for the
 * other modifier (Control on Mac, the Windows key elsewhere), so Ctrl+S never saves on Mac.
 */
export function chordOf(event:ChordEvent,mac:boolean):string {
  if(mac?event.ctrlKey:event.metaKey)return '';
  const key=event.key.toLowerCase();
  return [...(mac?event.metaKey:event.ctrlKey)?['mod']:[],...(event.altKey?['alt']:[]),...(event.shiftKey?['shift']:[]),key===' '?'space':key].join('+');
}
