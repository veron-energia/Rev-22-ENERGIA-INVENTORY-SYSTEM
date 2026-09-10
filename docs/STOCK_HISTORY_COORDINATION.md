# Stock History work

Starting point: commit `8c4cc91`, with invoice and therapy changes preserved. The later `a83f7ba` invoice fix was also preserved when it appeared during the work. Existing untracked reports are untouched. No repository AGENTS.md was found. No other agent is currently editing this scope.

Owned changes: StockMovementsPage, new stock-history-specific components/styles/test scripts, new migrations 270–272, and stock-history documentation. Shared files: AppLayout navigation (add staff Stock History link only), TransfersPage (shared read-only notes and source-only detail display), ExcelExport (catch a failed full-report fetch and display its error without downloading a partial file). The existing workbook implementation is reused. No new stock or transfer mutation privileges are granted. Direct transfer-table writes are closed while the authorized mutation functions are retained.

Tests use a new exclusive `.stock-history-test/data` PostgreSQL cluster, port 55443, database `energia_stock_history_test`. Other agents’ databases are untouched. No commit, push, deployment or production database changes are authorized.
