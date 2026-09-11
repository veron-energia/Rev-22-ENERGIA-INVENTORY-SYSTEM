# Commission payout and invoice interface work

Baseline: `d3738d5`, including the committed Stock History work and all preceding invoice/therapy changes. Existing untracked reports and tests are preserved. No AGENTS.md was found. No other agent is editing this scope.

Planned files: CommissionsPage; new commission components/helpers; new migrations 280 onward; isolated commission test scripts and setup/recovery documentation. Shared files: InvoicesPage, InvoiceRefundCancelChooser, invoice-controls.css and the opt-in price matching in SearchSelect. Existing commission rates, earning rules and staff payout behavior are preserved. No branch switch, reset, stash, commit, push, deployment or production write.

Write tests use a new exclusive `.commission-test/data` PostgreSQL cluster, port 55444, database `energia_commission_test`. Prior test clusters are not changed.
