DO $$ BEGIN
    IF auth.credit(1, 10) <> 10 THEN RAISE EXCEPTION 'credit broken'; END IF;
    IF auth.apply_op(1, 'debit', 3) <> 7 THEN RAISE EXCEPTION 'debit broken'; END IF;
    IF (SELECT ops FROM auth.wallet_report() WHERE wallet_id = 1) <> 2 THEN RAISE EXCEPTION 'report broken'; END IF;
    IF auth.wallet_bump(1) <> 8 THEN RAISE EXCEPTION 'wallet_bump broken'; END IF;
END $$;
