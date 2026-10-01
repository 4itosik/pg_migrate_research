CREATE SCHEMA auth;
CREATE TABLE invoices (
    id integer NOT NULL,
    number bigint NOT NULL,
    legacy_number bigint
);
CREATE SEQUENCE invoice_number_seq
    START WITH 1000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE invoice_number_seq OWNED BY invoices.number;
CREATE SEQUENCE invoices_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE invoices_id_seq OWNED BY invoices.id;
CREATE TABLE tickets (
    id bigint NOT NULL,
    code text
);
ALTER TABLE tickets ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME tickets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
ALTER TABLE ONLY invoices ALTER COLUMN id SET DEFAULT nextval('invoices_id_seq'::regclass);
ALTER TABLE ONLY invoices ALTER COLUMN number SET DEFAULT nextval('invoice_number_seq'::regclass);
ALTER TABLE ONLY invoices ALTER COLUMN legacy_number SET DEFAULT nextval('invoice_number_seq'::regclass);
ALTER TABLE ONLY invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (id);
ALTER TABLE ONLY tickets
    ADD CONSTRAINT tickets_pkey PRIMARY KEY (id);
