DO $$ BEGIN
    IF to_regclass('auth.big_v_idx') IS NULL THEN RAISE EXCEPTION 'index missing'; END IF;
END $$;
