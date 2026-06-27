ALTER TABLE user_auth ADD COLUMN branch_registered_in SMALLINT DEFAULT 1 NOT NULL REFERENCES bank_branches(branch_number);
ALTER TABLE user_auth 
ALTER COLUMN branch_registered_in DROP DEFAULT;

ALTER TABLE user_active_session_roles
ADD COLUMN branch_id
SMALLINT DEFAULT 1 NOT NULL REFERENCES bank_branches(branch_number)
ON DELETE CASCADE;

ALTER TABLE user_auth 
ALTER COLUMN branch_registered_in DROP DEFAULT;