CREATE TABLE auth.tasks (id INT PRIMARY KEY, prio auth.priority NOT NULL DEFAULT 'low', code TEXT NOT NULL CHECK (code = auth.normalize_code(code)));
INSERT INTO auth.tasks VALUES (1, CAST('high' AS auth.priority), auth.normalize_code('  AbC '));
ALTER TYPE auth.priority RENAME VALUE 'high' TO 'urgent';
ALTER TYPE auth.priority RENAME TO task_priority;
ALTER TABLE auth.tasks ADD COLUMN backup_prio auth.task_priority;
