DROP FUNCTION auth.credit(int, numeric);
DROP FUNCTION auth.wallet_report();
DROP FUNCTION auth.apply_op(int, auth.op_kind, numeric);
DROP TYPE auth.op_kind;
DROP TABLE auth.wallet_ops, auth.wallets;
