DO $$ BEGIN
    IF (SELECT body FROM auth.notes WHERE id = 1) <> 'UPDATE users SET x = 1' THEN RAISE EXCEPTION 'dollar-quoted literal modified'; END IF;
    IF (SELECT body FROM auth.notes WHERE id = 3) <> 'it''s users table' THEN RAISE EXCEPTION 'string literal modified'; END IF;
    IF (SELECT count(*) FROM auth."my table") <> 1 THEN RAISE EXCEPTION 'quoted table broken'; END IF;
END $$;
