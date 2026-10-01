CREATE SCHEMA auth;
CREATE TABLE "my table" (
    "from" integer,
    "select" text
);
CREATE TABLE notes (
    id integer NOT NULL,
    body text DEFAULT 'INSERT INTO users VALUES (1)'::text NOT NULL
);
ALTER TABLE ONLY notes
    ADD CONSTRAINT notes_pkey PRIMARY KEY (id);
