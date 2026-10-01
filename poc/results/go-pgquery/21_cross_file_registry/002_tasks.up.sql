CREATE TABLE auth.tasks (
    id   int PRIMARY KEY,
    prio auth.priority NOT NULL DEFAULT 'low',
    code text NOT NULL CHECK (code = auth.normalize_code(code))
);
INSERT INTO auth.tasks VALUES (1, 'high'::auth.priority, auth.normalize_code('  AbC '));
ALTER TYPE auth.priority RENAME VALUE 'high' TO 'urgent';
ALTER TYPE auth.priority RENAME TO task_priority;
ALTER TABLE auth.tasks ADD COLUMN backup_prio auth.task_priority;
