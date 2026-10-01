DELETE FROM auth.user_roles;
UPDATE auth.roles SET code = lower(code);
