DO $$ BEGIN
    IF (SELECT count(*) FROM auth.jobs WHERE state = 'done') <> 1 THEN RAISE EXCEPTION 'DO block update broken'; END IF;
END $$;
