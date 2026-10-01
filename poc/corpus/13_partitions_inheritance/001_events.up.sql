CREATE TABLE events (
    id         bigint NOT NULL,
    created_at date   NOT NULL,
    payload    jsonb
) PARTITION BY RANGE (created_at);

CREATE TABLE events_2025 PARTITION OF events
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

CREATE TABLE events_2026 (LIKE events INCLUDING ALL);
ALTER TABLE events ATTACH PARTITION events_2026
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');

CREATE TABLE events_default PARTITION OF events DEFAULT;
ALTER TABLE events DETACH PARTITION events_default;
DROP TABLE events_default;

CREATE INDEX events_created_at_idx ON events (created_at);

CREATE TABLE base_entity (
    id         int,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE notes (body text) INHERITS (base_entity);
ALTER TABLE notes NO INHERIT base_entity;
ALTER TABLE notes INHERIT base_entity;
