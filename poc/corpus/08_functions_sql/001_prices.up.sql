CREATE TABLE prices (
    id     int PRIMARY KEY,
    amount numeric NOT NULL
);

CREATE FUNCTION add_vat(amount numeric) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $$ SELECT amount * 1.2 $$;

CREATE FUNCTION price_with_vat(p_id int) RETURNS numeric
    LANGUAGE sql STABLE
    AS '
        SELECT add_vat(amount) FROM prices WHERE id = p_id
    ';

CREATE FUNCTION expensive_prices(threshold numeric) RETURNS SETOF prices
    LANGUAGE sql STABLE
    AS $$ SELECT * FROM prices WHERE amount > threshold $$;

CREATE PROCEDURE reset_prices(new_amount numeric)
    LANGUAGE sql
    AS $$ UPDATE prices SET amount = new_amount $$;

ALTER TABLE prices ADD COLUMN amount_with_vat numeric GENERATED ALWAYS AS (add_vat(amount)) STORED;
ALTER TABLE prices ADD CONSTRAINT prices_positive CHECK (add_vat(amount) > 0);
CREATE INDEX prices_vat_idx ON prices (add_vat(amount));
COMMENT ON FUNCTION add_vat(numeric) IS 'Adds 20% VAT';
GRANT EXECUTE ON FUNCTION add_vat(numeric) TO PUBLIC;
ALTER FUNCTION price_with_vat(int) COST 50;
CALL reset_prices(1);
