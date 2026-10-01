CREATE SCHEMA auth;
CREATE FUNCTION document_title(p_id integer) RETURNS text
    LANGUAGE sql STABLE
    AS $BODY$;
CREATE FUNCTION documents_touch() RETURNS trigger
    LANGUAGE plpgsql
    AS $BODY$;
CREATE TABLE document_history (
    doc_id integer NOT NULL,
    title text,
    version integer,
    changed_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);
CREATE TABLE documents (
    id integer NOT NULL,
    title text NOT NULL,
    updated_at timestamp with time zone,
    version integer DEFAULT 1 NOT NULL
);
ALTER TABLE ONLY documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (id);
CREATE TRIGGER documents_touch_trg BEFORE UPDATE ON documents FOR EACH ROW EXECUTE FUNCTION documents_touch();
