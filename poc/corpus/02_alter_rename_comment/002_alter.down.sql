COMMENT ON TABLE customers IS NULL;
ALTER INDEX customers_pkey RENAME TO accounts_pkey;
ALTER TABLE customers RENAME TO accounts;
ALTER TABLE orders DROP CONSTRAINT orders_account_fk;
ALTER TABLE accounts RENAME COLUMN title TO name;
ALTER TABLE accounts DROP COLUMN status;
