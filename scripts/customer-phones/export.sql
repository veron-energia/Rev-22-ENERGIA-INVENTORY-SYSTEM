-- Read-only full export in psql (not the paginated Customers UI export).
-- \copy writes to the psql client's current directory. Treat it as private data.
\copy (select id,full_name,phone,is_active,deleted_at from public.customers order by id) to 'customer-phones.csv' with (format csv,header true)
