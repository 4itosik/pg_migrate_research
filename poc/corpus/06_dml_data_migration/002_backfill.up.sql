INSERT INTO roles (id, code) VALUES (1, 'admin'), (2, 'viewer')
ON CONFLICT (code) DO UPDATE SET code = EXCLUDED.code;

INSERT INTO user_roles (user_id, role_id)
SELECT l.user_id, r.id
FROM legacy_user_roles l
JOIN roles r ON r.code = l.role_code
WHERE NOT EXISTS (
    SELECT 1 FROM user_roles ur WHERE ur.user_id = l.user_id AND ur.role_id = r.id
);

UPDATE roles SET code = upper(code) WHERE id IN (SELECT role_id FROM user_roles);

UPDATE user_roles ur
SET role_id = r.id
FROM roles r
WHERE r.code = 'ADMIN' AND ur.role_id = r.id;

DELETE FROM legacy_user_roles l
USING roles r
WHERE upper(l.role_code) = r.code;

DELETE FROM legacy_user_roles WHERE role_code IS NULL RETURNING user_id;

-- FOR UPDATE OF names FROM items: they must stay unqualified
SELECT r.id FROM roles r JOIN user_roles ur ON ur.role_id = r.id FOR UPDATE OF r;
SELECT id FROM roles FOR NO KEY UPDATE OF roles SKIP LOCKED;
