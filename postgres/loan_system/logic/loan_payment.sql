CREATE OR REPLACE PROCEDURE pay_for_loan(
    amount_paid DECIMAL(9,2),
    p_account_type e_account_type
)
SECURITY DEFINER AS $$
DECLARE
    v_customer_id UUID;
    v_loan_amount DECIMAL(9,2);
    v_loan_id INT;
    user_account_balance DECIMAL(19,2);
    v_remaining_amount DECIMAL(9,2);

BEGIN
    v_customer_id := current_setting('myapp.user_id')::UUID;

    IF NOT EXISTS 
    (
        SELECT 1
        FROM user_active_session_roles AS uasr
        WHERE uasr.id = v_customer_id
        AND uasr.role = 'customer'::e_user_roles
        AND uasr.expires_at > now()
    )
    THEN 
        RAISE EXCEPTION 'Operation failed: No id found for customer %', v_customer_id;
    END IF;

    --check if customer loan exiss
    SELECT id, amount 
    INTO v_loan_id, v_loan_amount
    FROM loans
    WHERE customer_id = v_customer_id
    AND status = 'active'
    FOR UPDATE;

    IF NOT FOUND THEN
        -- Halt execution if nothing is found in pending_loans
        RAISE EXCEPTION 'Operation failed: No pending loan found for customer %', v_customer_id;
    END IF;

    IF amount_paid <= 50 THEN
        RAISE EXCEPTION '💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️';
    ELSEIF amount_paid > v_loan_amount THEN
        RAISE EXCEPTION 'brother doing charity no thx';
    END IF;

    SELECT balance INTO user_account_balance
    FROM user_bank_accounts 
    WHERE customer_id = v_customer_id
    AND account_type = p_account_type
    FOR UPDATE;

    IF NOT FOUND
        THEN
            RAISE EXCEPTION 'i coded this on haramball derby (Also ur account doesnt exist)';
    END IF;

    IF amount_paid > user_account_balance
        THEN RAISE EXCEPTION 'user account balance is less than loan amount paid';
    END IF;

    UPDATE loans SET 
    amount = amount - amount_paid
    WHERE id = v_loan_id
    RETURNING amount INTO v_remaining_amount;

    IF v_remaining_amount = 0 THEN
        UPDATE loans
        SET status = 'paid'::e_loan_status
        WHERE id = v_loan_id;

        RAISE NOTICE 'loan has been paid for!';
    END IF;

    UPDATE user_bank_accounts
    SET balance = balance - amount_paid
    WHERE customer_id = v_customer_id
    AND account_type = p_account_type;

    INSERT INTO audit_logs_loans_payment
    (loan_id,
    amount_paid,
    happened_at)
    VALUES
    (
        v_loan_id,
        amount_paid,
        now()
    );

--enforce loan to be 10lac only
END;
$$ LANGUAGE plpgsql;

SET ROLE postgres;