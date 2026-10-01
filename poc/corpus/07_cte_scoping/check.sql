DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM auth.category_paths WHERE id = 999 AND path = 'from-cte') THEN
        RAISE EXCEPTION 'CTE shadowing broken';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM auth.categories WHERE id = 1999 AND name = 'shadow-check') THEN
        RAISE EXCEPTION 'CTE visibility broken';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM auth.category_paths WHERE id = 103 AND path = 'root/child/leaf') THEN
        RAISE EXCEPTION 'data-modifying CTE broken';
    END IF;
END $$;
