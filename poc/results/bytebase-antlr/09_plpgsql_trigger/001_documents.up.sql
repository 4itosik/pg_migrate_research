CREATE TABLE auth.documents (
    id         int PRIMARY KEY,
    title      text NOT NULL,
    updated_at timestamptz,
    version    int NOT NULL DEFAULT 1
);

CREATE TABLE auth.document_history (
    doc_id     int NOT NULL,
    title      text,
    version    int,
    changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE FUNCTION auth.documents_touch() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    prev_title auth.documents.title%TYPE;
    last_entry auth.document_history%ROWTYPE;
BEGIN
    prev_title := OLD.title;
    INSERT INTO auth.document_history (doc_id, title, version)
    VALUES (OLD.id, prev_title, OLD.version);

    SELECT * INTO last_entry
    FROM auth.document_history
    WHERE doc_id = OLD.id
    ORDER BY changed_at DESC
    LIMIT 1;

    NEW.updated_at := now();
    NEW.version := last_entry.version + 1;
    RETURN NEW;
END;
$$;

CREATE TRIGGER documents_touch_trg
    BEFORE UPDATE ON auth.documents
    FOR EACH ROW
    EXECUTE FUNCTION auth.documents_touch();

CREATE FUNCTION auth.document_title(p_id auth.documents.id%TYPE) RETURNS auth.documents.title%TYPE
LANGUAGE sql STABLE AS $$ SELECT title FROM auth.documents WHERE id = p_id $$;
