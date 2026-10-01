CREATE TABLE auth.categories (id int PRIMARY KEY, parent_id int, name text NOT NULL);
INSERT INTO auth.categories VALUES (1, NULL, 'root'), (2, 1, 'child'), (3, 2, 'leaf');

CREATE TABLE auth.category_paths (id int PRIMARY KEY, path text NOT NULL);

WITH RECURSIVE tree AS (
    SELECT id, name::text AS path FROM auth.categories WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, tree.path || '/' || c.name
    FROM auth.categories c
    JOIN tree ON c.parent_id = tree.id
)
INSERT INTO auth.category_paths (id, path)
SELECT id, path FROM tree;

-- CTE with the name of a real table: the reference must stay unqualified
INSERT INTO auth.category_paths (id, path)
WITH categories AS (SELECT 999 AS id, 'from-cte' AS name)
SELECT id, name FROM categories;

-- an earlier CTE sees the real table, the main query sees the later CTE
WITH src AS (SELECT id FROM auth.category_paths WHERE id = 999),
     category_paths AS (SELECT id + 1000 AS id FROM src)
INSERT INTO auth.categories (id, parent_id, name)
SELECT id, NULL, 'shadow-check' FROM category_paths;

-- data-modifying CTE
WITH moved AS (
    DELETE FROM auth.category_paths WHERE id = 3 RETURNING id, path
)
INSERT INTO auth.category_paths (id, path)
SELECT id + 100, path FROM moved;
