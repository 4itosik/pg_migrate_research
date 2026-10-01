DROP FUNCTION document_title(int);
DROP TRIGGER IF EXISTS documents_touch_trg ON documents;
DROP FUNCTION documents_touch();
DROP TABLE document_history, documents;
