CREATE SCHEMA auth;
CREATE TABLE categories (
    id integer NOT NULL,
    parent_id integer,
    name text NOT NULL
);
CREATE TABLE category_paths (
    id integer NOT NULL,
    path text NOT NULL
);
ALTER TABLE ONLY categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);
ALTER TABLE ONLY category_paths
    ADD CONSTRAINT category_paths_pkey PRIMARY KEY (id);
