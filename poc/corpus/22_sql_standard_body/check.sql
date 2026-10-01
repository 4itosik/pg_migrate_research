INSERT INTO auth.prices (id, amount) VALUES (1, 10), (2, 100);
DO $$ BEGIN
    IF auth.add_vat(10) <> 12 THEN RAISE EXCEPTION 'add_vat broken'; END IF;
    IF auth.total_with_vat() <> 132 THEN RAISE EXCEPTION 'total_with_vat broken'; END IF;
END $$;
