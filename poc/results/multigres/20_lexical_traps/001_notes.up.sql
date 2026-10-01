CREATE TABLE auth.notes (id INT PRIMARY KEY, body TEXT NOT NULL DEFAULT 'INSERT INTO users VALUES (1)');
INSERT INTO auth.notes (id, body) VALUES (1, 'UPDATE users SET x = 1'), (2, 'FROM users
'), (3, 'it''s users table');
CREATE TABLE auth."my table" ("from" INT, "select" TEXT);
INSERT INTO auth."my table" ("from", "select") VALUES (1, 'x');
SELECT users."from" FROM auth."my table" AS users;
SELECT n.id FROM auth.notes AS n WHERE n.body LIKE '%users%';
