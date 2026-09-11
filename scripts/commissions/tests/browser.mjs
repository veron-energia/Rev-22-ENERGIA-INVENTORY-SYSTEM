import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
await mkdir('.commission-test/browser', { recursive: true });
const mock = `export const supabase={async rpc(name,args){window.calls.push({name,args});
 if(name==='affiliate_payout_overview') {if(window.failRefresh){window.failRefresh=false;return {error:{message:'Connection interrupted'}};}return {data:structuredClone(window.state)};}
 if(name==='commission_referrer_names'){if(window.failNames){window.failNames=false;return {error:{code:'PGRST202',message:'commission_referrer_names missing from schema cache'}};} return {data:[{id:'ref-active',full_name:'Active Affiliate'},{id:'ref-deleted',full_name:'Historical Affiliate',deleted_at:'2020-01-01'}]};}
 if(name==='record_affiliate_payout'||name==='correct_affiliate_payout'){
   const replay=window.replays[args.p_request_id];if(replay)return {data:replay};
   let p=window.state.payouts.find(p=>p.id===args.p_payout_id);const prev=p?.total_amount||0;
   if(!p){p={id:'payment-'+window.state.payouts.length,referrer_customer_id:args.p_referrer_customer_id,payout_month:args.p_month,total_tier1:0,total_tier2:0,status:'paid',version:0,allocation_state:'verified'};window.state.payouts.push(p);}
   p.total_amount=Number(args.p_amount);p.total_tier1=p.total_amount;p.version++;p.payment_method_id=args.p_payment_method_id;p.payment_method_name='Bank Transfer';p.payment_date=args.p_payment_date;p.reference=args.p_reference;p.notes=args.p_notes;
   const g=window.state.groups.find(g=>g.referrer===p.referrer_customer_id);g.paid+=p.total_amount-prev;g.balance-=p.total_amount-prev;
   const result={id:p.id,amount:p.total_amount,version:p.version};window.replays[args.p_request_id]=result;
   if(window.loseSave){window.loseSave=false;return {error:{message:'Network response lost'}};}
   return {data:result};
 }
 if(name==='affiliate_payout_history')return {data:{original:{total_amount:150,payment_date:'2020-01-01',payment_method_name:'Bank Transfer'},allocations:[{commission_id:'entry',invoice_no:'INV-123',tier:'tier1',amount:100}],changes:[{id:'change',version:2,editor:'Test Owner',created_at:'2020-01-02',reason:'Receipt verified',old_record:{total_amount:150},new_record:{total_amount:100,reference:'Correct reference',notes:'Receipt checked'}}]}};
 return {data:[]};}};`;
const bundle = await build({ stdin: { contents: `import React from 'react';import {createRoot} from 'react-dom/client';import {AffiliatePayoutPanel} from './src/components/commissions/AffiliatePayoutPanel';function App(){const [mode,setMode]=React.useState('earned');return <><button onClick={()=>setMode('payouts')}>Show history</button><button onClick={()=>setMode('earned')}>Show balances</button><AffiliatePayoutPanel mode={mode} canPay={window.canPay} userId="owner" onSaved={()=>window.saved++}/></>;}createRoot(document.getElementById('root')).render(<App/>);`, resolveDir: process.cwd(), loader: 'tsx' }, bundle: true, write: false, outdir: '.commission-test/browser', format: 'iife', plugins: [{ name: 'offline', setup(b){b.onResolve({filter:/lib\/supabase$/},()=>({path:'mock',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:mock,loader:'js'}));} }] });
const css = (await readFile('src/styles/globals.css','utf8')) + (bundle.outputFiles.find(f=>f.path.endsWith('.css'))?.text || '');
const js = bundle.outputFiles.find(f=>f.path.endsWith('.js')).text;
const browser = await chromium.launch({headless:true,executablePath:process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
try {
 const page = await browser.newPage({viewport:{width:1200,height:900}}); const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',r=>r.fulfill({contentType:'text/html',body:'<!doctype html><html><body><div id="root"></div></body></html>'}));
 await page.goto('http://localhost/commission-fixture');
 await page.evaluate(()=>{window.calls=[];window.replays={};window.saved=0;window.canPay=true;window.failNames=true;window.state={groups:[{referrer:'ref-active',month:'2020-01-01',earned:300,adjustments:0,paid:0,balance:300},{referrer:'ref-deleted',month:'2020-01-01',earned:0,adjustments:0,paid:0,balance:0},{referrer:'missing-123456',month:'2020-01-01',earned:0,adjustments:0,paid:0,balance:0}],payouts:[],methods:[{id:'cash',name:'Cash',is_active:true},{id:'bank',name:'Bank Transfer',is_active:true},{id:'old',name:'Old cheque',is_active:false}]};});
 await page.addStyleTag({content:css.replace(/^@import.*$/gm,'')});await page.addScriptTag({content:js});
 await page.getByRole('button',{name:'Retry names'}).waitFor();assert.match(await page.locator('body').innerText(),/Name unavailable/);
 await page.getByRole('button',{name:'Retry names'}).click();await page.getByText('Active Affiliate',{exact:true}).waitFor();
 assert.match(await page.locator('body').innerText(),/Historical Affiliate \(deleted\)/);assert.match(await page.locator('body').innerText(),/Name unavailable · missing-/);
 await page.getByRole('button',{name:'Record payout',exact:true}).first().click();
 const modal=page.locator('.modal');await modal.getByLabel('Amount (S$)',{exact:true}).fill('150');
 await modal.getByRole('button',{name:'Payment method',exact:true}).click();await modal.getByRole('combobox').fill('bank');await modal.getByRole('combobox').press('Enter');
 assert.equal(await modal.getByLabel('Payment date (Singapore)').inputValue(),new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Singapore',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date()));
 await page.evaluate(()=>window.failRefresh=true);await modal.getByRole('button',{name:'Record payout',exact:true}).click();
 await page.getByRole('alert').filter({hasText:'Balances could not be refreshed'}).waitFor();assert.equal(await page.locator('.modal').count(),0);assert.match(await page.locator('body').innerText(),/Payout saved: S\$150.00/);
 assert.equal(await page.getByRole('button',{name:'Record payout',exact:true}).first().isDisabled(),true);
 await page.getByRole('button',{name:'Refresh payouts'}).click();await page.waitForFunction(()=>document.body.innerText.includes('Remaining payable: S$150.00'));
 await page.getByRole('button',{name:'Show history'}).click();await page.getByRole('button',{name:'Edit payout'}).click();
 await modal.getByLabel('Amount (S$)',{exact:true}).fill('100');await modal.getByLabel('Correction reason (required)').fill('Receipt verified');
 await modal.getByLabel('Payment date (Singapore)').fill('2020-02-02');await modal.getByLabel('Notes (optional)').fill('Receipt checked');
 await modal.getByRole('button',{name:'Save correction'}).click();await page.waitForFunction(()=>!document.querySelector('.modal'));
 assert.match(await page.locator('body').innerText(),/2020-02-02/);assert.match(await page.locator('body').innerText(),/Receipt checked/);
 await page.getByLabel('Payment date from').fill('2020-02-03');assert.equal(await page.getByRole('button',{name:'Edit payout'}).count(),0);
 await page.getByLabel('Payment date from').fill('2020-02-01');await page.getByRole('button',{name:'History & allocations'}).click();
 await page.getByText('INV-123').waitFor();await page.getByText('Version 2',{exact:false}).click();assert.match(await modal.innerText(),/Receipt verified/);assert.match(await modal.innerText(),/S\$150.00/);assert.match(await modal.innerText(),/S\$100.00/);
 await modal.getByRole('button',{name:'✕'}).click();await page.getByRole('button',{name:'Show balances'}).click();
 assert.match(await page.locator('body').innerText(),/Remaining payable: S\$200.00/);
 await page.getByRole('button',{name:'Record payout',exact:true}).first().click();await modal.getByRole('button',{name:'Payment method',exact:true}).click();await modal.getByRole('option',{name:'Bank Transfer'}).click();
 await page.evaluate(()=>window.loseSave=true);await modal.getByRole('button',{name:'Record payout',exact:true}).click();await modal.getByRole('button',{name:'Retry same save'}).waitFor();
 assert.equal(await modal.getByLabel('Amount (S$)',{exact:true}).isDisabled(),true);await modal.getByRole('button',{name:'Retry same save'}).click();await page.waitForFunction(()=>!document.querySelector('.modal'));
 assert.equal(await page.evaluate(()=>window.state.payouts.length),2);assert.equal(await page.evaluate(()=>window.state.groups[0].paid),300);
 const calls=await page.evaluate(()=>window.calls.filter(c=>c.name==='record_affiliate_payout'));
 assert.equal(calls.at(-1).args.p_request_id,calls.at(-2).args.p_request_id);
 await page.setViewportSize({width:390,height:844});await page.getByRole('button',{name:'Show history'}).click();await page.getByRole('button',{name:'Edit payout'}).first().click();
 await page.screenshot({path:'.commission-test/browser/payout-mobile.png',fullPage:true});assert.ok(await modal.getByRole('button',{name:'Save correction'}).isVisible());
 assert.deepEqual(errors,[]);console.log('PASS: name failure/retry, partial/corrected balances, payment search, SG date, date filter, history, save/refresh recovery, duplicate retry, mobile');
} finally {await browser.close();}
