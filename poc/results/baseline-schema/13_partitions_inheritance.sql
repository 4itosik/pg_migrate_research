CREATE SCHEMA auth;
CREATE TABLE base_entity (
    id integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE events (
    id bigint NOT NULL,
    created_at date NOT NULL,
    payload jsonb
)
PARTITION BY RANGE (created_at);
CREATE TABLE events_2025 (
    id bigint NOT NULL,
    created_at date NOT NULL,
    payload jsonb
);
CREATE TABLE events_2026 (
    id bigint NOT NULL,
    created_at date NOT NULL,
    payload jsonb
);
CREATE TABLE notes (
    id integer,
    created_at timestamp with time zone DEFAULT now(),
    body text
)
INHERITS (base_entity);
ALTER TABLE ONLY events ATTACH PARTITION events_2025 FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
ALTER TABLE ONLY events ATTACH PARTITION events_2026 FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
CREATE INDEX events_created_at_idx ON ONLY events USING btree (created_at);
CREATE INDEX events_2025_created_at_idx ON events_2025 USING btree (created_at);
CREATE INDEX events_2026_created_at_idx ON events_2026 USING btree (created_at);
ALTER INDEX events_created_at_idx ATTACH PARTITION events_2025_created_at_idx;
ALTER INDEX events_created_at_idx ATTACH PARTITION events_2026_created_at_idx;
