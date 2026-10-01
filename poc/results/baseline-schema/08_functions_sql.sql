CREATE SCHEMA auth;
CREATE FUNCTION add_vat(amount numeric) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $BODY$;
COMMENT ON FUNCTION add_vat(amount numeric) IS 'Adds 20% VAT';
CREATE TABLE prices (
    id integer NOT NULL,
    amount numeric NOT NULL,
    amount_with_vat numeric GENERATED ALWAYS AS (add_vat(amount)) STORED,
    CONSTRAINT prices_positive CHECK ((add_vat(amount) > (0)::numeric))
);
CREATE FUNCTION expensive_prices(threshold numeric) RETURNS SETOF prices
    LANGUAGE sql STABLE
    AS $BODY$;
CREATE FUNCTION price_with_vat(p_id integer) RETURNS numeric
    LANGUAGE sql STABLE COST 50
    AS $BODY$;
CREATE PROCEDURE reset_prices(IN new_amount numeric)
    LANGUAGE sql
    AS $BODY$;
ALTER TABLE ONLY prices
    ADD CONSTRAINT prices_pkey PRIMARY KEY (id);
CREATE INDEX prices_vat_idx ON prices USING btree (add_vat(amount));
