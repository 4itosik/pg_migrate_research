INSERT INTO auth.users (email) VALUES ('a@example.com');
INSERT INTO auth.sessions (user_id) SELECT id FROM auth.users;
DO $$ BEGIN
    IF (SELECT count(*) FROM auth.sessions) <> 1 THEN RAISE EXCEPTION 'sessions not inserted'; END IF;
END $$;
