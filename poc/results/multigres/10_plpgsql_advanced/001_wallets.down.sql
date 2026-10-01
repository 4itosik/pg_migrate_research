DROP FUNCTION auth.wallet_bump(INT);
DROP FUNCTION auth.credit(INT, NUMERIC);
DROP FUNCTION auth.wallet_report();
DROP FUNCTION auth.apply_op(INT, auth.op_kind, NUMERIC);
DROP TYPE auth.op_kind;
DROP TABLE auth.wallet_ops, auth.wallets;
