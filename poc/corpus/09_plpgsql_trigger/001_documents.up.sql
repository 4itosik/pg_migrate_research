CREATE TABLE documents (
    id         int PRIMARY KEY,
    title      text NOT NULL,
    updated_at timestamptz,
    version    int NOT NULL DEFAULT 1
);

CREATE TABLE document_history (
    doc_id     int NOT NULL,
    title      text,
    version    int,
    changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE FUNCTION documents_touch() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    prev_title documents.title%TYPE;
    last_entry document_history%ROWTYPE;
BEGIN
    prev_title := OLD.title;
    INSERT INTO document_history (doc_id, title, version)
    VALUES (OLD.id, prev_title, OLD.version);

    SELECT * INTO last_entry
    FROM document_history
    WHERE doc_id = OLD.id
    ORDER BY changed_at DESC
    LIMIT 1;

    NEW.updated_at := now();
    NEW.version := last_entry.version + 1;
    RETURN NEW;
END;
$$;

CREATE TRIGGER documents_touch_trg
    BEFORE UPDATE ON documents
    FOR EACH ROW
    EXECUTE FUNCTION documents_touch();

CREATE FUNCTION document_title(p_id documents.id%TYPE) RETURNS documents.title%TYPE
LANGUAGE sql STABLE AS $$ SELECT title FROM documents WHERE id = p_id $$;
