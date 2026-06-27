ALTER TABLE user_information ENABLE ROW LEVEL SECURITY;
CREATE POLICY users_view_their_own_data
ON user_information 
FOR SELECT TO PUBLIC
USING (
    user_information.customer_id = current_setting('myapp.user_id')::UUID
    AND
    EXISTS (
        SELECT 1 FROM user_active_session_roles AS uasr
        WHERE uasr.id = current_setting('myapp.user_id')::UUID
        AND uasr.expires_at > now()
    ));

--TODO who can insert information, admins only or can users too?
CREATE POLICY users_update_their_own_data
ON user_information
FOR UPDATE TO PUBLIC 
USING (
    user_information.id = current_setting('myapp.user_id')::UUID
    AND
    EXISTS (
        SELECT 1 FROM user_active_session_roles AS uasr
        WHERE uasr.id = current_setting('myapp.user_id')::UUID
        AND uasr.expires_at > now()
    )
);


CREATE POLICY admins_see_all_data
ON user_information
FOR ALL TO PUBLIC
USING(
    EXISTS(
        SELECT 1 FROM user_active_session_roles as uasr
        WHERE uasr.id = current_setting('myapp.user_id')::UUID
        AND uasr.role = 'admin'::e_user_roles
        AND uasr.expires_at > now()
        AND uasr.branch_id = (SELECT branch_registered_in FROM user_auth
        WHERE id = user_information.id)
    )
);
