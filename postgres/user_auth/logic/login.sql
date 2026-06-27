CREATE OR REPLACE FUNCTION user_login(
    f_username VARCHAR(50)
)
RETURNS TABLE(
    r_id UUID,
    r_password_hash TEXT
)
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT id, password_hash FROM user_auth WHERE username = f_username
    AND password_hash IS NOT NULL;
END;
$$ LANGUAGE plpgsql;

