DO $$
BEGIN
    CREATE TYPE job_state AS ENUM ('queued', 'running', 'done');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'job_priority') THEN
        CREATE TYPE job_priority AS ENUM ('low', 'high');
    END IF;
END
$$;

CREATE TABLE jobs (
    id       bigserial PRIMARY KEY,
    state    job_state    NOT NULL DEFAULT 'queued',
    priority job_priority NOT NULL DEFAULT 'low'
);

DO $$
DECLARE
    i int;
BEGIN
    FOR i IN 1..3 LOOP
        INSERT INTO jobs (state) VALUES ('queued');
    END LOOP;
    UPDATE jobs SET state = 'done'::job_state WHERE id = 1;
END
$$;

DO LANGUAGE plpgsql $do$
BEGIN
    IF (SELECT count(*) FROM jobs) <> 3 THEN
        RAISE EXCEPTION 'expected 3 jobs, got %', (SELECT count(*) FROM jobs);
    END IF;
END
$do$;
