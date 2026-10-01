INSERT INTO auth.invoices DEFAULT VALUES;
INSERT INTO auth.tickets (code) VALUES ('T-1');
DO $$ BEGIN
    IF (SELECT number FROM auth.invoices) <> 5000 THEN RAISE EXCEPTION 'unexpected invoice number'; END IF;
    IF (SELECT id FROM auth.invoices) <> 101 THEN RAISE EXCEPTION 'unexpected invoice id'; END IF;
    IF (SELECT id FROM auth.tickets) <> 500 THEN RAISE EXCEPTION 'unexpected ticket id'; END IF;
END $$;
