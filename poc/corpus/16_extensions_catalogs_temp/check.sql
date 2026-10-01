DO $$ BEGIN
    IF (SELECT count(*) FROM auth.api_keys WHERE owner_email = 'admin@example.com') <> 1 THEN RAISE EXCEPTION 'citext broken'; END IF;
    IF (SELECT n_live_tup FROM auth.table_stats WHERE relname = 'api_keys') <> 1 THEN RAISE EXCEPTION 'temp table flow broken'; END IF;
END $$;
