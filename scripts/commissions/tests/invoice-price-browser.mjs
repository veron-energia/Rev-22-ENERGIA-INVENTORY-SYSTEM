// Render the actual invoice page and selectors. All data and RPCs are synthetic.
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const common={is_active:true,deleted_at:null};
const tables={
 stores:[{id:'a',name:'Store A',...common},{id:'b',name:'Store B',...common}],
 profiles:[{id:'owner',full_name:'Owner',role:'owner',...common}], customers:[{id:'customer',full_name:'Test Customer',phone:'+6591119998',...common}],
 products:[{id:'product',name:'Priced Product',sku:'ITEM',...common},{id:'code',name:'Numeric Code Product',sku:'7200',cost_price:72,...common}],
 vouchers:[{id:'voucher',name:'Priced Voucher',code:'VCHR',...common}], promotions:[{id:'promo',name:'Priced Promotion',code:'PRM',...common}],
 unlimited_therapy_packages:[{id:'therapy',name:'Priced Therapy Package',duration_months:1,...common}],
 therapy_services:[{id:'session',name:'Priced Session',code:'SESS',standard_price:99,...common}],
 special_products:[{id:'special',name:'Priced Special',sku:'SPECIAL',sale_price:72,rate_day:72,rate_week:200,rate_month:500,rate_year:5000,...common}],
 payment_methods:[{id:'cash',name:'Cash',...common}],
 invoices:[{id:'invoice',invoice_no:'PRICE-HISTORY',store_id:'a',customer_id:'customer',created_by:'owner',status:'paid',created_at:'2020-01-01',business_date:'2020-01-01',paid_at:'2020-01-01',subtotal:31,total_amount:31,paid_amount:31,discount_total:0,manual_discount:0,edit_count:0,...common}],
 invoice_items:[{id:'line',invoice_id:'invoice',line_kind:'product',product_id:'product',quantity:2,unit_price:31,line_total:31,foc_quantity:1,foc_reason_id:'old-reason',foc_reason:'Saved FOC reason',topup_amount:0}],
 invoice_payments:[{id:'receipt',invoice_id:'invoice',payment_method_id:'cash',amount:31,entry_kind:'receipt',created_at:'2020-01-01'}],
};
for(const [table,key,id] of [['store_product_prices','product_id','product'],['voucher_store_prices','voucher_id','voucher'],['promotion_store_prices','promotion_id','promo'],['unlimited_therapy_store_prices','package_id','therapy']])tables[table]=['a','b'].map(store_id=>({[key]:id,store_id,selling_price:store_id==='a'?72:90,member_price:store_id==='a'?72:90,availability:'available',...common}));
tables.store_product_prices.push(...['a','b'].map(store_id=>({product_id:'code',store_id,selling_price:99,member_price:99,...common})));
tables.store_inventory=['a','b'].flatMap(store_id=>['product','code'].map(product_id=>({store_id,product_id,current_qty:100})));
tables.therapy_service_stores=['a','b'].map(store_id=>({store_id,service_id:'session',is_available:true,price_override:store_id==='a'?72:90}));
const mock=`export const supabase={from(t){let rows=[...(window.tables[t]||[])],one=false;const q=new Proxy({}, {get(_,k){if(k==='then')return(ok,bad)=>Promise.resolve({data:one?rows[0]||null:rows,error:null}).then(ok,bad);return(...args)=>{if(k==='eq')rows=rows.filter(r=>r[args[0]]===args[1]);if(k==='in')rows=rows.filter(r=>args[1].includes(r[args[0]]));if(k==='single'||k==='maybeSingle')one=true;return q;};}});return q;},rpc(name,args){window.calls.push({name,args});let data=[];
if(name==='customer_search')data=window.tables.customers;
if(name==='invoice_refund_options')data={financial:{net_received:31},sources:[],stock:[],benefits:[],lines:[],review_required:false};
if(name==='invoice_benefit_review_options')data={lines:[]};
if(name==='invoice_effective_affiliate')data={found:true,has_affiliate:false};
if(name==='invoice_financial_position')data={total:31,net_received:31,refunded:0,outstanding:0};
if(name==='credit_packages_for_store')data=[{id:'credit',name:'Priced Credit Package',customer_price:args.p_store_id==='a'?72:90,paid_credit_amount:1000}];
if(name==='premium_bundles_for_store')data=[{id:'bundle',name:'Priced Premium Bundle',customer_payment_amount:args.p_store_id==='a'?72:90,total_credit:1000}];
const q=new Proxy({}, {get(_,k){if(k==='then')return(ok,bad)=>Promise.resolve({data,error:null}).then(ok,bad);return()=>q;}});return q;}};
export const fetchCustomersByIds=async()=>window.tables.customers;export const mergeCustomers=(a,b)=>a;`;
const built=await build({stdin:{contents:`import React from 'react';import {createRoot} from 'react-dom/client';import {BrowserRouter} from 'react-router-dom';import Page from './src/pages/InvoicesPage';createRoot(document.getElementById('root')).render(<BrowserRouter><Page/></BrowserRouter>);`,resolveDir:process.cwd(),loader:'tsx'},bundle:true,write:false,format:'iife',define:{'import.meta.env':'{}'},plugins:[{name:'fixtures',setup(b){b.onResolve({filter:/(?:^|\/)supabase$/},()=>({path:'db',namespace:'fixture'}));b.onResolve({filter:/\/context\/AuthContext$/},()=>({path:'auth',namespace:'fixture'}));b.onResolve({filter:/\.css$/},()=>({path:'css',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},a=>({contents:a.path==='db'?mock:a.path==='auth'?`export const useAuth=()=>({profile:{id:'owner',role:'owner',full_name:'Owner'},assignments:[]});`:'',loader:'js'}));}}]});
const css=(await readFile('src/styles/globals.css','utf8')+'\n'+await readFile('src/components/invoices/invoice-controls.css','utf8')).replace(/^@import.*$/gm,'');
const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
let checks=0;
try{
 const page=await browser.newPage({viewport:{width:1280,height:1000}});page.setDefaultTimeout(8000);const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',r=>r.request().url()==='https://price.test/'?r.fulfill({contentType:'text/html',body:'<html><body><div id="root"></div></body></html>'}):r.abort());
 const mount=async()=>{await page.goto('https://price.test/');await page.evaluate(t=>{window.tables=t;window.calls=[];},tables);await page.addStyleTag({content:css});await page.addScriptTag({content:built.outputFiles[0].text});};
 const kinds=[['product','Search product name or SKU…','Priced Product'],['voucher','Search voucher name or code…','Priced Voucher'],['promotion','Search promotion name or code…','Priced Promotion'],['therapy','Search therapy package or session…','Priced Therapy Package'],['credit_package','Search Credit Package…','Priced Credit Package'],['premium_bundle','Search Premium Bundle…','Priced Premium Bundle'],['special_product','Search special product…','Priced Special'],['rental','Search special product…','Priced Special']];
 await mount();await page.getByRole('button',{name:'New Invoice',exact:true}).click();let modal=page.locator('.modal').last();
 const storeSelect=()=>modal.locator('select').filter({has:page.locator('option[value="a"]')}).first();
 await storeSelect().selectOption('a');
 for(const [kind,placeholder,expected] of kinds){
  await modal.locator('select').filter({has:page.locator('option[value="product"]')}).selectOption(kind);
  await modal.getByRole('button',{name:placeholder,exact:true}).click();const input=modal.getByPlaceholder(placeholder,{exact:true});
  for(const query of ['72','72.00','$72','S$72']){await input.fill(query);const popup=input.locator('..').locator('..').locator('..');assert.match(await popup.innerText(),new RegExp(expected));if(kind==='therapy')assert.match(await popup.innerText(),/Priced Session/);checks++;}
  if(kind==='product'){await input.fill('72');const popup=input.locator('..').locator('..').locator('..');const text=await popup.innerText();assert.ok(text.indexOf('Priced Product')<text.indexOf('Numeric Code Product'));await input.fill('7200');assert.match(await popup.innerText(),/Numeric Code Product/);checks+=2;}
  if(kind==='credit_package'||kind==='premium_bundle'){await input.fill('1000');assert.match(await input.locator('..').locator('..').locator('..').innerText(),/No matches/);checks++;}
  await modal.locator('h3').click();
 }
 await storeSelect().selectOption('b');await modal.getByRole('button',{name:'Search product name or SKU…',exact:true}).click();const input=modal.getByPlaceholder('Search product name or SKU…');await input.fill('$72');assert.match(await input.locator('..').locator('..').locator('..').innerText(),/No matches/);await input.fill('$90');assert.match(await input.locator('..').locator('..').locator('..').innerText(),/Priced Product/);checks+=2;
 // Open the real correction form. Searching catalogue 72 must leave the saved
 // price 31 and the historical FOC reason untouched in the submitted payload.
 await mount();await page.getByRole('button',{name:'View',exact:true}).first().click();
 const red=page.getByRole('button',{name:'Refund / Cancel',exact:true});await red.waitFor().catch(async e=>{console.log('Browser errors:',errors,'Page:',await page.locator('body').innerText());throw e;});assert.equal(await red.evaluate(el=>getComputedStyle(el).backgroundColor),'rgb(180, 35, 24)');
 await red.focus();await red.press('Enter');const chooser=page.getByRole('dialog');assert.match(await chooser.innerText(),/PRICE-HISTORY/);assert.match(await chooser.innerText(),/Payment still held: S\$31.00/);
 await page.keyboard.press('Shift+Tab');await page.keyboard.press('Tab');assert.ok(await chooser.evaluate(el=>el.contains(document.activeElement)));await page.keyboard.press('Escape');assert.equal(await red.evaluate(el=>el===document.activeElement),true);checks+=4;
 await page.getByRole('button',{name:'Correct Invoice',exact:true}).click();modal=page.locator('.modal').last();
 await modal.getByRole('button',{name:/Priced Product —/}).click();await modal.getByPlaceholder('Search product name or SKU…').fill('S$72');await modal.locator('h3').click();
 await modal.getByPlaceholder('e.g. Wrong quantity keyed at the till').fill('Verify historical pricing');
 await modal.getByRole('button',{name:'Save Changes',exact:true}).click();
 const calls=await page.evaluate(()=>window.calls);const correction=calls.find(c=>c.name==='correct_invoice');assert.ok(correction,JSON.stringify(calls.slice(-5)));
 const payload=correction.args.p_items[0];assert.equal(payload.unit_price,31);assert.equal(payload.foc_quantity,1);assert.equal(payload.foc_reason,'Saved FOC reason');checks+=3;
 await mkdir('.commission-test/browser',{recursive:true});await page.screenshot({path:'.commission-test/browser/invoice-price.png'});assert.deepEqual(errors,[]);
 console.log(`PASS: ${checks} real invoice selector / store / historical price & FOC / red chooser checks`);
}finally{await browser.close();}
