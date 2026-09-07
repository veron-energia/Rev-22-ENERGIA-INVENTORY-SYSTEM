import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';
import React, { act } from 'react';
import { createRoot } from 'react-dom/client';
import { Simulate } from 'react-dom/test-utils';

const require=createRequire(import.meta.url);
const dir=await mkdtemp(join(tmpdir(),'energia-phone-input-'));
await build({entryPoints:['src/components/PhoneInput.tsx'],outfile:join(dir,'component.mjs'),bundle:true,format:'esm',platform:'node',
  plugins:[{name:'shared-react',setup(b){b.onResolve({filter:/^react(?:\/.*)?$/},args=>({path:require.resolve(args.path),external:true}));}}]});
const {default:PhoneInput}=await import(pathToFileURL(join(dir,'component.mjs')).href);
const dom=new JSDOM('<!doctype html><html><body></body></html>');
globalThis.window=dom.window; globalThis.document=dom.window.document;
globalThis.IS_REACT_ACT_ENVIRONMENT=true;
function setup(value) {
  const node=document.createElement('div'); document.body.appendChild(node);
  const root=createRoot(node); const changes=[];
  function Controlled() {
    const [current,setCurrent]=React.useState(value);
    return React.createElement(PhoneInput,{value:current,onChange:(v,valid)=>{changes.push({value:v,valid});setCurrent(v);}});
  }
  act(()=>root.render(React.createElement(Controlled)));
  return {node,changes,change(value){act(()=>Simulate.change(node.querySelector('input'),{target:{value}}));},country(value){act(()=>Simulate.change(node.querySelector('select'),{target:{value}}));},close(){act(()=>root.unmount());node.remove();}};
}
test('uncertain stored SG/MY number requires a country decision and is not changed on mount',()=>{
  const ui=setup('93234567');
  try {
    assert.equal(ui.node.querySelector('select').value,''); assert.equal(ui.changes.length,0);
    ui.country('MY'); assert.deepEqual(ui.changes.at(-1),{value:'+6093234567',valid:true});
  } finally {ui.close();}
});
test('pasted international numbers retain country; malformed values remain invalid',()=>{
  const ui=setup('');
  try {
    ui.change('+60 12-345 6789'); assert.deepEqual(ui.changes.at(-1),{value:'+60123456789',valid:true});
    assert.equal(ui.node.querySelector('select').value,'MY');
    ui.change('+65 0123 4567'); assert.equal(ui.changes.at(-1).valid,false); assert.equal(ui.changes.at(-1).value,'+65 0123 4567');
    ui.change('91234567 ext 5'); assert.equal(ui.changes.at(-1).valid,false);
  } finally {ui.close();}
});
test('partial input does not lose the selected country and clearing keeps it usable',()=>{
  const ui=setup('');
  try {
    ui.country('MY'); ui.change('0'); ui.change('01');
    assert.equal(ui.node.querySelector('select').value,'MY');
    ui.change('0123456789'); assert.equal(ui.changes.at(-1).value,'+60123456789');
    ui.change(''); assert.equal(ui.node.querySelector('input').value,'');
    assert.equal(ui.node.querySelector('select').value,'MY');
  } finally {ui.close();}
});
test.after(async()=>{dom.window.close();await rm(dir,{recursive:true,force:true});});
