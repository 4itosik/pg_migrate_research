CREATE TABLE metrics (
    id    int         NOT NULL,
    host  text        NOT NULL,
    ts    timestamptz NOT NULL,
    value float8
);
ALTER TABLE metrics ADD PRIMARY KEY (id);
CREATE INDEX metrics_host_ts_idx ON metrics USING btree (host, ts DESC) INCLUDE (value) WHERE value IS NOT NULL;
ALTER INDEX metrics_host_ts_idx SET (fillfactor = 90);
REINDEX INDEX metrics_host_ts_idx;
CREATE STATISTICS metrics_host_ts_stats (dependencies) ON host, ts FROM metrics;
ALTER STATISTICS metrics_host_ts_stats SET STATISTICS 200;
ALTER TABLE metrics ALTER COLUMN value SET STATISTICS 500;
CLUSTER metrics USING metrics_pkey;
ANALYZE metrics;
CREATE RULE metrics_no_delete AS ON DELETE TO metrics DO INSTEAD NOTHING;
ALTER TABLE metrics OWNER TO CURRENT_USER;
LOCK TABLE metrics IN SHARE MODE;
TRUNCATE metrics;
