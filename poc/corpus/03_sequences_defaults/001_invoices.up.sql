CREATE SEQUENCE invoice_number_seq START 1000;

CREATE TABLE invoices (
    id            serial PRIMARY KEY,
    number        bigint NOT NULL DEFAULT nextval('invoice_number_seq'),
    legacy_number bigint DEFAULT nextval('invoice_number_seq'::regclass)
);

ALTER SEQUENCE invoice_number_seq OWNED BY invoices.number;
SELECT setval('invoice_number_seq', 5000, false);
SELECT setval(pg_get_serial_sequence('invoices', 'id'), 100);
SELECT to_regclass('invoices') IS NOT NULL AS invoices_exists;

CREATE TABLE tickets (
    id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text
);
ALTER TABLE tickets ALTER COLUMN id RESTART WITH 500;
ALTER SEQUENCE invoices_id_seq INCREMENT BY 1;
