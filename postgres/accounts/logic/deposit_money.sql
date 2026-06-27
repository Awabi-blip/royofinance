--TODO: 
--validate the money does not exdeed 40lakh pkr
--validate that if you depositd money in the last 12 hours, you cant again
--validate the admin has a matching branch with customer
CALL deposit_money(
    '9f187eb8-a436-4464-824f-d0d8dff6e30f'::UUID,
    'b13ab668-31ac-4c14-87a8-7b1efc500f36'::UUID,
    '15000.00'::DECIMAL(9,2),
    now()
);

CREATE OR REPLACE PROCEDURE deposit_money(
    p_account_number UUID, 
    p_customer_id UUID,
    p_deposit_amount DECIMAL(9,2),
    p_happened_at TIMESTAMPTZ DEFAULT NULL
)
SECURITY DEFINER
AS $$
DECLARE
    v_depositer_id UUID;
    v_customer_branch_id SMALLINT;
    v_account_type e_account_type;
    v_user_balance DECIMAL(18,2);
    v_staff_id UUID;
    v_staff_role e_user_roles;
BEGIN

    IF p_deposit_amount > 4000000 THEN
        RAISE EXCEPTION 'deposit amount is greater than bank allowed limit (i hope youre not smuggling drugs)';
    END IF;

    IF p_deposit_amount < 50 THEN
        RAISE EXCEPTION 'beta ye piggy bank nahi real bank hai';
    END IF;

    SELECT branch_registered_in INTO v_customer_branch_id
    FROM user_auth WHERE id = p_customer_id;
    
    v_depositer_id := current_setting('myapp.user_id')::UUID; 

    IF v_depositer_id IS NULL THEN
        RAISE EXCEPTION 'id is empty';
    END IF;

    -- use exists for quick admin check
    SELECT role INTO v_staff_role
    FROM user_active_session_roles
    WHERE id = v_depositer_id AND role IN ('admin', 'teller', 'owner')
    AND branch_id = v_customer_branch_id
    AND expires_at > now();

    -- activated by v_staff_id, v_staff_role yeah
    IF NOT FOUND THEN
        RAISE EXCEPTION 'staff not found or unauthorized';
    END IF;
    
    -- LOCK the row while depositing money
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

    -- give them all money under emergency lol 
    
    UPDATE user_bank_accounts
    SET balance = balance + p_deposit_amount
    WHERE customer_id = p_customer_id
    AND account_number = p_account_number
    AND expires_at > now();

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
        'deposit'::e_action_type,
        p_deposit_amount,
        p_happened_at,
        v_depositer_id,
        v_staff_role
    );

END;
$$ LANGUAGE plpgsql;

-- SELECT 1
-- FROM user_bank_accounts 
-- WHERE customer_id = p_customer_id
-- AND account_number = p_account_number


