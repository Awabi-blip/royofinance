CREATE OR REPLACE PROCEDURE set_user_password_and_delete_token(
    p_password_hash TEXT, p_username TEXT, p_token UUID
)
SECURITY DEFINER
AS $$
DECLARE
    v_id UUID;
    v_expires_at TIMESTAMPTZ(0);
    v_role e_user_roles;
    v_user_id := current_setting('myapp.user_id');
BEGIN
     -- this lacks security damn.
    
     -- check if user exists
     SELECT u_a.id as id, u_t.expires_at, u_t.role INTO v_id, v_expires_at, v_role
        FROM 
            user_auth as u_a
        JOIN 
            user_auth_setup_token as u_t
        ON 
            u_a.id = u_t.id
    WHERE u_a.username = p_username AND u_a.password_hash IS NULL AND u_t.token = p_token
    FOR UPDATE OF u_a;

    -- if not found then raise exception (targets v_expires_at)
    IF NOT FOUND 
        THEN
            RAISE EXCEPTION '404 User Not Found';
    END IF;

    IF v_user_id != v_id 
        THEN
            RAISE EXCEPTION '404 Logged in user does 
            not have this account';
    END IF;

    -- time check logic, if expired then raise exception
    IF now()::TIMESTAMPTZ(0) > v_expires_at
        THEN
            RAISE EXCEPTION '404 Timeout, Contact bank for re-newel';
    END IF;

    -- ACIDify user password setting and token deletion
    UPDATE user_auth SET password_hash = p_password_hash
    WHERE username = p_username;
    --WHERE id = v_id;
    
    INSERT INTO user_roles(id , role)
    VALUES (v_id, v_role);

    DELETE FROM user_auth_setup_token 
    WHERE id = v_id;
END;
$$ LANGUAGE plpgsql;



select * from user_auth;