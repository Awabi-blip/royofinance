CREATE TYPE e_gender AS ENUM ('male', 'female');
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE IF NOT EXISTS user_information(
    id UUID,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    phone_number VARCHAR(20) NOT NULL UNIQUE,
    email CITEXT NOT NULL UNIQUE 
    CHECK (email ~*'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'), --regex for checking email broadly
    CNIC CHAR(13) NOT NULL UNIQUE,
    gender e_gender NOT NULL,
    address TEXT,
    DoB DATE,
    PRIMARY KEY(id),
    FOREIGN KEY(id) REFERENCES user_auth(id) ON DELETE CASCADE
);
--to check or not to check user > 18 years old(TODO if approved)
CREATE OR REPLACE FUNCTION check_user_is_adult(
)
RETURNS TRIGGER AS $$
DECLARE
BEGIN
    
    IF EXTRACT(YEAR FROM AGE(NEW.DoB::DATE)) < 18 THEN
        RAISE EXCEPTION 'user is not an adult';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_user_age 
BEFORE UPDATE OR INSERT 
ON user_information
FOR EACH ROW
EXECUTE FUNCTION check_user_is_adult();
