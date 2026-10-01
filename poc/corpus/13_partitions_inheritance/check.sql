INSERT INTO auth.events VALUES (1, '2025-05-05', '{}'), (2, '2026-05-05', '{}');
INSERT INTO auth.notes (id, body) VALUES (1, 'x');
DO $$ BEGIN
    IF (SELECT count(*) FROM auth.base_entity) <> 1 THEN RAISE EXCEPTION 'inheritance broken'; END IF;
    IF (SELECT count(*) FROM auth.events_2026) <> 1 THEN RAISE EXCEPTION 'partition broken'; END IF;
END $$;
