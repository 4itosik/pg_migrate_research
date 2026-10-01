INSERT INTO auth.prices (id, amount) VALUES (1, 10), (2, 100);
DO $$ BEGIN
    IF auth.price_with_vat(1) <> 12 THEN RAISE EXCEPTION 'price_with_vat broken'; END IF;
    IF auth.total_with_vat() <> 132 THEN RAISE EXCEPTION 'total_with_vat broken'; END IF;
    IF (SELECT count(*) FROM auth.expensive_prices(50)) <> 1 THEN RAISE EXCEPTION 'expensive_prices broken'; END IF;
END $$;
CALL auth.reset_prices(5);
