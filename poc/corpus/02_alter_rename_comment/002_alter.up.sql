ALTER TABLE accounts ADD COLUMN status text NOT NULL DEFAULT 'active';
ALTER TABLE IF EXISTS accounts RENAME COLUMN name TO title;
ALTER TABLE orders
    ADD CONSTRAINT orders_account_fk FOREIGN KEY (account_id) REFERENCES accounts (id);
ALTER TABLE ONLY orders ALTER COLUMN account_id SET NOT NULL;
ALTER TABLE accounts RENAME TO customers;
ALTER INDEX accounts_pkey RENAME TO customers_pkey;
COMMENT ON TABLE customers IS 'Customers (renamed from accounts)';
COMMENT ON COLUMN customers.title IS 'Display name';
COMMENT ON INDEX customers_pkey IS 'Primary key';
COMMENT ON CONSTRAINT orders_account_fk ON orders IS 'FK to customers';
