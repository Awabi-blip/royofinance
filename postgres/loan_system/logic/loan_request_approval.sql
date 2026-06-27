CREATE OR REPLACE PROCEDURE request_loan(
     p_amount DECIMAL(9,2)
)
SECURITY DEFINER AS $$
DECLARE
    v_customer_id UUID;
    user_bank_account_number UUID;
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

    SELECT account_number INTO user_bank_account_number
        FROM user_bank_accounts
        WHERE customer_id = v_customer_id
        AND account_type = 'active'::e_account_type;
    
    IF NOT FOUND THEN 
        RAISE EXCEPTION 'Operation failed: No bank account found for customer %', v_customer_id;
    END IF;

    IF p_amount > 1000000.00 OR p_amount < 10000.00 THEN
    RAISE EXCEPTION 'loan cant be more than 10lac or less than 10k';
    END IF;

    INSERT INTO pending_loans
    (customer_id,
    customer_role,
    amount,
    event_date,
    account_type,
    bank_account_number
    )
    VALUES (
    v_customer_id,
    'customer',
    p_amount,
    CURRENT_DATE,
    'active',
    user_bank_account_number
    );

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE approve_loan(
    p_customer_id UUID
)
SECURITY DEFINER 
AS $$
DECLARE
    -- Variable declarations
    v_approver_id UUID;
    v_approver_role e_user_roles;
    v_loan_amount DECIMAL(9,2);
    v_customer_bank_account_number UUID;
BEGIN
    -- 1. Validate session, role, and branch matching
    SELECT uasr.id, uasr.role
    INTO v_approver_id, v_approver_role
    FROM user_active_session_roles AS uasr
    WHERE uasr.id = current_setting('myapp.user_id')::UUID
      AND uasr.role IN ('teller'::e_user_roles, 'admin'::e_user_roles)
      AND uasr.branch_id = (
          SELECT branch_id 
          FROM user_auth 
          WHERE id = p_customer_id
      )
      AND uasr.expires_at > now();

    -- Check if the user meets the authorization criteria
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unauthorized: Invalid session, insufficient privileges, or branch mismatch.';
    END IF;

    -- 2. Verify pending loan exists (Guard Clause)
    SELECT amount 
    INTO v_loan_amount
    FROM pending_loans
    WHERE customer_id = p_customer_id;
    
    IF NOT FOUND THEN
        -- Halt execution if nothing is found in pending_loans
        RAISE EXCEPTION 'Operation failed: No pending loan found for customer %', p_customer_id;
    END IF;

    SELECT account_number INTO v_customer_bank_account_number
    FROM user_bank_accounts
    WHERE customer_id = p_customer_id
    AND account_type = 'active'::e_account_type;

    IF NOT FOUND THEN
        -- Halt execution if nothing is found in pending_loans
        RAISE EXCEPTION 'Operation failed: No active account found for customer %', p_customer_id;
    END IF;

    -- 3. Insert into loans (This only runs if the exception above wasn't raised)
    INSERT INTO loans (
        customer_id, 
        customer_role, 
        amount, 
        status, 
        bank_account_number, 
        account_type, 
        approved_by, 
        approver_role
    )
    VALUES (
        p_customer_id, 
        'customer'::e_user_roles,
        v_loan_amount, 
        'active'::e_loan_status, 
        v_customer_bank_account_number,
        'active'::e_account_type,
        v_approver_id, 
        v_approver_role
    );

    UPDATE user_bank_accounts 
    SET balance = balance + v_loan_amount
    WHERE customer_id = p_customer_id
    AND account_number = v_customer_bank_account_number
    AND account_type = 'active'::e_account_type;

    -- 4. Clean up the pending_loans table
    DELETE FROM pending_loans WHERE customer_id = p_customer_id;
END;
$$ LANGUAGE plpgsql;

CALL approve_loan('b13ab668-31ac-4c14-87a8-7b1efc500f36'::UUID);

SET ROLE testuser;

SET myapp.user_id = 'a0fabb0b-550b-491d-8bc6-9840c2811230';
