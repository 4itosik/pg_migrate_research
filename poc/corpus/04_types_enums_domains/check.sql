INSERT INTO auth.members (id, status, email, balance, previous_statuses)
VALUES (1, 'blocked', 'a@example.com', ROW(10.5, 'USD'), ARRAY['active']::auth.user_status[]);
DO $$ BEGIN
    IF (SELECT (balance).currency FROM auth.members WHERE id = 1) <> 'USD' THEN RAISE EXCEPTION 'composite type broken'; END IF;
END $$;
