CREATE TABLE auth.events (
    id         bigint NOT NULL,
    created_at date   NOT NULL,
    payload    jsonb
) PARTITION BY RANGE (created_at);

CREATE TABLE auth.events_2025 PARTITION OF auth.events
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

CREATE TABLE auth.events_2026 (LIKE auth.events INCLUDING ALL);
ALTER TABLE auth.events ATTACH PARTITION auth.events_2026
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');

CREATE TABLE auth.events_default PARTITION OF auth.events DEFAULT;
ALTER TABLE auth.events DETACH PARTITION auth.events_default;
DROP TABLE auth.events_default;

CREATE INDEX events_created_at_idx ON auth.events (created_at);

CREATE TABLE auth.base_entity (
    id         int,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE auth.notes (body text) INHERITS (auth.base_entity);
ALTER TABLE auth.notes NO INHERIT auth.base_entity;
ALTER TABLE auth.notes INHERIT auth.base_entity;
