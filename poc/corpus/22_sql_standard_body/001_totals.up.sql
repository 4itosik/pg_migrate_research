CREATE TABLE prices (
    id     int PRIMARY KEY,
    amount numeric NOT NULL
);

CREATE FUNCTION add_vat(amount numeric) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    RETURN amount * 1.2;

CREATE FUNCTION total_with_vat() RETURNS numeric
    LANGUAGE sql STABLE
BEGIN ATOMIC
    SELECT sum(add_vat(amount)) FROM prices;
END;
