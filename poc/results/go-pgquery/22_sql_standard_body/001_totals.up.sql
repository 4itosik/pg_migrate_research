CREATE TABLE auth.prices (
    id     int PRIMARY KEY,
    amount numeric NOT NULL
);

CREATE FUNCTION auth.add_vat(amount numeric) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    RETURN amount * 1.2;

CREATE FUNCTION auth.total_with_vat() RETURNS numeric
    LANGUAGE sql STABLE
BEGIN ATOMIC
    SELECT sum(auth.add_vat(amount)) FROM auth.prices;
END;
