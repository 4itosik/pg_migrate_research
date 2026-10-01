INSERT INTO auth.documents (id, title) VALUES (1, 'draft');
UPDATE auth.documents SET title = 'final' WHERE id = 1;
DO $$ BEGIN
    IF (SELECT version FROM auth.documents WHERE id = 1) <> 2 THEN RAISE EXCEPTION 'trigger did not bump version'; END IF;
    IF (SELECT count(*) FROM auth.document_history) <> 1 THEN RAISE EXCEPTION 'history not written'; END IF;
    IF auth.document_title(1) <> 'final' THEN RAISE EXCEPTION 'document_title broken'; END IF;
END $$;
