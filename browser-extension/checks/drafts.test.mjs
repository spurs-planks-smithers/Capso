// Run with: npm --prefix browser-extension run checks (Node 22.18 or newer strips the TypeScript types).
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {draftsToDiscard,draftLimits} from '../src/core/drafts.ts';

const now=Date.parse('2026-10-30T12:00:00Z'),hour=3600*1000,MB=1024*1024;
const draft=(id,ageMs,bytes=MB)=>({id,updatedAt:now-ageMs,bytes});
const source=name=>readFileSync(new URL(`../src/${name}`,import.meta.url),'utf8');

test('a recent draft survives a restart',()=>{
  assert.deepEqual(draftsToDiscard([draft('a',2*hour)],now),[]);
});
test('a draft older than the age limit is discarded',()=>{
  assert.deepEqual(draftsToDiscard([draft('old',draftLimits.maxAgeMs+hour),draft('new',hour)],now),['old']);
  assert.deepEqual(draftsToDiscard([draft('edge',draftLimits.maxAgeMs)],now),[]);
});
test('a draft with no usable time is discarded',()=>{
  assert.deepEqual(draftsToDiscard([{id:'x',updatedAt:NaN,bytes:1}],now),['x']);
});
test('only the newest drafts within the count limit stay',()=>{
  const drafts=Array.from({length:8},(_,i)=>draft(`d${i}`,(i+1)*hour));
  assert.deepEqual(draftsToDiscard(drafts,now).sort(),['d5','d6','d7']);
});
test('the size limit drops older drafts first',()=>{
  const drafts=[draft('new',hour,40*MB),draft('mid',2*hour,20*MB),draft('older',3*hour,10*MB)];
  assert.deepEqual(draftsToDiscard(drafts,now).sort(),['older']);
});
test('the newest draft is kept even when it alone exceeds the size limit',()=>{
  assert.deepEqual(draftsToDiscard([draft('big',hour,200*MB),draft('small',2*hour,MB)],now),['small']);
});
test('input order does not change the result',()=>{
  const drafts=[draft('c',3*hour),draft('a',hour),draft('b',2*hour)],limits={...draftLimits,maxCount:2};
  assert.deepEqual(draftsToDiscard(drafts,now,limits),['c']);
  assert.deepEqual(draftsToDiscard([...drafts].reverse(),now,limits),['c']);
});

// Guards for the restart rule (docs/decisions/2026-10-30-chrome-draft-restart-recovery.md).
test('the pilot never discards a draft because its tab closed or the browser restarted',()=>{
  const background=source('pilot-background.ts');
  assert.doesNotMatch(background,/tabs\.onRemoved/);
  assert.doesNotMatch(background,/discardDraft|pruneDrafts\(Object/);
  assert.match(background,/onStartup\.addListener\(pruneDrafts\)/);
});
test('the editor keeps edit and selection state across a restart',()=>{
  const review=source('review.ts');
  assert.doesNotMatch(review,/sessionStorage/);
  assert.match(review,/localStorage\.setItem\(journalKey/);
  assert.match(review,/localStorage\.setItem\(selectedKey/);
});
test('Discard capture deletes the draft and its editor state',()=>{
  const review=source('review.ts');
  assert.match(review,/if\(capture&&!saved\)await discardDraft\(capture\.id\);forgetEditorState\(capture\.id\)/);
});
test('persisting a draft does not clear the selected dot',()=>{
  const review=source('review.ts');
  assert.match(review,/function clearJournal\(id:string\):void\{try\{localStorage\.removeItem\(journalKey\(id\)\);\}catch\{\}\}/);
});
