ALTER TABLE user_auth ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_auth_setup_token ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_active_session_roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY admins_see_all_users ON user_auth
FOR SELECT TO PUBLIC 
USING (
  EXISTS(
    SELECT 1 FROM user_active_session_roles AS uasr 
    WHERE uasr.id = current_setting('myapp.user_id')::UUID
    AND uasr.role = 'admin'::e_user_roles
    AND uasr.expires_at > now() 
    AND uasr.branch_id = user_auth.branch_registered_in
  )
);

CREATE POLICY admins_insert_all_users ON user_auth
FOR INSERT TO PUBLIC 
WITH CHECK (
  EXISTS(
    SELECT 1 FROM user_active_session_roles AS uasr 
    WHERE uasr.id = current_setting('myapp.user_id')::UUID
    AND uasr.role = 'admin'::e_user_roles
    AND uasr.expires_at > now() 
    AND uasr.branch_id = user_auth.branch_registered_in
  )
);

create or replace function check_user_auth()
returns trigger as $$
declare
    user_id uuid := current_setting('myapp.user_id')::uuid;
    user_role e_user_roles;
    user_branch_id SMALLINT;
begin

    ----------------------------------------------------
    select role, branch_id
    into user_role, user_branch_id
    from user_active_session_roles
    where id = user_id;

    if not found
        then raise exception 'user is not found';
    end if;

    if user_role = 'owner'::e_user_roles
      then return new;
    end if;
    -----------------------------------------------------

    -----------------------------------------------------
    if new.branch_registered_in != user_branch_id
        then raise exception 
        'can not insert users into other branches';
    end if;

    if new.password is not null 
        then raise exception
        'can not insert passwords for users';
    end if;
    ------------------------------------------------------
  
  return new;
end;
$$ language plpgsql;

CREATE POLICY admins_see_user_roles ON user_roles
FOR SELECT TO PUBLIC 
USING (
  EXISTS(
    SELECT 1 FROM user_active_session_roles AS uasr 
    WHERE uasr.id = current_setting('myapp.user_id')::UUID
    AND uasr.role = 'admin'::e_user_roles
    AND uasr.expires_at > now() 
    AND uasr.branch_id = (SELECT branch_registered_in FROM 
    user_auth WHERE user_auth.id = user_roles.id)
  )
);

CREATE POLICY admins_delete_user_roles ON user_roles
FOR DELETE TO PUBLIC 
USING (
  EXISTS(
    SELECT 1 FROM user_active_session_roles AS uasr 
    WHERE uasr.id = current_setting('myapp.user_id')::UUID
    AND uasr.role = 'admin'::e_user_roles
    AND uasr.expires_at > now() 
    AND uasr.branch_id = (SELECT branch_registered_in FROM 
    user_auth WHERE user_auth.id = user_roles.id)
  )
);

CREATE POLICY users_see_own_roles ON user_roles
FOR SELECT TO PUBLIC USING(
  id = current_setting('myapp.user_id')::UUID
);

CREATE POLICY admins_manage_login_tokens ON user_auth_setup_token
FOR ALL TO PUBLIC 
USING (
  EXISTS(
    SELECT 1 FROM user_active_session_roles AS uasr 
    WHERE uasr.id = current_setting('myapp.user_id')::UUID
    AND uasr.role = 'admin'::e_user_roles
    AND uasr.expires_at > now() 
    AND uasr.branch_id = (SELECT branch_registered_in FROM 
    user_auth WHERE user_auth.id = user_auth_setup_token.id)
  )
);

create or replace function check_user_auth_setup_token()
returns trigger as $$
declare
    user_id uuid := current_setting('myapp.user_id')::uuid;
    user_role e_user_role;
    user_branch_id SMALLINT;
begin

    ----------------------------------------------------
    select role, branch_id
    into user_role, user_branch_id
    from user_active_session_roles
    where id = user_id;

    if not found
        then raise exception 'user is not found';
    end if;
    -----------------------------------------------------

    -----------------------------------------------------
    if new.id IN (select id from user_auth where password 
    is not null)
        then raise exception
            'user already exists';
    end if;
    -----------------------------------------------------
    return new;
end;
$$ language plpgsql;

-- CREATE OR REPLACE FUNCTION 
-- admins_see_user_active_session_roles()
-- RETURNS TABLE(
--   id UUID,
--   role e_user_roles
-- ) SECURITY DEFINER AS $$
-- DECLARE
--   admin_branch_id INT;
-- BEGIN

--   SELECT branch_id INTO admin_branch_id
--   FROM user_active_session_roles AS uasr 
--   WHERE uasr.id = current_setting('myapp.user_id')::UUID
--   AND uasr.role = 'admin'::e_user_roles
--   AND uasr.expires_at > now();

--   IF NOT FOUND THEN RAISE EXCEPTION ''; END IF;

--   RETURN QUERY
--     SELECT uasr.id, uasr.role FROM user_active_session_roles AS uasr
--     WHERE uasr.branch_id = admin_branch_id;
  
-- END;
-- $$ LANGUAGE plpgsql;

DROP FUNCTION admins_see_user_active_session_roles;

-- CREATE OR REPLACE PROCEDURE 
-- admins_revoke_user_current_access(p_user_id UUID)
-- SECURITY DEFINER AS $$
-- DECLARE
--   admin_branch_id INT;
-- BEGIN 

--   IF p_user_id = current_setting('myapp.user_id')::UUID
--     THEN RAISE EXCEPTION '';
--   END IF;

--   SELECT branch_id INTO admin_branch_id
--   FROM user_active_session_roles AS uasr 
--   WHERE uasr.id = current_setting('myapp.user_id')::UUID
--   AND uasr.role = 'admin'::e_user_roles
--   AND uasr.expires_at > now();

--   IF NOT FOUND THEN RAISE EXCEPTION ''; END IF;

--   DELETE FROM user_active_session_roles
--   WHERE user_active_session_roles.id = p_user_id;

-- END;
-- $$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_current_user_role()
RETURNS e_user_roles
LANGUAGE sql
SECURITY DEFINER  -- runs as postgres, bypasses RLS
STABLE
AS $$
    SELECT role FROM user_active_session_roles
    WHERE id = current_setting('myapp.user_id')::UUID
    AND expires_at > now()
$$;

CREATE POLICY read_sessions_teller
ON user_active_session_roles FOR SELECT
TO PUBLIC USING (
    id = current_setting('myapp.user_id')::UUID
    OR get_current_user_role() = 'teller'::e_user_roles
);

CREATE POLICY manage_sessions_data
ON user_active_session_roles FOR ALL
TO PUBLIC USING (
    get_current_user_role() = 'admin'::e_user_roles
);


