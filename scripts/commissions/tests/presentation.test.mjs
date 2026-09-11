import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
const compiled = await build({stdin:{contents:"export * from './src/lib/cataloguePriceSearch';export * from './src/lib/affiliatePayoutPresentation';",resolveDir:process.cwd()},bundle:true,write:false,format:'esm'});
const { priceCents, searchCatalogueOptions, payoutExportColumns, payoutInRange, unavailableName } = await import('data:text/javascript;base64,'+Buffer.from(compiled.outputFiles[0].text).toString('base64'));
test('currency normalization uses exact cents and rejects unsupported precision/grouping',()=>{
 for(const q of ['72','72.00','$72','S$72','S$ 72.00',' 72 '])assert.equal(priceCents(q),7200);
 for(const q of ['1,272.45','$1,272.45','S$ 1 272.45'])assert.equal(priceCents(q),127245);
 for(const q of ['72.001','-72','1,27.00','72abc','NaN','Infinity'])assert.equal(priceCents(q),null);
 assert.equal(priceCents(0),0);assert.equal(priceCents(null),null);
});
test('exact selling price ranks first while names and numeric codes remain searchable',()=>{
 const rows=[{id:'code',label:'Code product',search:'Product SKU 7200',searchPrices:[99]}, {id:'price',label:'Price product',search:'Body product ABC',searchPrices:[72]}, {id:'unpriced',label:'Unpriced item',searchPrices:[null]}];
 for(const q of ['72','72.00','$72','S$72']) assert.equal(searchCatalogueOptions(rows,q)[0].id,'price');
 assert.deepEqual(searchCatalogueOptions(rows,'72').map(x=>x.id),['price','code']);
 assert.equal(searchCatalogueOptions(rows,'7200')[0].id,'code');assert.equal(searchCatalogueOptions(rows,'ABC')[0].id,'price');
 assert.equal(searchCatalogueOptions(rows,'0').some(x=>x.id==='unpriced'),false);
 assert.equal(searchCatalogueOptions([{label:'Unrelated selector',search:'Unaffected'}],'72').length,0);
});
test('store changes change selling-price matches; multiple available rental rates do not invent a final price',()=>{
 const storeA=[{label:'Product',searchPrices:[72]}], storeB=[{label:'Product',searchPrices:[90]}];
 assert.equal(searchCatalogueOptions(storeA,'$72').length,1);assert.equal(searchCatalogueOptions(storeB,'$72').length,0);
 assert.equal(searchCatalogueOptions([{label:'Rental',searchPrices:[72,200,500]}],'S$200').length,1);
 assert.equal(searchCatalogueOptions([{label:'Rental',searchPrices:[72,200,500]}],'144').length,0);
});
test('history/export uses corrected payment dates, effective amounts and readable identity/method',()=>{
 const p={id:'p',referrer_customer_id:'ref',payout_month:'2020-01-01',total_amount:'100.00',total_tier1:'75.00',total_tier2:'25.00',payment_date:'2020-03-03',created_at:'2020-02-02',payment_method_name:'Old cheque',reference:'Verified',notes:'Correction',status:'paid'};
 const cols=Object.fromEntries(payoutExportColumns(()=> 'Historical Affiliate').map(c=>[c.header,c.value(p)]));
 assert.equal(cols.Amount,100);assert.equal(cols['Payment date'],'2020-03-03');assert.equal(cols.Method,'Old cheque');assert.equal(cols.Notes,'Correction');assert.equal(cols['Tier 1']+cols['Tier 2'],100);
 assert.equal(payoutInRange(p,'2020-03-01','2020-03-31'),true);assert.equal(payoutInRange(p,'2020-02-01','2020-02-28'),false);
 assert.equal(unavailableName('12345678-1234-1234-1234-123456789abc'),'Name unavailable · 12345678');
});
