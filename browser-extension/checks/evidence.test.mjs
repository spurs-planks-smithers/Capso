// Run with: npm --prefix browser-extension run checks
// Rule: docs/decisions/2026-10-30-chrome-element-evidence-labels.md (issue #185).
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {evidenceCaption} from '../src/core/evidence.ts';

const base={tag:'div',role:'',ariaLabel:null,ownText:'',insideLabel:false,insideFieldRole:false};
const caption=overrides=>evidenceCaption({...base,...overrides});

test('a label element carries no text, bound to a field or not',()=>{
  assert.equal(caption({tag:'LABEL',ownText:'Work email'}),'');
  assert.equal(caption({tag:'label',ariaLabel:'Work email',ownText:'Work email'}),'');
});
test('text inside a label carries no text',()=>{
  assert.equal(caption({tag:'span',ownText:'(required)',insideLabel:true}),'');
});
test('an aria-label on a field carries no text',()=>{
  assert.equal(caption({tag:'input',ariaLabel:'Credit card number',role:'textbox'}),'');
  assert.equal(caption({tag:'div',ariaLabel:'Search the site',role:'searchbox'}),'');
});
test('a non-editable field role carries no text',()=>{
  for(const role of ['textbox','searchbox','combobox','listbox','spinbutton','slider','switch','checkbox','radio'])
    assert.equal(caption({role,ownText:'typed value'}),'',role);
  assert.equal(caption({role:'presentation textbox',ownText:'typed value'}),'');
  assert.equal(caption({role:'TextBox',ownText:'typed value'}),'');
  assert.equal(caption({role:' ComboBox ',ariaLabel:'Country'}),'');
});
test('text inside a field role carries no text',()=>{
  assert.equal(caption({tag:'span',ownText:'typed value',insideFieldRole:true}),'');
});
test('buttons, links, and ordinary page text keep their text',()=>{
  assert.equal(caption({tag:'button',ownText:'Save changes'}),'Save changes');
  assert.equal(caption({tag:'a',role:'link',ownText:'Pricing'}),'Pricing');
  assert.equal(caption({tag:'div',role:'button',ariaLabel:'Close dialog',ownText:'x'}),'Close dialog');
  assert.equal(caption({tag:'p',ownText:'Welcome back'}),'Welcome back');
});

// The adapter in content.ts must route every page element through evidenceCaption.
test('snapshot records element text only through evidenceCaption',()=>{
  const content=readFileSync(new URL('../src/content.ts',import.meta.url),'utf8');
  assert.match(content,/evidenceCaption\(\{tag:e\.tagName,role,ariaLabel:e\.getAttribute\('aria-label'\)/);
  assert.match(content,/\.\.\.captionContext\(e\)/);
  assert.match(content,/root instanceof ShadowRoot\?root\.host/);
  assert.doesNotMatch(content,/redactSensitive\(e\.getAttribute\('aria-label'\)\|\|ownText/);
});
