CREATE SCHEMA auth;
CREATE TABLE customers (
    id integer NOT NULL,
    title text,
    status text DEFAULT 'active'::text NOT NULL
);
COMMENT ON TABLE customers IS 'Customers (renamed from accounts)';
COMMENT ON COLUMN customers.title IS 'Display name';
CREATE TABLE orders (
    id integer NOT NULL,
    account_id integer NOT NULL
);
ALTER TABLE ONLY customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);
ALTER TABLE ONLY orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);
COMMENT ON INDEX customers_pkey IS 'Primary key';
ALTER TABLE ONLY orders
    ADD CONSTRAINT orders_account_fk FOREIGN KEY (account_id) REFERENCES customers(id);
COMMENT ON CONSTRAINT orders_account_fk ON orders IS 'FK to customers';
