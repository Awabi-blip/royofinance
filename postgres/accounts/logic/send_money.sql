-- Active: 1776099699305@@127.0.0.1@5432@banking_system
-- to make it idempotent, I need an idempotent table.
-- store idempotent keys as UUID.
-- it has user_id, function, idemotency key.

select * from user_bank_accounts uba join user_auth ua on ua.id = uba.customer_id;



CREATE OR REPLACE PROCEDURE send_money (
p_sender_account_type      e_account_type,
p_receiver_account_number  UUID,
p_amount                   DECIMAL(9,2),
p_idempotency_key          UUID,
OUT p_response             JSONB
)
SECURITY DEFINER
AS $$
DECLARE
v_sender_balance DECIMAL(19,2);
v_sender_account_number UUID;
v_receiver_id UUID;
v_sender_id UUID;
BEGIN
    
    IF p_amount <= 0 THEN
        RAISE EXCEPTION
            'too little sent at once';
    END IF;

    IF p_amount > 4000000 THEN
        RAISE EXCEPTION 'too much amount sent at once';
    END IF;

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
    
    SELECT  account_number 
    INTO    v_sender_account_number
    FROM    user_bank_accounts
    WHERE   customer_id = v_sender_id
    AND     account_type = p_sender_account_type;

    IF v_sender_account_number = p_receiver_account_number THEN
        RAISE EXCEPTION
            'not possible';
    END IF;

    SELECT        response 
    INTO          p_response
    FROM          idempotent_responses_accounts
    WHERE         customer_id     = v_sender_id
    AND           account_number  = v_sender_account_number
    AND           idempotency_key = p_idempotency_key
    AND           expires_at      > now()
    AND           method_name     = 'send_money'::idempotent_functions;

    IF FOUND THEN
        RETURN;
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
    WHERE customer_id    = v_sender_id 
    AND   account_type   = p_sender_account_type
    AND   account_number = v_sender_account_number
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'no balance added, hence no transactions must take place, fair as all things must be. period.';
    END IF;

    IF v_sender_balance <= 0 OR v_sender_balance < p_amount THEN
        RAISE EXCEPTION 'not enough balance';
    END IF;

    UPDATE user_bank_accounts
    SET balance = balance - p_amount
    WHERE customer_id = v_sender_id
    AND account_number = v_sender_account_number;

    UPDATE user_bank_accounts
    SET balance = balance + p_amount
    WHERE customer_id = v_receiver_id
    AND account_number = p_receiver_account_number;

    -- for a striple like system, the retry should be identical to the first reponse

    p_response := jsonb_build_object(
    'success',
    TRUE,
    'response',
    'SUCCESSFULLY SENT MONEY'
    );

    INSERT INTO idempotent_responses_accounts(
    customer_id, 
    account_number,
    idempotency_key, 
    method_name, 
    response
    )
    VALUES(
    v_sender_id, 
    v_sender_account_number, 
    p_idempotency_key,
    'send_money'::idempotent_functions,
    p_response  
    );

    INSERT INTO send_money_audit_logs (
    sender_account_number,
    receiver_account_number,
    amount
    ) VALUES (
        v_sender_account_number,
        p_receiver_account_number,
        p_amount
    );

END;
$$ LANGUAGE plpgsql;


DROP FUNCTION test_send_money;

CREATE OR REPLACE FUNCTION test_send_money(
f_sender_id                UUID,
f_sender_balance           DECIMAL(19,2),
f_sender_account_type      e_account_type,
f_receiver_account_number  UUID,
f_receiver_balance         DECIMAL(19,2),
f_amount                   DECIMAL(9,2),
f_idempotency_key          UUID DEFAULT gen_random_uuid()
) RETURNS DECIMAL (9,2) 
SECURITY DEFINER AS $$ 
DECLARE
    V_SENDER_BALANCE   DECIMAL(19,4);
    V_RECEIVER_BALANCE DECIMAL(19,4);
    v_response         JSONB;

BEGIN


    UPDATE user_bank_accounts
    SET   balance = f_sender_balance
    WHERE customer_id = f_sender_id
    AND   account_type = f_sender_account_type;
    
    UPDATE user_bank_accounts
    SET    balance = f_receiver_balance
    WHERE  account_number = f_receiver_account_number;


    PERFORM set_config(
        'myapp.user_id',
        f_sender_id::TEXT,
        true
    );

    CALL send_money (
        f_sender_account_type,
        f_receiver_account_number,
        f_amount,
        f_idempotency_key,
        v_response
    );

    SELECT balance
    INTO   V_SENDER_BALANCE 
    FROM   user_bank_accounts
    WHERE  customer_id = f_sender_id
    AND    account_type = f_sender_account_type;


    SELECT balance 
    INTO   V_RECEIVER_BALANCE
    FROM   user_bank_accounts
    WHERE  account_number = f_receiver_account_number;

    RETURN V_RECEIVER_BALANCE;


END;
$$ LANGUAGE plpgsql;


