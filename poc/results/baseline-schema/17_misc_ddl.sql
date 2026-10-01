CREATE SCHEMA auth;
CREATE TABLE metrics (
    id integer NOT NULL,
    host text NOT NULL,
    ts timestamp with time zone NOT NULL,
    value double precision
);
ALTER TABLE ONLY metrics ALTER COLUMN value SET STATISTICS 500;
ALTER TABLE ONLY metrics
    ADD CONSTRAINT metrics_pkey PRIMARY KEY (id);
ALTER TABLE metrics CLUSTER ON metrics_pkey;
CREATE INDEX metrics_host_ts_idx ON metrics USING btree (host, ts DESC) INCLUDE (value) WITH (fillfactor='90') WHERE (value IS NOT NULL);
CREATE STATISTICS metrics_host_ts_stats (dependencies) ON host, ts FROM metrics;
CREATE RULE metrics_no_delete AS
    ON DELETE TO metrics DO INSTEAD NOTHING;
