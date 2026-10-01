CREATE SCHEMA auth;
CREATE TYPE job_priority AS ENUM (
    'low',
    'high'
);
CREATE TYPE job_state AS ENUM (
    'queued',
    'running',
    'done'
);
CREATE TABLE jobs (
    id bigint NOT NULL,
    state job_state DEFAULT 'queued'::job_state NOT NULL,
    priority job_priority DEFAULT 'low'::job_priority NOT NULL
);
CREATE SEQUENCE jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE jobs_id_seq OWNED BY jobs.id;
ALTER TABLE ONLY jobs ALTER COLUMN id SET DEFAULT nextval('jobs_id_seq'::regclass);
ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (id);
