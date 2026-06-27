-- Active: 1776099699305@@127.0.0.1@5432@banking_system
CREATE TABLE IF NOT EXISTS user_auth (
    id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash TEXT,
    branch_registered_in SMALLINT NOT NULL, 
    PRIMARY KEY (id),
    FOREIGN KEY (branch_registered_in) REFERENCES bank_branches(branch_number) ON DELETE CASCADE
);

CREATE TYPE e_user_roles AS ENUM('customer', 'teller', 'admin', 'owner');

CREATE TABLE IF NOT EXISTS user_auth_setup_token (
    id UUID,
    token UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    role e_user_roles NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    FOREIGN KEY (id) REFERENCES user_auth(id) ON DELETE CASCADE
);

select * from user_auth;


CREATE TABLE IF NOT EXISTS user_roles(
    id UUID,
    role e_user_roles,
    PRIMARY KEY (id, role), -- this would mean, one user can have multiple roles
    FOREIGN KEY (id) REFERENCES user_auth(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS user_active_session_roles(
    id UUID UNIQUE,
    role e_user_roles,
    branch_id SMALLINT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL CHECK (expires_at > started_at),
    PRIMARY KEY (id, role),
    FOREIGN KEY (id, role) REFERENCES user_roles(id, role) ON DELETE CASCADE,
    FOREIGN KEY (id, branch_id) REFERENCES user_auth(id, branch_registed_in) ON DELETE CASCADE
);


-- by having a primary key set to id and role, i ensure one can't exist without the other
-- by having that reference a composite primary key, i ensure that it references a tuple that does exist
-- by having a unique on id i ensure that no more than one user can have the same id.

CREATE OR REPLACE FUNCTION no_invalid_time_entering()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.expires_at < now() THEN
        RAISE EXCEPTION 'can not expire in the past';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_no_invalid_time
BEFORE INSERT OR UPDATE ON user_active_session_roles 
FOR EACH ROW EXECUTE FUNCTION no_invalid_time_entering();
CREATE TRIGGER trigger_no_invalid_time
BEFORE INSERT OR UPDATE ON user_auth_setup_token 
FOR EACH ROW EXECUTE FUNCTION no_invalid_time_entering();
