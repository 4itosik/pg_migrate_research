ALTER TABLE auth.accounts ADD COLUMN status text NOT NULL DEFAULT 'active';
ALTER TABLE IF EXISTS auth.accounts RENAME COLUMN name TO title;
ALTER TABLE auth.orders
    ADD CONSTRAINT orders_account_fk FOREIGN KEY (account_id) REFERENCES auth.accounts (id);
ALTER TABLE ONLY auth.orders ALTER COLUMN account_id SET NOT NULL;
ALTER TABLE auth.accounts RENAME TO customers;
ALTER INDEX auth.accounts_pkey RENAME TO customers_pkey;
COMMENT ON TABLE auth.customers IS 'Customers (renamed from accounts)';
COMMENT ON COLUMN auth.customers.title IS 'Display name';
COMMENT ON INDEX auth.customers_pkey IS 'Primary key';
COMMENT ON CONSTRAINT orders_account_fk ON auth.orders IS 'FK to customers';
