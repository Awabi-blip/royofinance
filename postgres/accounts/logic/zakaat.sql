CREATE OR REPLACE PROCEDURE calculate_zakaat(
) 
SECURITY DEFINER AS $$
DECLARE
    v_owner_id UUID;
    v_owner_role e_user_roles;
    v_total_zakaat_collected DECIMAL(18,2);
BEGIN

    v_owner_id := current_setting('myapp.user_id')::UUID; 

    -- use exists for quick admin check
    SELECT role INTO v_owner_role
    FROM user_active_session_roles
    WHERE id = v_owner_id 
    AND role = 'owner'::e_user_roles
    AND expires_at > now();

    IF NOT FOUND
        THEN RAISE EXCEPTION 'owner not found';
    END IF;

    --calculate the zakaat about to be deducted, don't do it after or else thats a problem
    -- because at that point zakaat has already been calculated
    SELECT SUM(balance * 0.025) AS total_zakaat_collected INTO v_total_zakaat_collected
    FROM user_bank_accounts
    WHERE account_type = 'saving'::e_account_type
    AND expires_at > now();

    UPDATE user_bank_accounts 
    SET balance = balance - (balance * 0.025)
    WHERE account_type = 'saving'::e_account_type
    AND expires_at > now();
    

    INSERT INTO zakaat(year, amount, logged_by, logger_role)
    VALUES(
        EXTRACT(YEAR FROM CURRENT_DATE),
        v_total_zakaat_collected,
        v_owner_id,
        v_owner_role::e_user_roles
    );
    
END;
$$ LANGUAGE plpgsql;


CREATE TABLE IF NOT EXISTS zakaat(
    year SMALLINT,
    amount DECIMAL(18,2),
    logged_by UUID,
    logger_role e_user_roles CHECK(logger_role = 'owner'::e_user_roles),
    PRIMARY KEY(year),
    FOREIGN KEY(logged_by, logger_role) REFERENCES user_roles(id,role)
);



