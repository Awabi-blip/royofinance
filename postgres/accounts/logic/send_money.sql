CREATE OR REPLACE PROCEDURE send_money(
p_sender_account_number UUID,
p_receiver_account_number UUID,
p_amount DECIMAL(9,2))
SECURITY DEFINER
AS $$
DECLARE
v_sender_balance DECIMAL(19,2);
v_receiver_id UUID;
v_sender_id UUID;
BEGIN
    v_sender_id := current_setting('myapp.user_id')::UUID;

    IF NOT EXISTS 
    (
        SELECT 1
        FROM user_active_session_roles AS uasr
        WHERE uasr.id = v_sender_id
        AND uasr.role = 'customer'::e_user_roles
        AND uasr.expires_at > now()
    )
    THEN 
        RAISE EXCEPTION 'Operation failed: No id found for customer %', v_sender_id;
    END IF;

    IF p_sender_account_number = p_receiver_account_number THEN
        RAISE EXCEPTION
            'not possible';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION
            'not possible';
    END IF;

    IF p_amount > 4000000 THEN
        RAISE EXCEPTION '';
    END IF;


    SELECT customer_id
    INTO v_receiver_id
    FROM user_bank_accounts
    WHERE account_number = p_receiver_account_number;

    IF v_sender_id = v_receiver_id THEN
        RAISE EXCEPTION
            'not possible';
    END IF;


    PERFORM 1 FROM user_bank_accounts 
    WHERE customer_id IN (v_sender_id, v_receiver_id) 
    ORDER BY (customer_id) FOR UPDATE;
    
    SELECT balance INTO v_sender_balance
    FROM user_bank_accounts
    WHERE customer_id = v_sender_id 
    AND account_number = p_sender_account_number
    FOR UPDATE;

    IF v_sender_balance IS NULL THEN
        RAISE EXCEPTION 'no balance added, hence no transactions must take place, fair as all things must be. period.';
    END IF;

    IF v_sender_balance <= 0 OR v_sender_balance < p_amount THEN
        RAISE EXCEPTION 'not enough balance';
    END IF;

    UPDATE user_bank_accounts
    SET balance = balance - p_amount
    WHERE customer_id = v_sender_id
    AND account_number = p_sender_account_number;

    UPDATE user_bank_accounts
    SET balance = balance + p_amount
    WHERE customer_id = v_receiver_id
    AND account_number = p_receiver_account_number;

    INSERT INTO send_money_audit_logs (
    sender_account_number,
    receiver_account_number,
    amount
    ) VALUES (
        p_sender_account_number,
        p_receiver_account_number,
        p_amount
    );

END;
$$ LANGUAGE plpgsql;



