# Energia Inventory &amp; Sales System

A multi-warehouse, multi-store, role-controlled inventory and sales platform built on
**React + TypeScript + Vite + Supabase (PostgreSQL)**.

This package is **Phase 1 — Foundation**: authentication, roles, and core master data
(Products, Warehouses, Stores, Staff assignments, Payment methods, Users &amp; roles).
Later phases add inventory, transfers, invoices, payments, commissions, refunds,
adjustments, audit logs, and reports.

---

## What's in Phase 1

| Module | What works |
|---|---|
| **Login** | Email/password auth via Supabase. Clear errors for missing config / missing profile. |
| **Roles** | Owner, Admin, Manager, Inventory Manager, Staff — enforced in both the UI and the database (RLS). |
| **Dashboard** | Role-aware welcome + live counts + the phased roadmap. |
| **Products** | Master data only (no stock fields). Own vs 3rd-party, SKU, category, cost, soft delete. |
| **Warehouses** | CRUD, manager+ only. |
| **Stores** | CRUD + staff assignment. Non-admins only see their assigned stores (enforced by RLS). |
| **Payment Methods** | CRUD, owner/manager only. |
| **Users &amp; Roles** | View users, edit role/status, guided two-step new-user flow. |

---

## Setup

### 1. Prerequisites
- Node.js 18+ and npm
- A Supabase project (you've already created one)

### 2. Install
```bash
npm install
```

### 3. Configure environment
Copy the example and fill in your Supabase project values
(Supabase dashboard → Project Settings → API):
```bash
cp .env.local.example .env.local
```
```
VITE_SUPABASE_URL=https://YOUR-PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-public-key
```
> Only the **anon public** key goes here. Never put the service role key in the frontend.

### 4. Set up the database
In the Supabase **SQL Editor**, run these three files in order:

1. `supabase/01_schema.sql` — tables, enums, indexes
2. `supabase/02_rls_policies.sql` — row-level security + helper functions
3. `supabase/03_starter_data.sql` — **after** you create the first Owner (see below)

### 5. Create the first Owner
1. Supabase dashboard → **Authentication → Users → Add user**. Enter your email + password.
2. Copy the new user's **UUID**.
3. Open `supabase/03_starter_data.sql`, paste the UUID and your email into the first
   `insert into public.profiles ...` block, then run the whole file in the SQL Editor.

### 6. Run
```bash
npm run dev
```
Open http://localhost:3000 and sign in with the Owner account.

---

## How roles map to permissions

| Capability | Owner | Manager | Admin | Inv. Manager | Staff |
|---|:-:|:-:|:-:|:-:|:-:|
| View products | ✓ | ✓ | ✓ | ✓ | ✓ |
| Manage products | ✓ | ✓ | ✓ | — | — |
| Manage warehouses | ✓ | ✓ | — | — | — |
| View all stores | ✓ | — | ✓ | — | — |
| Manage stores &amp; assignments | ✓ | ✓ | — | — | — |
| Manage payment methods | ✓ | ✓ | — | — | — |
| Manage users &amp; roles | ✓ | ✓ | — | — | — |

Store-scoped users (Manager, Inventory Manager, Staff) only see the stores they're
assigned to — this is enforced by Postgres RLS, not just the UI, so it holds even if
someone calls the API directly.

---

## Verify Phase 1 works

- [ ] Owner can sign in and lands on the dashboard.
- [ ] Products can be created without any stock fields.
- [ ] Own vs 3rd-party filter works.
- [ ] Warehouses and Stores CRUD works for Owner/Manager.
- [ ] A Staff user (created via the two-step flow, assigned to one store) only sees
      that store on the Stores page.
- [ ] Staff cannot see Warehouses, Payment Methods, or Users in the sidebar.
- [ ] Payment methods CRUD works for Owner/Manager.

Once these pass, we build **Phase 2 — Inventory** (warehouse &amp; store stock, manual
stock-in, transfers with approval, stock movement history) on top of this foundation.

---

## Project structure
```
energia-system/
├─ supabase/
│  ├─ 01_schema.sql          # tables, enums, indexes
│  ├─ 02_rls_policies.sql    # RLS + helper functions
│  └─ 03_starter_data.sql    # first owner, warehouse, store, payment methods
├─ src/
│  ├─ lib/supabase.ts        # Supabase client
│  ├─ context/AuthContext.tsx# session, profile, role, store assignments
│  ├─ types/index.ts         # DB types + permission helpers
│  ├─ components/
│  │  ├─ AppLayout.tsx        # role-gated sidebar + shell
│  │  └─ ui.tsx              # RoleGate, Modal, NoAccess
│  ├─ pages/                 # Login, Dashboard, Products, Warehouses, Stores, …
│  └─ styles/globals.css     # design tokens
└─ .env.local               # your Supabase keys (not committed)
```
