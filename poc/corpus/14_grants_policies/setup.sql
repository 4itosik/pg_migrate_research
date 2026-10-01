DO $$ BEGIN CREATE ROLE app_reader; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
GRANT USAGE ON SCHEMA auth TO app_reader;
