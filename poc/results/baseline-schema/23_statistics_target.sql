CREATE SCHEMA auth;
CREATE TABLE samples (
    id integer NOT NULL,
    a integer NOT NULL,
    b integer NOT NULL
);
ALTER TABLE ONLY samples
    ADD CONSTRAINT samples_pkey PRIMARY KEY (id);
CREATE STATISTICS samples_ab (ndistinct, dependencies) ON a, b FROM samples;
ALTER STATISTICS samples_ab SET STATISTICS 200;
COMMENT ON STATISTICS samples_ab IS 'a and b are correlated';
