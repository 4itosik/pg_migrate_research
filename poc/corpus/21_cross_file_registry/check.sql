DO $$ BEGIN
    IF (SELECT prio::text FROM auth.tasks WHERE id = 1) <> 'urgent' THEN RAISE EXCEPTION 'enum rename broken'; END IF;
    IF (SELECT code FROM auth.tasks WHERE id = 1) <> 'abc' THEN RAISE EXCEPTION 'function in CHECK broken'; END IF;
END $$;
