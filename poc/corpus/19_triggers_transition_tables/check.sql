INSERT INTO auth.items_view VALUES (1, 5);
DO $$ BEGIN
    IF (SELECT count(*) FROM auth.items) <> 1 THEN RAISE EXCEPTION 'INSTEAD OF trigger broken'; END IF;
    IF (SELECT max(n) FROM auth.items_audit) <> 1 THEN RAISE EXCEPTION 'transition table trigger broken'; END IF;
END $$;
