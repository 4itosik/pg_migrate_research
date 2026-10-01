CREATE SCHEMA auth;
CREATE TYPE op_kind AS ENUM (
    'credit',
    'debit'
);
CREATE FUNCTION apply_op(p_wallet integer, p_kind op_kind, p_amount numeric) RETURNS numeric
    LANGUAGE plpgsql
    AS $BODY$;
CREATE FUNCTION credit(p_wallet integer, p_amount numeric) RETURNS numeric
    LANGUAGE plpgsql
    AS $BODY$;
CREATE FUNCTION wallet_bump(p_wallet integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $BODY$;
CREATE FUNCTION wallet_report() RETURNS TABLE(wallet_id integer, balance numeric, ops bigint)
    LANGUAGE plpgsql STABLE
    AS $BODY$;
CREATE TABLE wallet_ops (
    id bigint NOT NULL,
    wallet_id integer NOT NULL,
    delta numeric NOT NULL
);
CREATE SEQUENCE wallet_ops_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE wallet_ops_id_seq OWNED BY wallet_ops.id;
CREATE TABLE wallets (
    id integer NOT NULL,
    balance numeric DEFAULT 0 NOT NULL
);
ALTER TABLE ONLY wallet_ops ALTER COLUMN id SET DEFAULT nextval('wallet_ops_id_seq'::regclass);
ALTER TABLE ONLY wallet_ops
    ADD CONSTRAINT wallet_ops_pkey PRIMARY KEY (id);
ALTER TABLE ONLY wallets
    ADD CONSTRAINT wallets_pkey PRIMARY KEY (id);
ALTER TABLE ONLY wallet_ops
    ADD CONSTRAINT wallet_ops_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES wallets(id);
