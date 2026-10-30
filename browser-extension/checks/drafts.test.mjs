// Run with: npm --prefix browser-extension run checks (Node 22.18 or newer strips the TypeScript types).
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {draftsToDiscard,draftLimits,isTabBoundDraft} from '../src/core/drafts.ts';

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
// Dev follows the same rule for screenshot drafts (issue #188). Rolling and recording drafts stay tab-bound.
test('rolling and recording drafts are tab-bound, screenshot drafts are not',()=>{
  assert.equal(isTabBoundDraft({kind:'rolling'}),true);
  assert.equal(isTabBoundDraft({kind:'capture',clip:{start:0,end:1000}}),true);
  assert.equal(isTabBoundDraft({kind:'capture'}),false);
  assert.equal(isTabBoundDraft(undefined),false);
});
test('the dev profile prunes screenshot drafts by the retention rule, not by tab',()=>{
  const background=source('background.ts'),capture=source('capture.ts'),store=source('core/store.ts');
  assert.match(background,/pruneTabBoundDrafts\(Object\.values\(associations\)\);await pruneStaleDrafts\(\)/);
  assert.doesNotMatch(background,/\bpruneDrafts\b/);
  assert.doesNotMatch(capture,/draftTabs/);
  assert.match(store,/filter\(\(\{record\}\)=>!isTabBoundDraft\(record\.capture\)\)/);
  assert.match(store,/isTabBoundDraft\(records\[index\]\?\.capture\)&&!keep\.has/);
});
test('both popups share one resume line that queries only extension pages',()=>{
  const resume=source('resume.ts');
  assert.match(source('pilot-popup.ts'),/mountResume\(/);
  assert.match(source('popup.ts'),/mountResume\(/);
  assert.match(resume,/chrome\.tabs\.query\(\{url:page\+'\*'\}\)/);
  assert.equal((resume.match(/tabs\.create/g)??[]).length,1);
});
test('persisting a draft does not clear the selected dot',()=>{
  const review=source('review.ts');
  assert.match(review,/function clearJournal\(id:string\):void\{try\{localStorage\.removeItem\(journalKey\(id\)\);\}catch\{\}\}/);
});
