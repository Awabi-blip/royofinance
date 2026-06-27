CALL withdraw_money(
    '4bbee994-ebda-49a0-90aa-1c1c267836c2'::UUID,
    'b13ab668-31ac-4c14-87a8-7b1efc500f36'::UUID,
    6900010124124,
    TRUE,
    now()
);

CREATE OR REPLACE PROCEDURE withdraw_money(
    p_account_number UUID, 
    p_customer_id UUID,
    p_withdraw_amount DECIMAL(9,2),
    p_emergency BOOLEAN,
    p_happened_at TIMESTAMPTZ DEFAULT NULL
)
SECURITY DEFINER
AS $$
DECLARE
    v_withdrawer_id UUID;
    v_customer_branch_id SMALLINT;
    v_account_type e_account_type;
    v_user_balance DECIMAL(18,2);
    v_staff_id UUID;
    v_staff_role e_user_roles;
BEGIN

    IF p_withdraw_amount > 4000000 THEN
        RAISE EXCEPTION 'with draw amount is greater than bank allowed limit (i hope youre not smuggling drugs)';
    END IF;

    IF p_withdraw_amount < 50 THEN
        RAISE EXCEPTION 'bhai kurkure khane hain to mere se lelo pese itne kam kyu withdraw krne';
    END IF;

    SELECT branch_registered_in INTO v_customer_branch_id
    FROM user_auth WHERE id = p_customer_id;
    
    v_withdrawer_id := current_setting('myapp.user_id')::UUID; 

    IF v_withdrawer_id IS NULL THEN
        RAISE EXCEPTION 'id is empty';
    END IF;

    -- use exists for quick admin check
    SELECT role INTO v_staff_role
    FROM user_active_session_roles
    WHERE id = v_withdrawer_id AND role IN ('admin', 'teller', 'owner')
    AND branch_id = v_customer_branch_id
    AND expires_at > now();

    -- activated by v_staff_id, v_staff_role yeah
    IF NOT FOUND THEN
        RAISE EXCEPTION 'staff not found or unauthorized';
    END IF;
    
    -- LOCK the row while withdrawing money
    SELECT balance 
    INTO v_user_balance
    FROM user_bank_accounts 
    WHERE customer_id = p_customer_id
    AND account_number = p_account_number
    AND expires_at > now()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'customer account not found';
    END IF;

    IF v_user_balance = 0 THEN
        RAISE EXCEPTION 'your account has no balance';
    END IF;

    -- give them all money under emergency lol (BABY GURL U SO DAMN FINE THO 2015 was so nostalgic)
    IF p_withdraw_amount > v_user_balance THEN
        
        IF p_emergency = TRUE THEN
            RAISE NOTICE 'withdrawing %s amount, emergency: active, amount balance lesser than withdraw amount', v_user_balance;
            
            UPDATE user_bank_accounts
            SET balance = balance - balance
            WHERE customer_id = p_customer_id
            AND account_number = p_account_number;

            p_withdraw_amount = v_user_balance;
        
        ELSE 
            RAISE EXCEPTION 'benjamins all in my pocket broke ahh cant withdraw that';
    
        END IF;
    
    ELSEIF p_withdraw_amount <= v_user_balance THEN
        
        UPDATE user_bank_accounts
        SET balance = balance - p_withdraw_amount
        WHERE customer_id = p_customer_id
        AND account_number = p_account_number;

    END IF; 
    
    IF p_happened_at IS NULL THEN
        p_happened_at := now();
    END IF;

    INSERT INTO deposit_withdraw_audit_logs(
        account_number,
        action_type,
        amount,
        happened_at,
        done_by,
        doer_role
    ) VALUES (
        p_account_number,
        'withdraw'::e_action_type,
        p_withdraw_amount,
        p_happened_at,
        v_withdrawer_id,
        v_staff_role
    );

END;
$$ LANGUAGE plpgsql;

-- SELECT 1
-- FROM user_bank_accounts 
-- WHERE customer_id = p_customer_id
-- AND account_number = p_account_number



