DROP FUNCTION auth.document_title(int);
DROP TRIGGER IF EXISTS documents_touch_trg ON auth.documents;
DROP FUNCTION auth.documents_touch();
DROP TABLE auth.document_history, auth.documents;
