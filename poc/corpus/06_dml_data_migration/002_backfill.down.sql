DELETE FROM user_roles;
UPDATE roles SET code = lower(code);
