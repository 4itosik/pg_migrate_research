-- CREATE TABLE users (id int);  <- a comment, must stay untouched
/* DROP TABLE accounts; INSERT INTO users VALUES (1); */
CREATE TABLE notes (
    id   int PRIMARY KEY,
    body text NOT NULL DEFAULT 'INSERT INTO users VALUES (1)'
);
INSERT INTO notes (id, body) VALUES
    (1, $q$UPDATE users SET x = 1$q$),
    (2, E'FROM users\n'),
    (3, 'it''s users table');
CREATE TABLE "my table" ("from" int, "select" text);
INSERT INTO "my table" ("from", "select") VALUES (1, 'x');
SELECT users."from" FROM "my table" AS users;
SELECT n.id FROM notes AS n WHERE n.body LIKE '%users%';
