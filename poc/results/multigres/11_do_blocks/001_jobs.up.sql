DO 'BEGIN
CREATE TYPE auth.job_state AS ENUM (''queued'', ''running'', ''done'');
EXCEPTION
WHEN duplicate_object THEN
END';
DO 'BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = ''job_priority'') THEN
CREATE TYPE auth.job_priority AS ENUM (''low'', ''high'');
END IF;
END';
CREATE TABLE auth.jobs (id bigserial PRIMARY KEY, state auth.job_state NOT NULL DEFAULT 'queued', priority auth.job_priority NOT NULL DEFAULT 'low');
DO 'DECLARE
i int;
BEGIN
FOR i IN 1 .. 3 LOOP
INSERT INTO auth.jobs (state) VALUES (''queued'');
END LOOP;
UPDATE auth.jobs SET state = CAST(''done'' AS auth.job_state) WHERE id = 1;
END';
DO LANGUAGE plpgsql 'BEGIN
IF (SELECT COUNT(*) FROM auth.jobs) <> 3 THEN
RAISE EXCEPTION ''expected 3 jobs, got %'', (SELECT COUNT(*) FROM auth.jobs);
END IF;
END';
