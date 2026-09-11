"""Render an existing read-only preview; never connects to any database.

Writes summary, one-row-per-invoice CSV, uncertain CSV and eligible JSON.
Optional --prepare-apply writes SQL for an operator to review/execute separately.
The original preview remains unchanged and every source hash is retained.
"""
import argparse, csv, json, pathlib, uuid
p=argparse.ArgumentParser()
p.add_argument('preview', type=pathlib.Path)
p.add_argument('output', type=pathlib.Path)
p.add_argument('--prepare-apply', action='store_true')
p.add_argument('--reason')
p.add_argument('--ids', type=pathlib.Path, help='Optional text file of reviewed eligible invoice UUIDs, one per line')
a=p.parse_args()
report=json.loads(a.preview.read_text());rows=report['rows']
assert len({r['invoice_id'] for r in rows})==len(rows), 'Preview contains duplicate invoices'
a.output.mkdir(parents=True,exist_ok=True)
fields=['invoice_id','invoice_no','status','store_id','store','existing_business_date','original_created_at',
        'singapore_creation_date','proposed_date','suggested_date','source','explanation','classification',
        'issues','recorded_business_dates','provenance_notes','eligible_received_amount','sales_to_add','deleted_at','evidence_hash']
def spreadsheet_cell(v):
    if isinstance(v,(list,dict)): v=json.dumps(v,ensure_ascii=False)
    # Protect spreadsheet users from formulas in imported invoice/store names.
    if isinstance(v,str) and v.startswith(('=','+','-','@','\t','\r','\n')): return "'"+v
    return v
for filename,selected in [('invoices.csv',rows),('uncertain.csv',[r for r in rows if r['classification']=='manual_review'])]:
    with (a.output/filename).open('w',newline='') as f:
        writer=csv.DictWriter(f,fields,extrasaction='ignore');writer.writeheader()
        writer.writerows({k:spreadsheet_cell(r.get(k)) for k in fields} for r in selected)
eligible=[r for r in rows if r['classification']=='eligible']
if a.ids:
    chosen={str(uuid.UUID(s.strip())) for s in a.ids.read_text().splitlines() if s.strip()}
    assert chosen <= {r['invoice_id'] for r in eligible}, 'Selection includes an unknown/ineligible invoice'
    eligible=[r for r in eligible if r['invoice_id'] in chosen]
(a.output/'eligible.json').write_text(json.dumps(eligible,indent=2)+'\n')
(a.output/'summary.md').write_text('# Invoice date preview\n\nGenerated: '+str(report['generated_at'])+'\n\n'+
    '\n'.join(f'- {key}: {value}' for key,value in report['counts'].items())+
    f"\n\nExpected additional invoice-date sales across the entire eligible preview: S${report['expected_sales_added']:.2f}.\n\n"+
    report['basis']+'\n\nUncertain records remain NULL. This tool has made no database changes.\n')
if a.prepare_apply:
    if not a.reason or not a.reason.strip(): p.error('--prepare-apply requires --reason')
    def literal(value): return "'"+str(value).replace("'","''")+"'"
    actor=str(uuid.UUID(report['actor']))
    for start in range(0,len(eligible),500):
        selected=eligible[start:start+500]
        payload=[{k:r[k] for k in ['invoice_id','proposed_date','evidence_hash']} for r in selected]
        batch=str(uuid.uuid4());stem=f'batch-{start//500+1:03d}-{batch}'
        sql=f"""-- PREPARED ONLY. Review against the original preview. Run once, then retain
-- this exact file and result for retry/reversal. Never change its batch payload.
\\set ON_ERROR_STOP on
begin;
set local timezone='UTC';
select set_config('request.jwt.claim.sub',{literal(actor)},true) as ignored \\gset
set local role authenticated;
select public.apply_invoice_date_recovery('{batch}',{literal(json.dumps(payload))}::jsonb,{literal(a.reason)});
commit;
"""
        (a.output/(stem+'.sql')).write_text(sql)
        (a.output/(stem+'-reverse.sql')).write_text(f"""-- PREPARED ONLY. Preview events/current dates/versions before executing.
\\set ON_ERROR_STOP on
begin;
select set_config('request.jwt.claim.sub',{literal(actor)},true) as ignored \\gset
set local role authenticated;
select public.reverse_invoice_date_recovery('{batch}','{uuid.uuid4()}','Reverse reviewed invoice date recovery');
commit;
""")
print(f'{len(rows)} invoices, {len(eligible)} selected eligible; files written to {a.output}; no database changes')
