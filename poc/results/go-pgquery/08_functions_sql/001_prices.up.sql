CREATE TABLE auth.prices (
    id     int PRIMARY KEY,
    amount numeric NOT NULL
);

CREATE FUNCTION auth.add_vat(amount numeric) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $$ SELECT amount * 1.2 $$;

CREATE FUNCTION auth.price_with_vat(p_id int) RETURNS numeric
    LANGUAGE sql STABLE
    AS $$
        SELECT auth.add_vat(amount) FROM auth.prices WHERE id = p_id
    $$;

CREATE FUNCTION auth.expensive_prices(threshold numeric) RETURNS SETOF auth.prices
    LANGUAGE sql STABLE
    AS $$ SELECT * FROM auth.prices WHERE amount > threshold $$;

CREATE PROCEDURE auth.reset_prices(new_amount numeric)
    LANGUAGE sql
    AS $$ UPDATE auth.prices SET amount = new_amount $$;

ALTER TABLE auth.prices ADD COLUMN amount_with_vat numeric GENERATED ALWAYS AS (auth.add_vat(amount)) STORED;
ALTER TABLE auth.prices ADD CONSTRAINT prices_positive CHECK (auth.add_vat(amount) > 0);
CREATE INDEX prices_vat_idx ON auth.prices (auth.add_vat(amount));
COMMENT ON FUNCTION auth.add_vat(numeric) IS 'Adds 20% VAT';
GRANT EXECUTE ON FUNCTION auth.add_vat(numeric) TO PUBLIC;
ALTER FUNCTION auth.price_with_vat(int) COST 50;
CALL auth.reset_prices(1);
