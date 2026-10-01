DO $$ BEGIN
    IF NOT has_table_privilege('app_reader', 'auth.tenants', 'SELECT') THEN RAISE EXCEPTION 'grant missing'; END IF;
    IF has_table_privilege('app_reader', 'auth.tenants', 'INSERT') THEN RAISE EXCEPTION 'revoke missing'; END IF;
    IF NOT has_sequence_privilege('app_reader', 'auth.tenant_seq', 'USAGE') THEN RAISE EXCEPTION 'sequence grant missing'; END IF;
END $$;
