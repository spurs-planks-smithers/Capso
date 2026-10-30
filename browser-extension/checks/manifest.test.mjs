// Run with: npm --prefix browser-extension run checks
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const manifest=name=>JSON.parse(readFileSync(new URL(`../${name}`,import.meta.url),'utf8'));

// Kept drafts stay in the profile for up to 7 days (docs/decisions/2026-10-30-chrome-incognito-and-dev-drafts.md, issue #187).
test('the pilot is not allowed in Incognito windows',()=>{
  assert.equal(manifest('pilot-manifest.json').incognito,'not_allowed');
});
test('the pilot permission set does not change',()=>{
  const pilot=manifest('pilot-manifest.json');
  assert.deepEqual([...pilot.permissions].sort(),['activeTab','scripting','storage']);
  assert.deepEqual(pilot.optional_permissions??[],[]);
  assert.deepEqual([...pilot.optional_host_permissions].sort(),['http://*/*','https://*/*']);
  assert.equal(pilot.host_permissions,undefined);
});
