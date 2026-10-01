CREATE SCHEMA auth;
CREATE TYPE task_priority AS ENUM (
    'low',
    'urgent'
);
CREATE FUNCTION normalize_code(code text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $BODY$;
CREATE TABLE tasks (
    id integer NOT NULL,
    prio task_priority DEFAULT 'low'::task_priority NOT NULL,
    code text NOT NULL,
    backup_prio task_priority,
    CONSTRAINT tasks_code_check CHECK ((code = normalize_code(code)))
);
ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (id);
