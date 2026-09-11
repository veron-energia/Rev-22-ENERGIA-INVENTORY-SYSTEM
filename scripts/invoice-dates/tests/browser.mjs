// Real invoice components and PDF/image/Excel outputs; synthetic data only.
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
import * as XLSX from 'xlsx';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
await mkdir('.invoice-date-test/browser', { recursive: true });
const common = { is_active: true, deleted_at: null };
const inv = (id, business_date, status = 'paid') => ({ ...common, id, invoice_no: `DATE-${id}`, store_id: 'store', customer_id: 'buyer', created_by: 'owner', business_date, created_at: '2020-01-31T16:00:00Z', edit_count: 1, status, subtotal: 100, total_amount: 100, discount_total: 0, manual_discount: 0, paid_amount: status === 'paid' ? 100 : 0 });
const tables = {
  stores: [{ ...common, id: 'store', name: 'Date Test Store', code: 'TEST' }],
  customers: [{ ...common, id: 'buyer', full_name: 'Date Test Buyer', phone: '+6591234567' }],
  profiles: [{ ...common, id: 'owner', full_name: 'Date Test Owner', role: 'owner' }],
  products: [{ ...common, id: 'product', name: 'Date Test Product', sku: 'TEST', product_type: 'own' }],
  store_product_prices: [{ ...common, store_id: 'store', product_id: 'product', selling_price: 100, member_price: 100, non_member_price: 100, availability: 'available' }],
  store_inventory: [{ store_id: 'store', product_id: 'product', current_qty: 100 }],
  payment_methods: [{ ...common, id: 'cash', name: 'Cash' }],
  invoices: [inv('recovered', '2020-02-01'), inv('backdated', '2019-12-15'), inv('pending', null, 'unpaid')],
  invoice_items: ['recovered', 'backdated', 'pending'].map(id => ({ id: `line-${id}`, invoice_id: id, line_kind: 'product', product_id: 'product', quantity: 1, unit_price: 100, line_total: 100, topup_amount: 0, foc_quantity: 0 })),
  invoice_payments: ['recovered', 'backdated'].map(id => ({ id: `payment-${id}`, invoice_id: id, payment_method_id: 'cash', amount: 100, created_at: '2020-03-01T00:00:00Z', entry_kind: 'receipt' })),
};
const mock = `export const supabase={from(table){
 let rows=[...(window.__tables[table]||[])],one=false,start=0,end=Infinity,orders=[];
 const q=new Proxy({}, {get(_,key){
  if(key==='then')return(ok,bad)=>{
   rows.sort((a,b)=>{for(const [field,opts] of orders){const av=a[field],bv=b[field];if(av==null&&bv==null)continue;if(av==null)return opts.nullsFirst?-1:1;if(bv==null)return opts.nullsFirst?1:-1;if(av!==bv)return String(av).localeCompare(String(bv))*(opts.ascending===false?-1:1);}return 0;});
   return Promise.resolve({data:one?(rows[0]||null):rows.slice(start,end+1),error:null}).then(ok,bad);};
  return(...args)=>{if(key==='eq'||key==='is')rows=rows.filter(r=>r[args[0]]===args[1]);if(key==='in')rows=rows.filter(r=>args[1].includes(r[args[0]]));if(key==='range'){start=args[0];end=args[1];window.__ranges.push([table,start,end]);}if(key==='order')orders.push([args[0],args[1]||{}]);if(key==='single'||key==='maybeSingle')one=true;return q;};
 }});return q;
},rpc(name,args){window.__calls.push({name,args});let data=[];
 if(name==='invoice_effective_affiliate')data={found:true,has_affiliate:false};
 if(name==='customer_search')data=window.__tables.customers;
 if(name==='my_assigned_store_id')data='store';
 if(name==='my_assigned_stores')data=[{store_id:'store',store_name:'Date Test Store',is_default:true}];
 if(name==='invoice_financial_position')data={total:100,net_received:100,outstanding:0,refund_due:0,refunded:0};
 if(name==='invoice_refund_options')data={financial:{total:100,net_received:100,outstanding:0},sources:[],stock:[],benefits:[],lines:[],review_required:false};
 if(name==='invoice_benefit_review_options')data={lines:[]};
 if(name==='correct_invoice'){
  window.__tables.invoices=window.__tables.invoices.map(i=>i.id===args.p_invoice_id?{...i,...args.p_header,edit_count:i.edit_count+1}:i);data={success:true};
 }
 if(name==='create_invoice_with_details'){
  window.__tables.invoices.push({...window.__tables.invoices[0],...args.p_header,id:'new',invoice_no:'DATE-new',status:'unpaid',paid_amount:0});
  window.__tables.invoice_items.push({...window.__tables.invoice_items[0],id:'line-new',invoice_id:'new'});data='new';
 }
 const q=new Proxy({}, {get(_,key){if(key==='then')return(ok,bad)=>Promise.resolve({data,error:null}).then(ok,bad);return()=>q;}});return q;
}};`;
const built = await build({ stdin: { contents: `import React from 'react';import {createRoot} from 'react-dom/client';import {BrowserRouter} from 'react-router-dom';import InvoicesPage from './src/pages/InvoicesPage';import {composeDocumentMessage} from './src/lib/sendDoc';window.__compose=composeDocumentMessage;createRoot(document.getElementById('root')).render(<BrowserRouter><InvoicesPage/></BrowserRouter>);`, resolveDir: process.cwd(), loader: 'tsx' }, bundle: true, define: { 'import.meta.env': '{}' }, format: 'iife', write: false,
 plugins: [{ name: 'fixture', setup(b) {
  b.onResolve({ filter: /(?:^|\/)supabase$/ }, () => ({ path: 'db', namespace: 'fixture' }));
  b.onResolve({ filter: /\/context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'fixture' }));
  b.onResolve({ filter: /\.css$/ }, () => ({ path: 'css', namespace: 'fixture' }));
  b.onLoad({ filter: /.*/, namespace: 'fixture' }, a => ({ contents: a.path === 'db' ? mock : a.path === 'auth' ? `export const useAuth=()=>({profile:{id:'owner',role:'owner'},assignments:[],loading:false});` : '', loader: 'js' }));
 } }],
});
const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
let checks = 0;const ok = (label, value) => { assert.ok(value, label);checks++;console.log('PASS:', label); };
try {
 const page = await browser.newPage({ viewport: { width: 1400, height: 1000 }, timezoneId: 'America/Los_Angeles' });
 page.setDefaultTimeout(10000);const errors=[];page.on('pageerror',e=>{errors.push(e.message);console.error('Browser error:',e.message);});
 await page.route('**/*',route=>route.request().url()==='https://invoice-dates.test/'?route.fulfill({contentType:'text/html',body:'<html><head></head><body><div id="root"></div></body></html>'}):route.abort());
 await page.goto('https://invoice-dates.test/');
 await page.evaluate(t=>{window.__tables=t;window.__calls=[];window.__ranges=[];window.__printed='';window.open=()=>({document:{write:html=>window.__printed=html,close(){}}});window.__imageText=[];const original=CanvasRenderingContext2D.prototype.fillText;CanvasRenderingContext2D.prototype.fillText=function(text,...args){window.__imageText.push(text);return original.call(this,text,...args);};},tables);
 await page.addStyleTag({content:(await readFile('src/styles/globals.css','utf8')).replace(/^@import.*$/gm,'')+'\n'+await readFile('src/components/invoices/invoice-controls.css','utf8')});
 await page.addScriptTag({content:built.outputFiles[0].text});
 const search=page.getByPlaceholder('Search invoice number, customer, store, payment method or invoice date…');
 await page.getByRole('button',{name:'View',exact:true}).first().waitFor();
 ok('confirmed dates sorted by business date, pending last', (await page.locator('tbody tr td:first-child strong').allTextContents()).join(',')==='DATE-recovered,DATE-backdated,DATE-pending');
 await search.fill('15 Dec 2019');ok('search uses the selected date, not creation date',await page.locator('tbody tr').count()===1&&(await page.locator('tbody').textContent()).includes('DATE-backdated'));
 await search.fill('');await page.getByLabel('Invoice date from',{exact:true}).fill('2020-02-01');await page.getByLabel('Invoice date to',{exact:true}).fill('2020-02-01');
 ok('same-day filter includes only recovered invoice across time zones',await page.locator('tbody tr').count()===1&&(await page.locator('tbody').textContent()).includes('DATE-recovered'));
 await page.getByRole('button',{name:'View',exact:true}).click();
 ok('details show the recovered business date',(await page.getByTestId('invoice-detail-date').textContent()).includes('01/02/2020'));
 await page.getByRole('button',{name:'Print',exact:true}).click();
 ok('both printed copies use the recovered date',await page.evaluate(()=>window.__printed.match(/Date: 01\/02\/2020/g)?.length===2));
 let downloadPromise=page.waitForEvent('download');await page.getByRole('button',{name:'PDF',exact:true}).click();let download=await downloadPromise;
 let pdf=await readFile(await download.path());ok('real downloaded PDF uses the recovered date',pdf.toString('latin1').includes('Date: 01/02/2020'));
 downloadPromise=page.waitForEvent('download');await page.getByRole('button',{name:'Image',exact:true}).click();await downloadPromise;
 ok('real rendered image uses the recovered date',await page.evaluate(()=>window.__imageText.includes('Date: 01/02/2020')));
 await page.getByRole('button',{name:'Correct Invoice',exact:true}).click();
 ok('Correct Invoice loads the saved date',await page.getByLabel('Invoice business date',{exact:true}).inputValue()==='2020-02-01');
 await page.getByLabel('Notes',{exact:true}).fill('Delivery note only');await page.getByPlaceholder('e.g. Wrong quantity keyed at the till').fill('Verified delivery note');
 await page.getByRole('button',{name:'Save Changes',exact:true}).click();
 await page.getByRole('button',{name:'New Invoice',exact:true}).waitFor();
 ok('unrelated correction submits the saved date',await page.evaluate(()=>window.__calls.findLast(c=>c.name==='correct_invoice')?.args.p_header.business_date==='2020-02-01'));
 await page.getByRole('button',{name:'Export Excel',exact:true}).click();
 // The export range must also handle date-only strings in a western timezone.
 await page.locator('.modal input[type=date]').first().fill('2020-02-01');await page.locator('.modal input[type=date]').last().fill('2020-02-01');
 downloadPromise=page.waitForEvent('download');await page.getByRole('button',{name:'Export 1 row(s)',exact:true}).click();download=await downloadPromise;
 const wb=XLSX.read(await readFile(await download.path()));const exported=XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]]);
 ok('Excel exports recovered date in the correct range',exported.length===1&&exported[0].Date==='01/02/2020');
 await page.getByLabel('Invoice date status').selectOption('pending');
 ok('pending filter clears date bounds and keeps unresolved invoices visible',await page.locator('tbody tr').count()===1&&(await page.locator('tbody').textContent()).includes('DATE-pending'));
 // An invoice with no recorded date now simply shows the day it was created,
 // as one date. No second line, and no 'pending review' wording anywhere.
 ok('an invoice with no recorded date shows its creation date as the date',(await page.locator('tbody').textContent()).includes('01/02/2020'));
 ok('and shows no separate Created on line',!(await page.locator('tbody').textContent()).includes('Created on'));
 ok('and is not described as pending review',!(await page.locator('tbody').textContent()).includes('pending review'));
 await page.getByRole('button',{name:'View',exact:true}).click();
 ok('the detail shows that same date, not a pending-review message',(await page.getByTestId('invoice-detail-date').textContent()).includes('01/02/2020'));
 downloadPromise=page.waitForEvent('download');await page.getByRole('button',{name:'PDF',exact:true}).click();download=await downloadPromise;pdf=await readFile(await download.path());
 ok('the PDF carries one date and no Created on reference',pdf.toString('latin1').replace(/\\([()\\])/g,'$1').includes('01/02/2020')&&!pdf.toString('latin1').includes('Date pending review'));
 ok('an outgoing message carries one date and no creation label',await page.evaluate(()=>{const t=window.__compose({kindLabel:'Invoice',docNo:'PENDING',date:'01/02/2020',lines:[],totals:[]});return t.includes('01/02/2020')&&!t.includes('Created on');}));
 await page.getByRole('button',{name:'Edit Invoice',exact:true}).click();ok('unresolved Edit Invoice leaves the date blank',await page.getByLabel('Invoice business date',{exact:true}).inputValue()==='');
 await page.getByRole('button',{name:'Cancel',exact:true}).click();await page.getByRole('button',{name:'All dates',exact:true}).click();
 await page.getByRole('button',{name:'New Invoice',exact:true}).click();
 const today=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Singapore',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 ok('new invoice defaults to Singapore today in a western browser timezone',await page.getByLabel('Invoice business date',{exact:true}).inputValue()===today);
 // Select real searchable customer/product controls, then create/backdate.
 await page.getByLabel('Invoice business date',{exact:true}).fill('2017-06-01');
 await page.locator('.modal select').filter({has:page.locator('option[value=store]')}).first().selectOption('store');
 await page.getByRole('button',{name:'Search name, ID, phone or email…',exact:true}).click();await page.locator('.modal').getByText('Date Test Buyer',{exact:true}).last().click();
 await page.getByRole('button',{name:'Search product name or SKU…',exact:true}).click();await page.locator('.modal').getByText(/Date Test Product —/).last().click();
 await page.getByRole('button',{name:'Create Invoice',exact:true}).click();
 await page.getByRole('button',{name:'Close',exact:true}).first().waitFor();
 ok('creation submits the chosen backdate',await page.evaluate(()=>window.__calls.findLast(c=>c.name==='create_invoice_with_details')?.args.p_header.business_date==='2017-06-01'));
 ok('saved new invoice reopens with its selected date',(await page.getByTestId('invoice-detail-date').textContent()).includes('01/06/2017'));
 await page.getByRole('button',{name:'Close',exact:true}).first().click();
 // More than a PostgREST page: verify historical and pending rows are fetched.
 await page.evaluate(()=>{const sample=window.__tables.invoices[0];window.__tables.invoices=Array.from({length:1001},(_,n)=>({...sample,id:String(n).padStart(4,'0'),invoice_no:'PAGE-'+n,business_date:n===1000?null:'2020-02-01'}));});
 await page.getByRole('button',{name:'Refresh',exact:true}).click();await page.getByLabel('Invoice date status').selectOption('pending');
 await page.getByText('PAGE-1000',{exact:true}).waitFor();
 ok('pending invoice beyond 1000 rows is discoverable',await page.evaluate(()=>window.__ranges.some(x=>x[0]==='invoices'&&x[1]===1000)));
 await page.setViewportSize({width:375,height:950});await page.screenshot({path:'.invoice-date-test/browser/pending-mobile.png',fullPage:true});
 ok('no browser runtime errors',errors.length===0);await page.close();
 console.log(`${checks} invoice-date browser checks passed.`);
} catch(error) { const page=browser.contexts()[0]?.pages()[0]; if(page){await writeFile('.invoice-date-test/browser/failure.txt',await page.locator('body').innerText());await page.screenshot({path:'.invoice-date-test/browser/failure.png',fullPage:true});} throw error; } finally {await browser.close();}
