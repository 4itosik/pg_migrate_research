CREATE TABLE auth.documents (id INT PRIMARY KEY, title TEXT NOT NULL, updated_at TIMESTAMPTZ, version INT NOT NULL DEFAULT 1);
CREATE TABLE auth.document_history (doc_id INT NOT NULL, title TEXT, version INT, changed_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp());
CREATE FUNCTION auth.documents_touch () RETURNS trigger LANGUAGE plpgsql AS $$DECLARE
prev_title auth.documents.title%TYPE;
last_entry auth.document_history%ROWTYPE;
BEGIN
prev_title := old.title;
INSERT INTO auth.document_history (doc_id, title, version) VALUES (old.id, prev_title, old.version);
SELECT * FROM auth.document_history WHERE doc_id = old.id ORDER BY changed_at DESC LIMIT 1 INTO last_entry;
new.updated_at := NOW();
new.version := last_entry.version + 1;
RETURN new;
END$$;
CREATE TRIGGER documents_touch_trg BEFORE UPDATE ON auth.documents FOR EACH ROW EXECUTE FUNCTION auth.documents_touch();
CREATE FUNCTION auth.document_title (p_id auth.documents.id%TYPE) RETURNS auth.documents.title%TYPE LANGUAGE sql STABLE AS $$SELECT title FROM auth.documents WHERE id = p_id$$;
