COMMENT ON TABLE auth.customers IS NULL;
ALTER INDEX auth.customers_pkey RENAME TO accounts_pkey;
ALTER TABLE auth.customers RENAME TO accounts;
ALTER TABLE auth.orders DROP CONSTRAINT orders_account_fk;
ALTER TABLE auth.accounts RENAME COLUMN title TO name;
ALTER TABLE auth.accounts DROP COLUMN status;
