DO $$ BEGIN
    IF (SELECT count(*) FROM auth.audit_log) <> 2 THEN RAISE EXCEPTION 'dynamic SQL broken'; END IF;
END $$;
