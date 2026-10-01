INSERT INTO auth.roles (id, code) VALUES (1, 'admin'), (2, 'viewer')
ON CONFLICT (code) DO UPDATE SET code = EXCLUDED.code;

INSERT INTO auth.user_roles (user_id, role_id)
SELECT l.user_id, r.id
FROM auth.legacy_user_roles l
JOIN auth.roles r ON r.code = l.role_code
WHERE NOT EXISTS (
    SELECT 1 FROM auth.user_roles ur WHERE ur.user_id = l.user_id AND ur.role_id = r.id
);

UPDATE auth.roles SET code = upper(code) WHERE id IN (SELECT role_id FROM auth.user_roles);

UPDATE auth.user_roles ur
SET role_id = r.id
FROM auth.roles r
WHERE r.code = 'ADMIN' AND ur.role_id = r.id;

DELETE FROM auth.legacy_user_roles l
USING auth.roles r
WHERE upper(l.role_code) = r.code;

DELETE FROM auth.legacy_user_roles WHERE role_code IS NULL RETURNING user_id;
