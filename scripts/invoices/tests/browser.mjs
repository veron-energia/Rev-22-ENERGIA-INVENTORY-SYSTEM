// Runs real invoice components against in-memory fixtures, with all network
// requests blocked. No application credentials or database are used.
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
await mkdir('.invoice-test/browser', { recursive: true });
const date='2026-09-01T01:00:00Z';
const common={is_active:true,deleted_at:null};
const tables={
 stores:[{id:'store',name:'Test Store',code:'TEST',...common}],
 customers:[{id:'customer',full_name:'Test Customer',phone:'+6591234567',...common},{id:'recipient',full_name:'Correct Recipient',phone:'+6591234568',...common}],
 profiles:[{id:'owner',full_name:'Test Owner',role:'owner',...common}],
 products:[{id:'socks',name:'Long Energia Socks',sku:'SOCK',product_type:'own',...common},{id:'gloves',name:'Energia Gloves',sku:'GLOV',product_type:'own',...common}],
 store_product_prices:['socks','gloves'].map(product_id=>({store_id:'store',product_id,selling_price:100,member_price:100,non_member_price:100,availability:'available',...common})),
 store_inventory:['socks','gloves'].map(product_id=>({store_id:'store',product_id,current_qty:100})),
 promotions:[{id:'promo',name:'Phone Width Bundle',code:'BUNDLE',...common}],
 promotion_store_prices:[{store_id:'store',promotion_id:'promo',selling_price:100,member_price:100,non_member_price:100,available_at_store:true,...common}],
 promotion_choice_groups:[{id:'group',promotion_id:'promo',label:'Socks or Gloves',choose_qty:2,item_kind:'product'},{id:'main',promotion_id:'promo',label:'Choose your main product',choose_qty:1,item_kind:'product'}],
 promotion_choice_options:['group','main'].flatMap(group_id=>['socks','gloves'].map(product_id=>({id:group_id+product_id,group_id,product_id}))),
 payment_methods:[{id:'cash',name:'Cash',...common},{id:'bank',name:'Bank Transfer',...common}],
 invoices:[{id:'invoice',invoice_no:'INV-TEST',store_id:'store',customer_id:'customer',status:'paid',subtotal:100,total_amount:100,paid_amount:100,discount_total:0,manual_discount:0,created_at:date,paid_at:date,business_date:'2026-09-01',created_by:'owner',edit_count:0,...common}],
 invoice_items:[{id:'line',invoice_id:'invoice',line_kind:'promotion',promotion_id:'promo',quantity:1,unit_price:100,line_total:100,topup_amount:0,foc_quantity:0}],
 invoice_promotion_selections:[{invoice_item_id:'line',group_id:'group',product_id:'socks',quantity:1},{invoice_item_id:'line',group_id:'group',product_id:'gloves',quantity:1},{invoice_item_id:'line',group_id:'main',product_id:'gloves',quantity:1}],
 invoice_payments:[{id:'payment',invoice_id:'invoice',payment_method_id:'cash',amount:100,created_at:date,entry_kind:'receipt'}],
};
const mock=`export const supabase={ from(table) {
 let rows=[...(window.__tables[table]||[])], one=false;
 const q=new Proxy({}, {get(_,key) {
  if(key==='then') return (ok,bad)=>Promise.resolve({data:one?(rows[0]||null):rows,error:null}).then(ok,bad);
  return (...args)=>{if(key==='eq')rows=rows.filter(r=>r[args[0]]===args[1]);if(key==='in')rows=rows.filter(r=>args[1].includes(r[args[0]]));if(key==='single'||key==='maybeSingle')one=true;return q;};
 }}); return q;
 }, rpc(name,args) {
 window.__calls.push({name,args});
 let data=[];
 if(name==='invoice_effective_affiliate')data={found:true,has_affiliate:false};
 if(name==='customer_search')data=window.__tables.customers;
 if(name==='invoice_financial_position')data={total:100,net_received:100,outstanding:0,refund_due:0,status:'paid'};
 if(name==='invoice_refund_options')data={financial:{total:100,net_received:100,outstanding:0,refund_due:0,status:'paid'},sources:[],stock:[],benefits:[{id:'benefit',invoice_item_id:'line',customer_id:'customer',customer_name:'Test Customer',store_id:'store',benefit_kind:'paid',remaining_value:60,max_refund:50}],lines:[]};
 if(name==='invoice_benefit_review_options')data={lines:[]};
 const q=new Proxy({}, {get(_,key){if(key==='then')return (ok,bad)=>Promise.resolve({data,error:null}).then(ok,bad);return()=>q;}});return q;
 }};`;
const result=await build({stdin:{contents:`import React from 'react';import {createRoot} from 'react-dom/client';import {BrowserRouter} from 'react-router-dom';import InvoicesPage from './src/pages/InvoicesPage';createRoot(document.getElementById('root')).render(<BrowserRouter><InvoicesPage/></BrowserRouter>);`,resolveDir:process.cwd(),loader:'tsx'},bundle:true,define:{'import.meta.env':'{}'},format:'iife',write:false,plugins:[{name:'isolated-fixtures',setup(b){
 b.onResolve({filter:/(?:^|\/)supabase$/},()=>({path:'db',namespace:'fixture'}));
 b.onResolve({filter:/\/context\/AuthContext$/},()=>({path:'auth',namespace:'fixture'}));
 b.onResolve({filter:/\.css$/},()=>({path:'css',namespace:'fixture'}));
 b.onLoad({filter:/.*/,namespace:'fixture'},a=>({contents:a.path==='db'?mock:a.path==='auth'?`export const useAuth=()=>({profile:{id:'owner',full_name:'Test Owner',role:'owner'},assignments:[],loading:false});`:'',loader:'js'}));
}}]});
const bundle=result.outputFiles[0].text;
const css=await readFile('src/styles/globals.css','utf8')+'\n'+await readFile('src/components/invoices/invoice-controls.css','utf8');
const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
try {
 for(const width of [320,375,390,430]){
  const page=await browser.newPage({viewport:{width,height:850},isMobile:true,hasTouch:true});
  page.setDefaultTimeout(8000); console.log('Testing width',width);
  const errors=[];page.on('pageerror',e=>{errors.push(e.message); console.log('Browser error:',e.message);});
  await page.route('**/*',route=>route.request().url()==='https://invoice.test/'?route.fulfill({contentType:'text/html',body:'<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div></body></html>'}):route.abort());
  await page.goto('https://invoice.test/');await page.evaluate(t=>{window.__tables=t;window.__calls=[];},tables);
  await page.addStyleTag({content:css.replace(/^@import.*$/gm,'')});console.log('Styles loaded'); await page.addScriptTag({content:bundle}); console.log('Invoice page mounted'); assert.equal(await page.evaluate(()=>getComputedStyle(document.body).backgroundColor),'rgb(246, 247, 245)','Application CSS must be loaded');
  await page.getByRole('button',{name:'New Invoice',exact:true}).click(); console.log('New invoice opened');
  await page.locator('select').filter({has:page.locator('option[value="store"]')}).selectOption('store');
  await page.locator('select').filter({has:page.locator('option[value="promotion"]')}).selectOption('promotion');
  await page.getByRole('button',{name:'Search promotion name or code…'}).click();
  await page.getByText('Phone Width Bundle',{exact:false}).last().click();
  await checkChoices(page,width,'new');
  await page.getByRole('button',{name:'Cancel',exact:true}).click();
  await page.getByRole('button',{name:'View',exact:true}).click();
  await page.getByRole('button',{name:'Correct Invoice',exact:true}).click();
  const qty=page.getByRole('spinbutton',{name:'Long Energia Socks quantity'}).first();
  assert.equal(await qty.inputValue(),'1','Saved promotion quantity must load');
  await checkChoices(page,width,'edit');
  await page.getByRole('button',{name:'Cancel',exact:true}).click();
  await page.getByRole('button',{name:'View',exact:true}).click();
  await page.getByRole('button',{name:'Correct payment amount / date',exact:true}).click();
  await page.getByLabel('Correct amount',{exact:true}).fill('75');
  await page.getByLabel('Actual payment date',{exact:true}).fill('2020-02-01');
  await page.getByRole('button',{name:'Payment method',exact:true}).click();
  await page.getByRole('combobox',{name:'Search payment method'}).fill('bank');
  await page.getByRole('combobox',{name:'Search payment method'}).press('Enter');
  await page.getByLabel('Reason (required)',{exact:true}).fill('Correct the receipt date and amount');
  await page.getByRole('button',{name:'Record with audit history'}).click();
  const call=await page.evaluate(()=>window.__calls.findLast(c=>c.name==='correct_invoice_payment'));
  assert.equal(call.args.p_amount,75);assert.equal(call.args.p_date,'2020-02-01');assert.equal(call.args.p_method_id,'bank');
  assert.ok(call.args.p_request_id,'Stable correction request id');
  await page.getByRole('button',{name:'Correct unused benefit recipient',exact:true}).click();
  await page.getByRole('button',{name:'Unused benefit',exact:true}).click();
  await page.getByRole('combobox',{name:'Search unused benefit'}).press('Enter');
  await page.locator('.invoice-recipient-picker').getByRole('button').click();
  await page.getByPlaceholder('Search name, ID, phone or email…').fill('Correct Recipient');
  await page.getByText('Correct Recipient',{exact:true}).click();
  await page.getByLabel('I confirm the selected unused balance should move to this recipient and store.').check();
  await page.getByLabel('Reason (required)',{exact:true}).fill('Correct the unused benefit recipient');
  await page.screenshot({path:`.invoice-test/browser/recipient-${width}.png`});
  assert.ok(await page.locator('.modal-body').evaluate(e=>e.scrollWidth<=e.clientWidth+1),'Recipient controls must fit the modal');
  await page.getByRole('button',{name:'Record with audit history'}).click();
  const transfer=await page.evaluate(()=>window.__calls.findLast(c=>c.name==='transfer_invoice_unused_benefit'));
  assert.equal(transfer.args.p_benefit_id,'benefit');assert.equal(transfer.args.p_customer_id,'recipient');assert.equal(transfer.args.p_store_id,'store');
  assert.ok(transfer.args.p_request_id);
  assert.deepEqual(errors,[],`Browser errors at ${width}`);
  console.log(`PASS Chromium ${width}px: new/edit promotion controls, payment correction and unused-recipient correction`);
  await page.close();
 }
} finally {await browser.close();}
async function checkChoices(page,width,mode){
 const group=page.locator('.invoice-choice-group').filter({has:page.getByText('Socks or Gloves',{exact:true})});
 await group.scrollIntoViewIfNeeded();
 const input=group.getByRole('spinbutton',{name:'Long Energia Socks quantity'});
 if(mode==='edit'){await group.getByRole('button',{name:'Remove Long Energia Socks',exact:true}).click();assert.equal(await input.inputValue(),'');}
 await group.getByRole('button',{name:'Add Long Energia Socks',exact:true}).click();
 assert.equal(await input.inputValue(),'1');
 await group.getByRole('button',{name:'Remove Long Energia Socks',exact:true}).click();
 assert.equal(await input.inputValue(),'');
 await input.fill('999');await input.blur();assert.ok(Number(await input.inputValue())<=2,'Choice limit');
 for(const b of await page.locator('.invoice-choice-stepper button').all()){
  await b.scrollIntoViewIfNeeded();const box=await b.boundingBox();
  assert.ok(box && box.x>=0 && box.x+box.width<=width+1,`${mode}: clipped control at ${width}: ${JSON.stringify(box)}`);
  assert.ok(box.width>=44 && box.height>=44,'Touch control minimum');
 }
 await page.screenshot({path:`.invoice-test/browser/${mode}-${width}.png`});

 assert.ok(await page.locator('.modal-body').evaluate(e=>e.scrollWidth<=e.clientWidth+1),`${mode}: horizontal modal overflow at ${width}`);
 await page.screenshot({path:`.invoice-test/browser/${mode}-${width}.png`});
}
