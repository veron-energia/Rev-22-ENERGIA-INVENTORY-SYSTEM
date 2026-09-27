> **Synthetic test data only.** This is an example of the review output, not an analysis of production customers. Run the tool on a complete private export to obtain actual review items.

# Customer phone dry run

DRY RUN — no database connection or writes

Input SHA-256: `b36320b5e6738672f864fae47586d7a8f0c879c68f2af4534bed59e5c217db18`

- total: 10
- non_deleted: 9
- proposed_changes: 2
- pending_review: 7
- over_capacity_groups: 1

## Pending manual review

| Customer ID | Name | Original phone | Suggested countries/numbers | Reason |
|---|---|---|---|---|
| 00000000-0000-4000-8000-000000001001 | Example Legacy A | 91234567 | SG: +6591234567 | Valid Singapore national phone pattern. More than 3 non-deleted customers normalize to this number; resolve the group manually. |
| 00000000-0000-4000-8000-000000001002 | Example Legacy B | 6591234567 | SG: +6591234567 | Validated country code without plus sign. More than 3 non-deleted customers normalize to this number; resolve the group manually. |
| 00000000-0000-4000-8000-000000001003 | Example Inactive C | +65 9123 4567 | SG: +6591234567 | Validated explicit international country code. More than 3 non-deleted customers normalize to this number; resolve the group manually. |
| 00000000-0000-4000-8000-000000001004 | Example Legacy D | +6591234567 | SG: +6591234567 | Validated explicit international country code. More than 3 non-deleted customers normalize to this number; resolve the group manually. |
| 00000000-0000-4000-8000-000000001006 | Example Ambiguous | 93234567 | SG: +6593234567; MY: +6093234567 | Ambiguous Singapore/Malaysia national number; confirm the phone country. |
| 00000000-0000-4000-8000-000000001008 | Example Unconfirmed MY | 123456789 | MY: +60123456789 | Possible Malaysian number; confirm country or supply +60. |
| 00000000-0000-4000-8000-000000001009 | Example Invalid | AFF-123 |  | Unsupported characters or extension; confirm the full phone number. |

The proposed plan excludes uncertain numbers and non-deleted records in over-capacity groups. Review it before applying; names, IDs, invoices, referrals and survey links are never merged or reassigned. Original values are included in this report and the database migration mapping.
