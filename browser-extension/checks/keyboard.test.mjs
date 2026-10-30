// Run with: npm --prefix browser-extension run checks
// Settled key rules: docs/sessions/2026-10-29-chrome-extension-handoff.md (issue #177).
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {chordOf} from '../src/ui/chord.ts';

const press=(key,mods={})=>({key,metaKey:false,ctrlKey:false,altKey:false,shiftKey:false,...mods});
const source=name=>readFileSync(new URL(`../src/${name}`,import.meta.url),'utf8');

test('mod is Command on Mac and Control elsewhere',()=>{
  assert.equal(chordOf(press('s',{metaKey:true}),true),'mod+s');
  assert.equal(chordOf(press('S',{ctrlKey:true}),false),'mod+s');
  assert.equal(chordOf(press('Z',{ctrlKey:true,shiftKey:true}),false),'mod+shift+z');
});
test('Control+S does not save on Mac, and the Windows key does not save elsewhere',()=>{
  assert.equal(chordOf(press('s',{ctrlKey:true}),true),'');
  assert.equal(chordOf(press('s',{metaKey:true}),false),'');
  assert.equal(chordOf(press('c',{ctrlKey:true}),true),'');
  assert.equal(chordOf(press('x',{metaKey:true,ctrlKey:true}),true),'');
});
test('plain and shifted keys keep their names',()=>{
  assert.equal(chordOf(press('c'),true),'c');
  assert.equal(chordOf(press('X',{shiftKey:true}),false),'shift+x');
  assert.equal(chordOf(press(' '),false),'space');
  assert.equal(chordOf(press('Escape'),true),'escape');
});

// Guards for the saved flow rules in review.ts.
test('Escape selects the dot tabs and never closes the editor',()=>{
  const line=source('review.ts').split('\n').find(l=>l.includes("e.key==='Escape'"));
  assert.ok(line);
  assert.match(line,/note-tab-\$\{selected\}/);
  assert.doesNotMatch(line,/close|cancel|discard/i);
});
test('C and X act only after saving, and a number selects its dot',()=>{
  const review=source('review.ts');
  assert.match(review,/\{selector:'#copy',key:'c',when:\(\)=>!!saved\}/);
  assert.match(review,/\{selector:'#export',key:'x',when:\(\)=>!!saved\}/);
  assert.match(review,/\/\^\[1-9\]\$\/\.test\(e\.key\)&&capture\.marks\.some/);
});
test('Return advances notes, Shift+Return adds a line, and the last note saves',()=>{
  const line=source('review.ts').split('\n').find(l=>l.includes("e.key==='Enter'&&!e.shiftKey&&!e.metaKey"));
  assert.ok(line);
  assert.match(line,/else save\.click\(\)/);
});
