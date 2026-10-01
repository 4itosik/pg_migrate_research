DO $$ BEGIN
    IF (SELECT count(*) FROM auth.user_roles) <> 3 THEN RAISE EXCEPTION 'backfill failed'; END IF;
    IF (SELECT count(*) FROM auth.legacy_user_roles) <> 0 THEN RAISE EXCEPTION 'cleanup failed'; END IF;
END $$;
