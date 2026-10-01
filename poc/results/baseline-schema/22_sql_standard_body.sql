CREATE SCHEMA auth;
CREATE FUNCTION add_vat(amount numeric) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    RETURN (amount * 1.2);
CREATE TABLE prices (
    id integer NOT NULL,
    amount numeric NOT NULL
);
CREATE FUNCTION total_with_vat() RETURNS numeric
    LANGUAGE sql STABLE
    BEGIN ATOMIC
 SELECT sum(add_vat(prices.amount)) AS sum
    FROM prices;
END;
ALTER TABLE ONLY prices
    ADD CONSTRAINT prices_pkey PRIMARY KEY (id);
