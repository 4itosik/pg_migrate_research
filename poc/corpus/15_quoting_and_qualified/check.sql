DO $$ BEGIN
    IF (SELECT count(*) FROM auth."order") <> 1 THEN RAISE EXCEPTION 'quoted table broken'; END IF;
    IF (SELECT "countryCode" FROM auth."UserProfiles") <> 'RU' THEN RAISE EXCEPTION 'cross-schema FK broken'; END IF;
END $$;
