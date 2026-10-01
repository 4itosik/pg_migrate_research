CREATE SEQUENCE auth.invoice_number_seq START 1000;

CREATE TABLE auth.invoices (
    id            serial PRIMARY KEY,
    number        bigint NOT NULL DEFAULT nextval('auth.invoice_number_seq'),
    legacy_number bigint DEFAULT nextval('auth.invoice_number_seq'::regclass)
);

ALTER SEQUENCE auth.invoice_number_seq OWNED BY auth.invoices.number;
SELECT setval('auth.invoice_number_seq', 5000, false);
SELECT setval(pg_get_serial_sequence('auth.invoices', 'id'), 100);
SELECT to_regclass('auth.invoices') IS NOT NULL AS invoices_exists;

CREATE TABLE auth.tickets (
    id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text
);
ALTER TABLE auth.tickets ALTER COLUMN id RESTART WITH 500;
ALTER SEQUENCE auth.invoices_id_seq INCREMENT BY 1;
