CREATE TABLE tasks (
    id   int PRIMARY KEY,
    prio priority NOT NULL DEFAULT 'low',
    code text NOT NULL CHECK (code = normalize_code(code))
);
INSERT INTO tasks VALUES (1, 'high'::priority, normalize_code('  AbC '));
ALTER TYPE priority RENAME VALUE 'high' TO 'urgent';
ALTER TYPE priority RENAME TO task_priority;
ALTER TABLE tasks ADD COLUMN backup_prio task_priority;
