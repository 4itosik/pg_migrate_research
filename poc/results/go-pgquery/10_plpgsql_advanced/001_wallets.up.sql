CREATE TABLE auth.wallets (
    id      int PRIMARY KEY,
    balance numeric NOT NULL DEFAULT 0
);
CREATE TABLE auth.wallet_ops (
    id        bigserial PRIMARY KEY,
    wallet_id int     NOT NULL REFERENCES auth.wallets (id),
    delta     numeric NOT NULL
);
CREATE TYPE auth.op_kind AS ENUM ('credit', 'debit');

CREATE FUNCTION auth.apply_op(p_wallet int, p_kind auth.op_kind, p_amount numeric) RETURNS numeric
LANGUAGE plpgsql AS $fn$
DECLARE
    v_delta   numeric := CASE WHEN p_kind = 'credit'::auth.op_kind THEN p_amount ELSE -p_amount END;
    v_balance auth.wallets.balance%TYPE;
    v_ops     int := (SELECT count(*) FROM auth.wallet_ops);
    r         record;
    c CURSOR (w int) FOR SELECT id FROM auth.wallet_ops WHERE wallet_id = w;
BEGIN
    PERFORM 1 FROM auth.wallets WHERE id = p_wallet FOR UPDATE;
    IF NOT FOUND THEN
        INSERT INTO auth.wallets (id) VALUES (p_wallet);
    END IF;

    INSERT INTO auth.wallet_ops (wallet_id, delta) VALUES (p_wallet, v_delta);

    UPDATE auth.wallets SET balance = balance + v_delta
    WHERE id = p_wallet
    RETURNING balance INTO v_balance;

    FOR r IN SELECT delta FROM auth.wallet_ops WHERE wallet_id = p_wallet LOOP
        v_ops := v_ops + 1;
    END LOOP;

    OPEN c(p_wallet);
    CLOSE c;

    CASE
        WHEN v_balance < 0 THEN
            RAISE NOTICE 'negative balance % for wallet %', v_balance, (SELECT id FROM auth.wallets WHERE id = p_wallet);
        ELSE
            NULL;
    END CASE;

    RETURN v_balance;
END
$fn$;

CREATE FUNCTION auth.wallet_report() RETURNS TABLE (wallet_id int, balance numeric, ops bigint)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
        SELECT w.id, w.balance, count(o.id)
        FROM auth.wallets w
        LEFT JOIN auth.wallet_ops o ON o.wallet_id = w.id
        GROUP BY w.id, w.balance;
END
$$;

CREATE FUNCTION auth.credit(p_wallet int, p_amount numeric) RETURNS numeric
LANGUAGE plpgsql AS $$
BEGIN
    RETURN auth.apply_op(p_wallet, 'credit', p_amount);
END
$$;
