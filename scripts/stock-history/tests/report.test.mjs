import {test} from 'node:test';import assert from 'node:assert/strict';import {build} from 'esbuild';import {mkdir} from 'node:fs/promises';
await mkdir('.stock-history-test',{recursive:true});await build({entryPoints:['src/components/stock-history/report.ts'],outfile:'.stock-history-test/report.mjs',bundle:true,format:'esm',platform:'node'});
const {collectStockReport,stockCell,stockMonth}=await import('../../../.stock-history-test/report.mjs');
const filters={from:'2020-01-01',to:'2020-01-02',search:'needle',products:['p'],locations:['store:a'],people:[],types:[]};
test('history export fetches all 6005 rows with unchanged permission-aware filters and one cutoff',async()=>{
 const calls=[],rows=Array.from({length:6005},(_,i)=>({id:String(i)}));const db={async rpc(name,args){calls.push({name,args});return{data:{rows:rows.slice(args.p_offset,args.p_offset+args.p_limit),total:rows.length,as_of:'2020-01-03',has_access:true}}}};
 assert.equal((await collectStockReport(db,'history',filters)).length,6005);assert.equal(calls.length,7);assert.ok(calls.every(c=>c.name==='stock_history_page'&&c.args.p_filters===filters));assert.ok(calls.slice(1).every(c=>c.args.p_as_of==='2020-01-03'));
});
test('table export retains separate product/location rows and uses table endpoint',async()=>{
 const db={async rpc(name){assert.equal(name,'stock_history_table');return{data:{has_access:true,total:2,rows:[{product_id:'p',location_key:'store:a'},{product_id:'p',location_key:'store:b'}]}}}};
 assert.equal((await collectStockReport(db,'table',filters)).length,2);
});
for(const scenario of ['failed','missing','duplicate','changed','revoked'])test(`export rejects ${scenario} pages rather than a partial export`,async()=>{
 let call=0;const db={async rpc(){if(!call++)return{data:{has_access:true,total:2,as_of:'fixed',rows:[{id:'first'}]}};
 return scenario==='failed'?{error:{message:'Read failed'}}:{data:{has_access:scenario!=='revoked',total:scenario==='changed'?3:2,as_of:'fixed',rows:scenario==='missing'?[]:[{id:scenario==='duplicate'?'first':'second'}]}};}};
 await assert.rejects(()=>collectStockReport(db,'history',filters));
});
test('untrusted text cannot become a spreadsheet formula; numeric effects remain numbers',()=>{for(const s of ['=1+1','+cmd','-cmd','@SUM(A1)',' \t=1'])assert.ok(stockCell(s).startsWith("'"));assert.equal(stockCell(-5),-5);assert.equal(stockCell('Product'), 'Product');});
test('default dates use Singapore calendar month to today',()=>{const d=stockMonth();assert.match(d.from,/^\d{4}-\d{2}-01$/);assert.equal(d.to,new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Singapore'}).format(new Date()));});
