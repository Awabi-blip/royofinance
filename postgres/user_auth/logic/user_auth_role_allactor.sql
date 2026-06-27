CREATE OR REPLACE FUNCTION allocate_role(
    p_user_id UUID, p_user_role e_user_roles
)
RETURNS INT
SECURITY DEFINER
AS $$
DECLARE
    expiry INT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM user_roles
        WHERE id = p_user_id
        AND role = p_user_role
    ) THEN
        RAISE EXCEPTION 'user_id with this role does not exist';
    END IF;

    IF p_user_role = 'admin'::e_user_roles
        THEN
            expiry = 6;
    ELSEIF p_user_role = 'teller'::e_user_roles
        THEN
            expiry = 8;
    ELSEIF p_user_role = 'customer'::e_user_roles
        THEN
            expiry = 2;
    END IF;

    INSERT INTO user_active_session_roles(id, role, branch_id, started_at, expires_at)
    VALUES (p_user_id, p_user_role, (SELECT branch_registered_in FROM user_auth WHERE id = p_user_id),
    now(), (now() + (INTERVAL '1 hour' * expiry)) )
    ON CONFLICT(id)
    DO UPDATE
    SET 
    role = EXCLUDED.role,
    started_at = now(),
    expires_at = EXCLUDED.expires_at;
    RETURN expiry;

END;
$$ LANGUAGE plpgsql;

CREATE INDEX idx_role_allocator ON user_roles(
    id, role
);

CREATE OR REPLACE FUNCTION grab_active_role(
    f_id UUID
)
RETURNS e_user_roles
SECURITY DEFINER
AS $$
DECLARE
    r_role e_user_roles;
BEGIN
    SELECT role INTO r_role FROM user_active_session_roles
    WHERE id = f_id AND expires_at > now();

    RETURN r_role;
END;
$$ LANGUAGE plpgsql;

