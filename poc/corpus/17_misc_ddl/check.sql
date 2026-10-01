INSERT INTO auth.metrics VALUES (1, 'host-1', now(), 1.0);
DELETE FROM auth.metrics;
DO $$ BEGIN
    IF (SELECT count(*) FROM auth.metrics) <> 1 THEN RAISE EXCEPTION 'rule broken'; END IF;
END $$;
