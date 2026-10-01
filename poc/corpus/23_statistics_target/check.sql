INSERT INTO auth.samples VALUES (1, 1, 1);
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_statistic_ext
                   WHERE stxname = 'samples_ab' AND stxnamespace = 'auth'::regnamespace AND stxstattarget = 200) THEN
        RAISE EXCEPTION 'statistics target not set on auth.samples_ab';
    END IF;
END $$;
