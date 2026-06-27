--
-- PostgreSQL database dump
--

\restrict Mwrtj3Wh6kYlXINe7AIb9NoZRMIRZjW8vDvyuLGWHXBk3yqZP4cSXHCW6ZSrWhF

-- Dumped from database version 18.3
-- Dumped by pg_dump version 18.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: e_account_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.e_account_type AS ENUM (
    'active',
    'saving'
);


ALTER TYPE public.e_account_type OWNER TO postgres;

--
-- Name: e_action_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.e_action_type AS ENUM (
    'withdraw',
    'deposit'
);


ALTER TYPE public.e_action_type OWNER TO postgres;

--
-- Name: e_branch_size; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.e_branch_size AS ENUM (
    'enterprise',
    'new',
    'medium'
);


ALTER TYPE public.e_branch_size OWNER TO postgres;

--
-- Name: e_gender; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.e_gender AS ENUM (
    'male',
    'female'
);


ALTER TYPE public.e_gender OWNER TO postgres;

--
-- Name: e_loan_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.e_loan_status AS ENUM (
    'active',
    'paid'
);


ALTER TYPE public.e_loan_status OWNER TO postgres;

--
-- Name: e_user_roles; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.e_user_roles AS ENUM (
    'customer',
    'teller',
    'admin',
    'owner'
);


ALTER TYPE public.e_user_roles OWNER TO postgres;

--
-- Name: allocate_role(uuid, public.e_user_roles); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.allocate_role(p_user_id uuid, p_user_role public.e_user_roles) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
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
$$;


ALTER FUNCTION public.allocate_role(p_user_id uuid, p_user_role public.e_user_roles) OWNER TO postgres;

--
-- Name: approve_loan(uuid); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.approve_loan(IN p_customer_id uuid)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    -- Variable declarations
    v_approver_id UUID;
    v_approver_role e_user_roles;
    v_loan_amount DECIMAL(9,2);
    v_customer_bank_account_number UUID;
BEGIN
    -- 1. Validate session, role, and branch matching
    SELECT uasr.id, uasr.role
    INTO v_approver_id, v_approver_role
    FROM user_active_session_roles AS uasr
    WHERE uasr.id = current_setting('myapp.user_id')::UUID
      AND uasr.role IN ('teller'::e_user_roles, 'admin'::e_user_roles)
      AND uasr.branch_id = (
          SELECT branch_id 
          FROM user_auth 
          WHERE id = p_customer_id
      )
      AND uasr.expires_at > now();

    -- Check if the user meets the authorization criteria
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unauthorized: Invalid session, insufficient privileges, or branch mismatch.';
    END IF;

    -- 2. Verify pending loan exists (Guard Clause)
    SELECT amount 
    INTO v_loan_amount
    FROM pending_loans
    WHERE customer_id = p_customer_id;
    
    IF NOT FOUND THEN
        -- Halt execution if nothing is found in pending_loans
        RAISE EXCEPTION 'Operation failed: No pending loan found for customer %', p_customer_id;
    END IF;

    SELECT account_number INTO v_customer_bank_account_number
    FROM user_bank_accounts
    WHERE customer_id = p_customer_id
    AND account_type = 'active'::e_account_type;

    IF NOT FOUND THEN
        -- Halt execution if nothing is found in pending_loans
        RAISE EXCEPTION 'Operation failed: No active account found for customer %', p_customer_id;
    END IF;

    -- 3. Insert into loans (This only runs if the exception above wasn't raised)
    INSERT INTO loans (
        customer_id, 
        customer_role, 
        amount, 
        status, 
        bank_account_number, 
        account_type, 
        approved_by, 
        approver_role
    )
    VALUES (
        p_customer_id, 
        'customer'::e_user_roles,
        v_loan_amount, 
        'active'::e_loan_status, 
        v_customer_bank_account_number,
        'active'::e_account_type,
        v_approver_id, 
        v_approver_role
    );

    UPDATE user_bank_accounts 
    SET balance = balance + v_loan_amount
    WHERE customer_id = p_customer_id
    AND account_number = v_customer_bank_account_number
    AND account_type = 'active'::e_account_type;

    -- 4. Clean up the pending_loans table
    DELETE FROM pending_loans WHERE customer_id = p_customer_id;
END;
$$;


ALTER PROCEDURE public.approve_loan(IN p_customer_id uuid) OWNER TO postgres;

--
-- Name: calcualte_zakaat(); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.calcualte_zakaat()
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
    AND branch_id = v_customer_branch_id
    AND expires_at > now();

    IF NOT FOUND
        THEN RAISE EXCEPTION 'owner not found';
    END IF;

    UPDATE user_bank_accounts 
    SET balance = balance - (balance * 0.025)
    WHERE account_type = 'saving'::e_account_typee_account_type
    AND expires_at > now();
    
    SELECT SUM(balance * 0.025) AS total_zakaat_collected INTO v_total_zakaat_collected
    FROM user_bank_accounts;

    INSERT INTO zakaat(year, amount, logged_by, logger_role)
    VALUES(
        EXTRACT(YEAR FROM CURRENT_DATE),
        total_zakaat_collected,
        owner_id,
        owner_role::e_user_roles
    );
    
END;
$$;


ALTER PROCEDURE public.calcualte_zakaat() OWNER TO postgres;

--
-- Name: calculate_zakaat(); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.calculate_zakaat()
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


ALTER PROCEDURE public.calculate_zakaat() OWNER TO postgres;

--
-- Name: check_no_new_accounts_with_invalid_expiries(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_no_new_accounts_with_invalid_expiries() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
    
    IF NEW.expires_at < CURRENT_DATE THEN
        RAISE EXCEPTION 'expiry date set in past';
    END IF;

        -- returns days, can use directly, without conversion
    IF (NEW.expires_at - NEW.date_created) > 731 THEN
        RAISE EXCEPTION 'adhere to the rule, expires in more than 6 months or less than 2 years';
    END IF;

    IF (NEW.expires_at - NEW.date_created) < 183 THEN
        RAISE EXCEPTION 'adhere to the rule, expires in more than 6 months or less than 2 years';
    END IF;

    RETURN NEW;

END;
$$;


ALTER FUNCTION public.check_no_new_accounts_with_invalid_expiries() OWNER TO postgres;

--
-- Name: check_user_is_adult(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_user_is_adult() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
    
    IF EXTRACT(YEAR FROM AGE(NEW.DoB::DATE)) < 18 THEN
        RAISE EXCEPTION 'user is not an adult';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_user_is_adult() OWNER TO postgres;

--
-- Name: check_valid_minimum_balance_for_saving_accounts(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_valid_minimum_balance_for_saving_accounts() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN

    IF NEW.account_type = 'saving'::e_account_type
        AND NEW.balance < 1000
    THEN
        RAISE NOTICE 'money in saving account cant be less than 1000 for account_number %s', NEW.account_number;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_valid_minimum_balance_for_saving_accounts() OWNER TO postgres;

--
-- Name: deposit_money(uuid, uuid, numeric, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.deposit_money(IN p_account_number uuid, IN p_customer_id uuid, IN p_deposit_amount numeric, IN p_happened_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_depositer_id UUID;
    v_customer_branch_id SMALLINT;
    v_account_type e_account_type;
    v_user_balance DECIMAL(18,2);
    v_staff_id UUID;
    v_staff_role e_user_roles;
BEGIN

    IF p_deposit_amount > 4000000 THEN
        RAISE EXCEPTION 'deposit amount is greater than bank allowed limit (i hope youre not smuggling drugs)';
    END IF;

    IF p_deposit_amount < 50 THEN
        RAISE EXCEPTION 'beta ye piggy bank nahi real bank hai';
    END IF;

    SELECT branch_registered_in INTO v_customer_branch_id
    FROM user_auth WHERE id = p_customer_id;
    
    v_depositer_id := current_setting('myapp.user_id')::UUID; 

    IF v_depositer_id IS NULL THEN
        RAISE EXCEPTION 'id is empty';
    END IF;

    -- use exists for quick admin check
    SELECT role INTO v_staff_role
    FROM user_active_session_roles
    WHERE id = v_depositer_id AND role IN ('admin', 'teller')
    AND branch_id = v_customer_branch_id
    AND expires_at > now();

    -- activated by v_staff_id, v_staff_role yeah
    IF NOT FOUND THEN
        RAISE EXCEPTION 'staff not found or unauthorized';
    END IF;
    
    -- LOCK the row while depositing money
    SELECT balance 
    INTO v_user_balance
    FROM user_bank_accounts 
    WHERE customer_id = p_customer_id
    AND account_number = p_account_number
    AND expires_at > now()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'customer account not found';
    END IF;

    -- give them all money under emergency lol (BABY GURL U SO DAMN FINE THO 2015 was so nostalgic)
    
    UPDATE user_bank_accounts
    SET balance = balance + p_deposit_amount
    WHERE customer_id = p_customer_id
    AND account_number = p_account_number;

    IF p_happened_at IS NULL THEN
        p_happened_at := now();
    END IF;

    INSERT INTO deposit_withdraw_audit_logs(
        account_number,
        action_type,
        amount,
        happened_at,
        done_by,
        doer_role
    ) VALUES (
        p_account_number,
        'deposit'::e_action_type,
        p_deposit_amount,
        p_happened_at,
        v_depositer_id,
        v_staff_role
    );

END;
$$;


ALTER PROCEDURE public.deposit_money(IN p_account_number uuid, IN p_customer_id uuid, IN p_deposit_amount numeric, IN p_happened_at timestamp with time zone) OWNER TO postgres;

--
-- Name: get_current_user_role(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_current_user_role() RETURNS public.e_user_roles
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
    SELECT role FROM user_active_session_roles
    WHERE id = current_setting('myapp.user_id')::UUID
    AND expires_at > now()
$$;


ALTER FUNCTION public.get_current_user_role() OWNER TO postgres;

--
-- Name: grab_active_role(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.grab_active_role(f_id uuid) RETURNS public.e_user_roles
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    r_role e_user_roles;
BEGIN
    SELECT role INTO r_role FROM user_active_session_roles
    WHERE id = f_id AND expires_at > now();

    RETURN r_role;
END;
$$;


ALTER FUNCTION public.grab_active_role(f_id uuid) OWNER TO postgres;

--
-- Name: no_invalid_time_entering(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.no_invalid_time_entering() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.expires_at < now() THEN
        RAISE EXCEPTION 'can not expire in the past';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.no_invalid_time_entering() OWNER TO postgres;

--
-- Name: pay_for_loan(numeric); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.pay_for_loan(IN amount_paid numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_customer_id UUID;
    v_loan_amount DECIMAL(9,2);
    v_loan_id INT;

BEGIN
    v_customer_id := current_setting('myapp.user_id')::UUID;

    IF NOT EXISTS 
    (
        SELECT 1
        FROM user_active_session_roles AS uasr
        WHERE uasr.id = v_customer_id
        AND uasr.role = 'customer'::e_user_roles
        AND uasr.expires_at > now()
    )
    THEN 
        RAISE EXCEPTION 'Operation failed: No id found for customer %', v_customer_id;
    END IF;

    --check if customer loan exiss
    SELECT id, amount 
    INTO v_loan_id, v_loan_amount
    FROM loans
    WHERE customer_id = v_customer_id
    AND status = 'active';

    IF NOT FOUND THEN
        -- Halt execution if nothing is found in pending_loans
        RAISE EXCEPTION 'Operation failed: No pending loan found for customer %', v_customer_id;
    END IF;

    IF amount_paid <= 50 THEN
        RAISE EXCEPTION '💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️';
    ELSEIF amount_paid > v_loan_amount THEN
        RAISE EXCEPTION 'brother doing charity no thx';
    END IF;

    UPDATE loans SET 
    amount = amount - amount_paid
    WHERE id = v_loan_id;

    INSERT INTO audit_logs_loans_payment
    (loan_id,
    amount_paid,
    happened_at)
    VALUES
    (
        v_loan_id,
        amount_paid,
        now()
    );

--enforce loan to be 10lac only
END;
$$;


ALTER PROCEDURE public.pay_for_loan(IN amount_paid numeric) OWNER TO postgres;

--
-- Name: pay_for_loan(numeric, public.e_account_type); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.pay_for_loan(IN amount_paid numeric, IN p_account_type public.e_account_type)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_customer_id UUID;
    v_loan_amount DECIMAL(9,2);
    v_loan_id INT;
    user_account_balance DECIMAL(19,2);
    v_remaining_amount DECIMAL(9,2);

BEGIN
    v_customer_id := current_setting('myapp.user_id')::UUID;

    IF NOT EXISTS 
    (
        SELECT 1
        FROM user_active_session_roles AS uasr
        WHERE uasr.id = v_customer_id
        AND uasr.role = 'customer'::e_user_roles
        AND uasr.expires_at > now()
    )
    THEN 
        RAISE EXCEPTION 'Operation failed: No id found for customer %', v_customer_id;
    END IF;

    --check if customer loan exiss
    SELECT id, amount 
    INTO v_loan_id, v_loan_amount
    FROM loans
    WHERE customer_id = v_customer_id
    AND status = 'active'
    FOR UPDATE;

    IF NOT FOUND THEN
        -- Halt execution if nothing is found in pending_loans
        RAISE EXCEPTION 'Operation failed: No pending loan found for customer %', v_customer_id;
    END IF;

    IF amount_paid <= 50 THEN
        RAISE EXCEPTION '💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️💀☠️';
    ELSEIF amount_paid > v_loan_amount THEN
        RAISE EXCEPTION 'brother doing charity no thx';
    END IF;

    SELECT balance INTO user_account_balance
    FROM user_bank_accounts 
    WHERE customer_id = v_customer_id
    AND account_type = p_account_type
    FOR UPDATE;

    IF NOT FOUND
        THEN
            RAISE EXCEPTION 'i coded this on haramball derby (Also ur account doesnt exist)';
    END IF;

    IF amount_paid > user_account_balance
        THEN RAISE EXCEPTION 'user account balance is less than loan amount paid';
    END IF;

    UPDATE loans SET 
    amount = amount - amount_paid
    WHERE id = v_loan_id
    RETURNING amount INTO v_remaining_amount;

    IF v_remaining_amount = 0 THEN
        UPDATE loans
        SET status = 'paid'::e_loan_status
        WHERE id = v_loan_id;

        RAISE NOTICE 'loan has been paid for!';
    END IF;

    UPDATE user_bank_accounts
    SET balance = balance - amount_paid
    WHERE customer_id = v_customer_id
    AND account_type = p_account_type;

    INSERT INTO audit_logs_loans_payment
    (loan_id,
    amount_paid,
    happened_at)
    VALUES
    (
        v_loan_id,
        amount_paid,
        now()
    );

--enforce loan to be 10lac only
END;
$$;


ALTER PROCEDURE public.pay_for_loan(IN amount_paid numeric, IN p_account_type public.e_account_type) OWNER TO postgres;

--
-- Name: prevent_invalid_approval_date(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.prevent_invalid_approval_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if the new date_approved is strictly in the past
    IF NEW.event_date != CURRENT_DATE THEN
        RAISE EXCEPTION 'The event_date (%) cannot be in the past or future. Current date is %.', NEW.event_date, CURRENT_DATE;
    END IF;
    -- If the check passes, proceed with the insert/update
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.prevent_invalid_approval_date() OWNER TO postgres;

--
-- Name: request_loan(numeric); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.request_loan(IN p_amount numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_customer_id UUID;
    user_bank_account_number UUID;
BEGIN

    v_customer_id := current_setting('myapp.user_id')::UUID;

    IF NOT EXISTS 
    (
        SELECT 1
        FROM user_active_session_roles AS uasr
        WHERE uasr.id = v_customer_id
        AND uasr.role = 'customer'::e_user_roles
        AND uasr.expires_at > now()
    )
    THEN 
        RAISE EXCEPTION 'Operation failed: No id found for customer %', v_customer_id;
    END IF;

    SELECT account_number INTO user_bank_account_number
        FROM user_bank_accounts
        WHERE customer_id = v_customer_id
        AND account_type = 'active'::e_account_type;
    
    IF NOT FOUND THEN 
        RAISE EXCEPTION 'Operation failed: No bank account found for customer %', v_customer_id;
    END IF;

    IF p_amount > 1000000.00 OR p_amount < 10000.00 THEN
    RAISE EXCEPTION 'loan cant be more than 10lac or less than 10k';
    END IF;

    INSERT INTO pending_loans
    (customer_id,
    customer_role,
    amount,
    event_date,
    account_type,
    bank_account_number
    )
    VALUES (
    v_customer_id,
    'customer',
    p_amount,
    CURRENT_DATE,
    'active',
    user_bank_account_number
    );

END;
$$;


ALTER PROCEDURE public.request_loan(IN p_amount numeric) OWNER TO postgres;

--
-- Name: request_loan(uuid, numeric); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.request_loan(IN p_customer_id uuid, IN p_balance numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
BEGIN

    IF p_balance > 1000000.00 THEN
    RAISE EXCEPTION 'loan cant be more than 10lac';
    END IF;

    INSERT INTO pending_loans
    VALUES (
    p_customer_id,
    p_balance,
    CURRENT_DATE
    );

END;
$$;


ALTER PROCEDURE public.request_loan(IN p_customer_id uuid, IN p_balance numeric) OWNER TO postgres;

--
-- Name: send_money(uuid, uuid, numeric); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.send_money(IN p_sender_account_number uuid, IN p_receiver_account_number uuid, IN p_amount numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
v_sender_balance DECIMAL(19,2);
v_receiver_id UUID;
v_sender_id UUID;
BEGIN
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

    IF p_amount <= 0 THEN
        RAISE EXCEPTION
            'not possible';
    END IF;

    IF p_amount > 4000000 THEN
        RAISE EXCEPTION '';
    END IF;

    SELECT customer_id
    INTO v_receiver_id
    FROM user_bank_accounts
    WHERE account_number = p_receiver_account_number;

    IF v_sender_id = v_receiver_id THEN
        RAISE EXCEPTION
            'not possible';
    END IF;

    IF p_sender_account_number = p_receiver_account_number THEN
        RAISE EXCEPTION
            'not possible';
    END IF;

    PERFORM 1 FROM user_bank_accounts 
    WHERE customer_id IN (v_sender_id, v_receiver_id) 
    ORDER BY (customer_id) FOR UPDATE;
    
    SELECT balance INTO v_sender_balance
    FROM user_bank_accounts
    WHERE customer_id = v_sender_id 
    AND account_number = p_sender_account_number
    FOR UPDATE;

    IF v_sender_balance IS NULL THEN
        RAISE EXCEPTION 'no balance added, hence no transactions must take place, fair as all things must be. period.';
    END IF;

    IF v_sender_balance <= 0 OR v_sender_balance < p_amount THEN
        RAISE EXCEPTION 'not enough balance';
    END IF;

    UPDATE user_bank_accounts
    SET balance = balance - p_amount
    WHERE customer_id = v_sender_id
    AND account_number = p_sender_account_number;

    UPDATE user_bank_accounts
    SET balance = balance + p_amount
    WHERE customer_id = v_receiver_id
    AND account_number = p_receiver_account_number;

    INSERT INTO send_money_audit_logs (
    sender_account_number,
    receiver_account_number,
    amount
    ) VALUES (
        p_sender_account_number,
        p_receiver_account_number,
        p_amount
    );

END;
$$;


ALTER PROCEDURE public.send_money(IN p_sender_account_number uuid, IN p_receiver_account_number uuid, IN p_amount numeric) OWNER TO postgres;

--
-- Name: set_user_password_and_delete_token(text, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.set_user_password_and_delete_token(IN p_password_hash text, IN p_username text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE user_auth SET password_hash = p_password_hash
    WHERE username = p_username;

    DELETE FROM user_auth_setup_token 
    WHERE id = (SELECT id FROM user_auth where username = p_username);
END;
$$;


ALTER PROCEDURE public.set_user_password_and_delete_token(IN p_password_hash text, IN p_username text) OWNER TO postgres;

--
-- Name: set_user_password_and_delete_token(text, text, uuid); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.set_user_password_and_delete_token(IN p_password_hash text, IN p_username text, IN p_token uuid)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_id UUID;
    v_expires_at TIMESTAMPTZ(0);
    v_role e_user_roles;
BEGIN

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
$$;


ALTER PROCEDURE public.set_user_password_and_delete_token(IN p_password_hash text, IN p_username text, IN p_token uuid) OWNER TO postgres;

--
-- Name: user_login(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.user_login() RETURNS TABLE(id uuid, password_hash text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
BEGIN
    RETURN QUERY
    SELECT id, password_hash FROM user_auth WHERE username = $1
    AND password_hash IS NOT NULL;
END;
$_$;


ALTER FUNCTION public.user_login() OWNER TO postgres;

--
-- Name: user_login(character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.user_login(f_username character varying) RETURNS TABLE(r_id uuid, r_password_hash text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT id, password_hash FROM user_auth WHERE username = f_username
    AND password_hash IS NOT NULL;
END;
$$;


ALTER FUNCTION public.user_login(f_username character varying) OWNER TO postgres;

--
-- Name: withdraw_money(uuid, uuid, numeric, boolean, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.withdraw_money(IN p_account_number uuid, IN p_customer_id uuid, IN p_withdraw_amount numeric, IN p_emergency boolean, IN p_happened_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_withdrawer_id UUID;
    v_customer_branch_id SMALLINT;
    v_account_type e_account_type;
    v_user_balance DECIMAL(18,2);
    v_staff_id UUID;
    v_staff_role e_user_roles;
BEGIN

    IF p_withdraw_amount > 4000000 THEN
        RAISE EXCEPTION 'with draw amount is greater than bank allowed limit (i hope youre not smuggling drugs)';
    END IF;

    IF p_withdraw_amount < 50 THEN
        RAISE EXCEPTION 'bhai kurkure khane hain to mere se lelo pese itne kam kyu withdraw krne';
    END IF;

    SELECT branch_registered_in INTO v_customer_branch_id
    FROM user_auth WHERE id = p_customer_id;
    
    v_withdrawer_id := current_setting('myapp.user_id')::UUID; 

    IF v_withdrawer_id IS NULL THEN
        RAISE EXCEPTION 'id is empty';
    END IF;

    -- use exists for quick admin check
    SELECT role INTO v_staff_role
    FROM user_active_session_roles
    WHERE id = v_withdrawer_id AND role IN ('admin', 'teller', 'owner')
    AND branch_id = v_customer_branch_id
    AND expires_at > now();

    -- activated by v_staff_id, v_staff_role yeah
    IF NOT FOUND THEN
        RAISE EXCEPTION 'staff not found or unauthorized';
    END IF;
    
    -- LOCK the row while withdrawing money
    SELECT balance 
    INTO v_user_balance
    FROM user_bank_accounts 
    WHERE customer_id = p_customer_id
    AND account_number = p_account_number
    AND expires_at > now()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'customer account not found';
    END IF;

    IF v_user_balance = 0 THEN
        RAISE EXCEPTION 'your account has no balance';
    END IF;

    -- give them all money under emergency lol (BABY GURL U SO DAMN FINE THO 2015 was so nostalgic)
    IF p_withdraw_amount > v_user_balance THEN
        
        IF p_emergency = TRUE THEN
            RAISE NOTICE 'withdrawing %s amount, emergency: active, amount balance lesser than withdraw amount', v_user_balance;
            UPDATE user_bank_accounts
            SET balance = balance - balance
            WHERE customer_id = p_customer_id
            AND account_number = p_account_number;

            p_withdraw_amount = v_user_balance;
        
        ELSE 
            RAISE EXCEPTION 'benjamins all in my pocket broke ahh cant withdraw that';
    
        END IF;
    
    ELSEIF p_withdraw_amount <= v_user_balance THEN
        UPDATE user_bank_accounts
        SET balance = balance - p_withdraw_amount
        WHERE customer_id = p_customer_id
        AND account_number = p_account_number;

    END IF;
    

    IF p_happened_at IS NULL THEN
        p_happened_at := now();
    END IF;

    INSERT INTO deposit_withdraw_audit_logs(
        account_number,
        action_type,
        amount,
        happened_at,
        done_by,
        doer_role
    ) VALUES (
        p_account_number,
        'withdraw'::e_action_type,
        p_withdraw_amount,
        p_happened_at,
        v_withdrawer_id,
        v_staff_role
    );

END;
$$;


ALTER PROCEDURE public.withdraw_money(IN p_account_number uuid, IN p_customer_id uuid, IN p_withdraw_amount numeric, IN p_emergency boolean, IN p_happened_at timestamp with time zone) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_logs_loans_payment; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audit_logs_loans_payment (
    log_id integer NOT NULL,
    loan_id integer NOT NULL,
    amount_paid numeric(9,2) NOT NULL,
    happened_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.audit_logs_loans_payment OWNER TO postgres;

--
-- Name: audit_logs_loans_payment_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.audit_logs_loans_payment_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.audit_logs_loans_payment_log_id_seq OWNER TO postgres;

--
-- Name: audit_logs_loans_payment_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.audit_logs_loans_payment_log_id_seq OWNED BY public.audit_logs_loans_payment.log_id;


--
-- Name: bank_branches; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bank_branches (
    branch_number smallint NOT NULL,
    city smallint NOT NULL,
    branch_size public.e_branch_size NOT NULL
);


ALTER TABLE public.bank_branches OWNER TO postgres;

--
-- Name: bank_branches_branch_number_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.bank_branches_branch_number_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bank_branches_branch_number_seq OWNER TO postgres;

--
-- Name: bank_branches_branch_number_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.bank_branches_branch_number_seq OWNED BY public.bank_branches.branch_number;


--
-- Name: cities; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cities (
    id smallint NOT NULL,
    name text
);


ALTER TABLE public.cities OWNER TO postgres;

--
-- Name: cities_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.cities_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cities_id_seq OWNER TO postgres;

--
-- Name: cities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.cities_id_seq OWNED BY public.cities.id;


--
-- Name: deposit_withdraw_audit_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.deposit_withdraw_audit_logs (
    log_id bigint NOT NULL,
    account_number uuid NOT NULL,
    action_type public.e_action_type NOT NULL,
    amount numeric(9,2) NOT NULL,
    happened_at timestamp with time zone DEFAULT now() NOT NULL,
    done_by uuid NOT NULL,
    doer_role public.e_user_roles NOT NULL,
    CONSTRAINT deposit_withdraw_audit_logs_doer_role_check CHECK ((doer_role = ANY (ARRAY['teller'::public.e_user_roles, 'admin'::public.e_user_roles, 'owner'::public.e_user_roles])))
);


ALTER TABLE public.deposit_withdraw_audit_logs OWNER TO postgres;

--
-- Name: deposit_withdraw_audit_logs_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.deposit_withdraw_audit_logs_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.deposit_withdraw_audit_logs_log_id_seq OWNER TO postgres;

--
-- Name: deposit_withdraw_audit_logs_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.deposit_withdraw_audit_logs_log_id_seq OWNED BY public.deposit_withdraw_audit_logs.log_id;


--
-- Name: loans; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.loans (
    id integer NOT NULL,
    customer_id uuid NOT NULL,
    customer_role public.e_user_roles NOT NULL,
    amount numeric(9,2) NOT NULL,
    status public.e_loan_status DEFAULT 'active'::public.e_loan_status NOT NULL,
    approved_by uuid NOT NULL,
    approver_role public.e_user_roles NOT NULL,
    event_date date DEFAULT CURRENT_DATE NOT NULL,
    account_type public.e_account_type NOT NULL,
    bank_account_number uuid NOT NULL,
    CONSTRAINT loan_amount_check CHECK (((amount >= (0)::numeric) AND (amount <= (1000000)::numeric))),
    CONSTRAINT loans_customer_role_check CHECK ((customer_role = 'customer'::public.e_user_roles))
);


ALTER TABLE public.loans OWNER TO postgres;

--
-- Name: loan_payments; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.loan_payments WITH (security_invoker='true') AS
 SELECT allp.loan_id,
    allp.amount_paid,
    allp.happened_at AS paid_at,
    l.status AS loan_status
   FROM (public.audit_logs_loans_payment allp
     JOIN public.loans l ON ((l.id = allp.loan_id)));


ALTER VIEW public.loan_payments OWNER TO postgres;

--
-- Name: loans_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.loans_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.loans_id_seq OWNER TO postgres;

--
-- Name: loans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.loans_id_seq OWNED BY public.loans.id;


--
-- Name: pending_loans; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pending_loans (
    customer_id uuid NOT NULL,
    customer_role public.e_user_roles NOT NULL,
    amount numeric(9,2) NOT NULL,
    event_date date DEFAULT CURRENT_DATE NOT NULL,
    account_type public.e_account_type NOT NULL,
    bank_account_number uuid NOT NULL,
    CONSTRAINT pending_loan_amount_check CHECK (((amount >= (10000)::numeric) AND (amount <= (1000000)::numeric))),
    CONSTRAINT pending_loans_customer_role_check CHECK ((customer_role = 'customer'::public.e_user_roles))
);


ALTER TABLE public.pending_loans OWNER TO postgres;

--
-- Name: send_money_audit_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.send_money_audit_logs (
    id integer NOT NULL,
    sender_account_number uuid NOT NULL,
    receiver_account_number uuid NOT NULL,
    amount numeric(9,2) NOT NULL,
    happened_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.send_money_audit_logs OWNER TO postgres;

--
-- Name: send_money_audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.send_money_audit_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.send_money_audit_logs_id_seq OWNER TO postgres;

--
-- Name: send_money_audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.send_money_audit_logs_id_seq OWNED BY public.send_money_audit_logs.id;


--
-- Name: staging; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.staging (
    city text,
    lat text,
    lng text,
    country text,
    iso2 text,
    admin_name text,
    capital text,
    population text,
    population_proper text
);


ALTER TABLE public.staging OWNER TO postgres;

--
-- Name: test_balances; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.test_balances (
    id integer NOT NULL,
    name character varying(50),
    balance numeric(10,2)
);


ALTER TABLE public.test_balances OWNER TO postgres;

--
-- Name: test_balances_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.test_balances_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.test_balances_id_seq OWNER TO postgres;

--
-- Name: test_balances_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.test_balances_id_seq OWNED BY public.test_balances.id;


--
-- Name: user_active_session_roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_active_session_roles (
    id uuid NOT NULL,
    role public.e_user_roles NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '02:00:00'::interval) NOT NULL,
    branch_id smallint DEFAULT 1 NOT NULL,
    CONSTRAINT user_active_session_roles_check CHECK ((expires_at > started_at))
);


ALTER TABLE public.user_active_session_roles OWNER TO postgres;

--
-- Name: user_auth; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_auth (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    username character varying(50) NOT NULL,
    password_hash text,
    branch_registered_in smallint NOT NULL
);


ALTER TABLE public.user_auth OWNER TO postgres;

--
-- Name: user_auth_setup_token; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_auth_setup_token (
    id uuid NOT NULL,
    token uuid DEFAULT gen_random_uuid() NOT NULL,
    expires_at timestamp with time zone DEFAULT now() NOT NULL,
    role public.e_user_roles NOT NULL
);


ALTER TABLE public.user_auth_setup_token OWNER TO postgres;

--
-- Name: user_bank_accounts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_bank_accounts (
    customer_id uuid NOT NULL,
    role public.e_user_roles NOT NULL,
    account_type public.e_account_type NOT NULL,
    account_number uuid DEFAULT gen_random_uuid() NOT NULL,
    balance numeric(18,2) NOT NULL,
    date_created date DEFAULT CURRENT_DATE NOT NULL,
    expires_at date NOT NULL,
    CONSTRAINT no_negative_balance CHECK ((balance >= (0)::numeric)),
    CONSTRAINT user_bank_accounts_role_check CHECK ((role = 'customer'::public.e_user_roles))
);


ALTER TABLE public.user_bank_accounts OWNER TO postgres;

--
-- Name: user_information; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_information (
    id uuid NOT NULL,
    first_name character varying(50) NOT NULL,
    last_name character varying(50) NOT NULL,
    phone_number character varying(20) NOT NULL,
    email public.citext NOT NULL,
    cnic character(13) NOT NULL,
    gender public.e_gender NOT NULL,
    address text,
    dob date,
    CONSTRAINT user_information_email_check CHECK ((email OPERATOR(public.~*) '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'::public.citext))
);


ALTER TABLE public.user_information OWNER TO postgres;

--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_roles (
    id uuid NOT NULL,
    role public.e_user_roles NOT NULL
);


ALTER TABLE public.user_roles OWNER TO postgres;

--
-- Name: v_balance; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.v_balance (
    balance numeric(18,2)
);


ALTER TABLE public.v_balance OWNER TO postgres;

--
-- Name: v_sender_balance; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.v_sender_balance (
    balance numeric(18,2)
);


ALTER TABLE public.v_sender_balance OWNER TO postgres;

--
-- Name: zakaat; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.zakaat (
    year smallint NOT NULL,
    amount numeric(18,2),
    logged_by uuid,
    logger_role public.e_user_roles,
    CONSTRAINT zakaat_logger_role_check CHECK ((logger_role = 'owner'::public.e_user_roles))
);


ALTER TABLE public.zakaat OWNER TO postgres;

--
-- Name: zakaat_test; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.zakaat_test (
    id integer NOT NULL,
    amount numeric(18,2)
);


ALTER TABLE public.zakaat_test OWNER TO postgres;

--
-- Name: zakaat_test_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.zakaat_test_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.zakaat_test_id_seq OWNER TO postgres;

--
-- Name: zakaat_test_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.zakaat_test_id_seq OWNED BY public.zakaat_test.id;


--
-- Name: audit_logs_loans_payment log_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs_loans_payment ALTER COLUMN log_id SET DEFAULT nextval('public.audit_logs_loans_payment_log_id_seq'::regclass);


--
-- Name: bank_branches branch_number; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bank_branches ALTER COLUMN branch_number SET DEFAULT nextval('public.bank_branches_branch_number_seq'::regclass);


--
-- Name: cities id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cities ALTER COLUMN id SET DEFAULT nextval('public.cities_id_seq'::regclass);


--
-- Name: deposit_withdraw_audit_logs log_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deposit_withdraw_audit_logs ALTER COLUMN log_id SET DEFAULT nextval('public.deposit_withdraw_audit_logs_log_id_seq'::regclass);


--
-- Name: loans id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.loans ALTER COLUMN id SET DEFAULT nextval('public.loans_id_seq'::regclass);


--
-- Name: send_money_audit_logs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.send_money_audit_logs ALTER COLUMN id SET DEFAULT nextval('public.send_money_audit_logs_id_seq'::regclass);


--
-- Name: test_balances id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.test_balances ALTER COLUMN id SET DEFAULT nextval('public.test_balances_id_seq'::regclass);


--
-- Name: zakaat_test id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.zakaat_test ALTER COLUMN id SET DEFAULT nextval('public.zakaat_test_id_seq'::regclass);


--
-- Data for Name: audit_logs_loans_payment; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.audit_logs_loans_payment (log_id, loan_id, amount_paid, happened_at) FROM stdin;
6	7	5000.00	2026-05-06 15:34:25.930082+05
7	7	5000.00	2026-05-06 15:34:44.708456+05
8	7	5000.00	2026-05-06 15:39:08.69529+05
9	7	5000.00	2026-05-06 15:39:14.343738+05
\.


--
-- Data for Name: bank_branches; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bank_branches (branch_number, city, branch_size) FROM stdin;
1	134	enterprise
\.


--
-- Data for Name: cities; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cities (id, name) FROM stdin;
1	Harunabad
2	Dainyor
3	Abdul Hakim
4	Rajanpur
5	Bagh
6	Nowshera
7	Kasur
8	Dera Bugti
9	Ziarat
10	Shakargarh
11	Gojra
12	Chitral
13	Athmuqam
14	Faisalabad
15	Kulachi
16	Gilgit
17	New Mirpur
18	Mandi Bahauddin
19	Jhang City
20	Quetta
21	Muridke
22	Rahimyar Khan
23	Gujranwala
24	Sanghar
25	Matiari
26	Mansehra
27	Qila Saifullah
28	Jhelum
29	Sialkot City
30	Kundian
31	Thatta
32	Gwadar
33	Sibi
34	Gandava
35	Chakwal
36	Nawabshah
37	Chaman
38	Turbat
39	Lahore
40	Mirpur Khas
41	Dadu
42	Kohat
43	Shahdad Kot
44	Abbottabad
45	Daggar
46	Tando Muhammad Khan
47	Saidu Sharif
48	Hyderabad City
49	Sargodha
50	Toba Tek Singh
51	Hujra Shah Muqim
52	Alpurai
53	Kharan
54	Dera Allahyar
55	Loralai
56	Mingaora
57	Hasilpur
58	Dera Ismail Khan
59	Haripur
60	Khairpur Mir’s
61	Khanpur
62	Hassan Abdal
63	Jaranwala
64	Kharian
65	Lakki
66	Risalpur Cantonment
67	Multan
68	Bannu
69	Peshawar
70	Parachinar
71	Tank
72	Muzaffargarh
73	Mastung
74	Sahiwal
75	Tando Allahyar
76	Sukkur
77	Pattoki
78	Narowal
79	Saddiqabad
80	Okara
81	Jalalpur Jattan
82	Badin
83	Charsadda
84	Kabirwala
85	Kohlu
86	Karak
87	Dasu
88	Attock City
89	Bhakkar
90	Hafizabad
91	Khuzdar
92	Leiah
93	Kamalia
94	Vihari
95	Batgram
96	Pakpattan
97	Lodhran
98	Eidgah
99	Kot Addu
100	Awaran
101	Larkana
102	Gujrat
103	Shekhupura
104	Shikarpur
105	Bahawalnagar
106	Aliabad
107	Barkhan
108	Gakuch
109	Dera Murad Jamali
110	Jacobabad
111	Zhob
112	Ghotki
113	Rawalpindi
114	Umarkot
115	Muzaffarabad
116	Malakand
117	Khanewal
118	Jamshoro
119	Swabi
120	Panjgur
121	Mianwali
122	Mandi Burewala
123	Rawala Kot
124	Pishin
125	Hangu
126	Islamabad
127	Kandhkot
128	Bahawalpur
129	Mian Channun
130	Mardan
131	Uthal
132	Dalbandin
133	Chilas
134	Karachi
135	Naushahro Firoz
136	Nankana Sahib
137	Khushab
138	Chiniot
139	Kotli
140	Dera Ghazi Khan
141	Upper Dir
142	Musa Khel Bazar
143	Lala Musa
144	Kalat
145	Timargara
\.


--
-- Data for Name: deposit_withdraw_audit_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.deposit_withdraw_audit_logs (log_id, account_number, action_type, amount, happened_at, done_by, doer_role) FROM stdin;
1	4bbee994-ebda-49a0-90aa-1c1c267836c2	deposit	5000.00	2026-05-07 05:38:24.04457+05	a0fabb0b-550b-491d-8bc6-9840c2811230	admin
2	4bbee994-ebda-49a0-90aa-1c1c267836c2	withdraw	100.00	2026-05-07 05:48:00.877503+05	a0fabb0b-550b-491d-8bc6-9840c2811230	admin
3	4bbee994-ebda-49a0-90aa-1c1c267836c2	withdraw	100.00	2026-05-07 05:49:42.191916+05	a0fabb0b-550b-491d-8bc6-9840c2811230	admin
4	4bbee994-ebda-49a0-90aa-1c1c267836c2	withdraw	100.00	2026-05-07 05:57:41.67212+05	a0fabb0b-550b-491d-8bc6-9840c2811230	admin
5	4bbee994-ebda-49a0-90aa-1c1c267836c2	withdraw	5500.00	2026-05-07 06:12:01.496666+05	a0fabb0b-550b-491d-8bc6-9840c2811230	admin
6	4bbee994-ebda-49a0-90aa-1c1c267836c2	withdraw	5500.00	2026-05-07 06:16:48.133388+05	a0fabb0b-550b-491d-8bc6-9840c2811230	admin
7	4bbee994-ebda-49a0-90aa-1c1c267836c2	withdraw	4000.00	2026-05-07 06:20:54.291468+05	a0fabb0b-550b-491d-8bc6-9840c2811230	admin
8	4bbee994-ebda-49a0-90aa-1c1c267836c2	withdraw	0.00	2026-05-07 06:25:35.02463+05	a0fabb0b-550b-491d-8bc6-9840c2811230	admin
9	4bbee994-ebda-49a0-90aa-1c1c267836c2	withdraw	0.00	2026-05-07 06:25:45.362082+05	a0fabb0b-550b-491d-8bc6-9840c2811230	admin
10	4bbee994-ebda-49a0-90aa-1c1c267836c2	withdraw	0.00	2026-05-07 06:26:44.839787+05	a0fabb0b-550b-491d-8bc6-9840c2811230	admin
\.


--
-- Data for Name: loans; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.loans (id, customer_id, customer_role, amount, status, approved_by, approver_role, event_date, account_type, bank_account_number) FROM stdin;
7	b13ab668-31ac-4c14-87a8-7b1efc500f36	customer	0.00	paid	a0fabb0b-550b-491d-8bc6-9840c2811230	admin	2026-05-06	active	4bbee994-ebda-49a0-90aa-1c1c267836c2
\.


--
-- Data for Name: pending_loans; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.pending_loans (customer_id, customer_role, amount, event_date, account_type, bank_account_number) FROM stdin;
\.


--
-- Data for Name: send_money_audit_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.send_money_audit_logs (id, sender_account_number, receiver_account_number, amount, happened_at) FROM stdin;
1	650b8f0d-3080-447a-8776-1e24fbf4c110	4bbee994-ebda-49a0-90aa-1c1c267836c2	200.00	2026-05-07 14:03:02.898807
2	650b8f0d-3080-447a-8776-1e24fbf4c110	4bbee994-ebda-49a0-90aa-1c1c267836c2	2000.00	2026-05-07 14:24:52.360361
\.


--
-- Data for Name: staging; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.staging (city, lat, lng, country, iso2, admin_name, capital, population, population_proper) FROM stdin;
\.


--
-- Data for Name: test_balances; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.test_balances (id, name, balance) FROM stdin;
1	Alice	975.49
2	Bob	2437.50
3	Charlie	487.74
4	David	2925.00
\.


--
-- Data for Name: user_active_session_roles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_active_session_roles (id, role, started_at, expires_at, branch_id) FROM stdin;
b13ab668-31ac-4c14-87a8-7b1efc500f36	customer	2026-05-06 15:08:57.591404+05	2026-05-06 17:08:57.591404+05	1
a0fabb0b-550b-491d-8bc6-9840c2811230	customer	2026-05-07 13:32:19.824691+05	2026-05-07 15:32:19.824691+05	1
\.


--
-- Data for Name: user_auth; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_auth (id, username, password_hash, branch_registered_in) FROM stdin;
a0fabb0b-550b-491d-8bc6-9840c2811230	awabi	$argon2id$v=19$m=65536,t=3,p=4$L9oU6oPm/e/hr2iVHiDGOQ$aVqDw/ZohqK4d/8/R/ZhF++d2Ypucgu9CrQuBCErLQ4	1
b13ab668-31ac-4c14-87a8-7b1efc500f36	okay123	$argon2id$v=19$m=65536,t=3,p=4$Z8QgXt1i4hk5HggeN7uzJQ$FesUDjD+WPiil7GCLMWTATjC5OZt+TcTmvqYf21roJk	1
\.


--
-- Data for Name: user_auth_setup_token; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_auth_setup_token (id, token, expires_at, role) FROM stdin;
\.


--
-- Data for Name: user_bank_accounts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_bank_accounts (customer_id, role, account_type, account_number, balance, date_created, expires_at) FROM stdin;
a0fabb0b-550b-491d-8bc6-9840c2811230	customer	saving	650b8f0d-3080-447a-8776-1e24fbf4c110	2800.00	2026-05-07	2027-05-12
b13ab668-31ac-4c14-87a8-7b1efc500f36	customer	active	4bbee994-ebda-49a0-90aa-1c1c267836c2	2200.00	2026-05-06	2027-07-14
\.


--
-- Data for Name: user_information; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_information (id, first_name, last_name, phone_number, email, cnic, gender, address, dob) FROM stdin;
\.


--
-- Data for Name: user_roles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_roles (id, role) FROM stdin;
a0fabb0b-550b-491d-8bc6-9840c2811230	admin
a0fabb0b-550b-491d-8bc6-9840c2811230	customer
b13ab668-31ac-4c14-87a8-7b1efc500f36	customer
\.


--
-- Data for Name: v_balance; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.v_balance (balance) FROM stdin;
5000.00
\.


--
-- Data for Name: v_sender_balance; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.v_sender_balance (balance) FROM stdin;
5000.00
\.


--
-- Data for Name: zakaat; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.zakaat (year, amount, logged_by, logger_role) FROM stdin;
\.


--
-- Data for Name: zakaat_test; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.zakaat_test (id, amount) FROM stdin;
\.


--
-- Name: audit_logs_loans_payment_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.audit_logs_loans_payment_log_id_seq', 9, true);


--
-- Name: bank_branches_branch_number_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.bank_branches_branch_number_seq', 1, true);


--
-- Name: cities_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cities_id_seq', 145, true);


--
-- Name: deposit_withdraw_audit_logs_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.deposit_withdraw_audit_logs_log_id_seq', 10, true);


--
-- Name: loans_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.loans_id_seq', 7, true);


--
-- Name: send_money_audit_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.send_money_audit_logs_id_seq', 2, true);


--
-- Name: test_balances_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.test_balances_id_seq', 4, true);


--
-- Name: zakaat_test_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.zakaat_test_id_seq', 1, false);


--
-- Name: audit_logs_loans_payment audit_logs_loans_payment_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs_loans_payment
    ADD CONSTRAINT audit_logs_loans_payment_pkey PRIMARY KEY (log_id);


--
-- Name: bank_branches bank_branches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bank_branches
    ADD CONSTRAINT bank_branches_pkey PRIMARY KEY (branch_number);


--
-- Name: cities cities_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key UNIQUE (name);


--
-- Name: cities cities_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_pkey PRIMARY KEY (id);


--
-- Name: deposit_withdraw_audit_logs deposit_withdraw_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deposit_withdraw_audit_logs
    ADD CONSTRAINT deposit_withdraw_audit_logs_pkey PRIMARY KEY (log_id);


--
-- Name: loans loans_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.loans
    ADD CONSTRAINT loans_pkey PRIMARY KEY (id);


--
-- Name: pending_loans pending_loans_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pending_loans
    ADD CONSTRAINT pending_loans_pkey PRIMARY KEY (customer_id);


--
-- Name: send_money_audit_logs send_money_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.send_money_audit_logs
    ADD CONSTRAINT send_money_audit_logs_pkey PRIMARY KEY (id);


--
-- Name: test_balances test_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.test_balances
    ADD CONSTRAINT test_balances_pkey PRIMARY KEY (id);


--
-- Name: user_active_session_roles user_active_session_roles_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_active_session_roles
    ADD CONSTRAINT user_active_session_roles_id_key UNIQUE (id);


--
-- Name: user_active_session_roles user_active_session_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_active_session_roles
    ADD CONSTRAINT user_active_session_roles_pkey PRIMARY KEY (id, role);


--
-- Name: user_auth user_auth_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_auth
    ADD CONSTRAINT user_auth_pkey PRIMARY KEY (id);


--
-- Name: user_auth_setup_token user_auth_setup_token_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_auth_setup_token
    ADD CONSTRAINT user_auth_setup_token_pkey PRIMARY KEY (id);


--
-- Name: user_auth_setup_token user_auth_setup_token_token_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_auth_setup_token
    ADD CONSTRAINT user_auth_setup_token_token_key UNIQUE (token);


--
-- Name: user_bank_accounts user_bank_accounts_account_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_bank_accounts
    ADD CONSTRAINT user_bank_accounts_account_number_key UNIQUE (account_number);


--
-- Name: user_bank_accounts user_bank_accounts_account_number_status_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_bank_accounts
    ADD CONSTRAINT user_bank_accounts_account_number_status_key UNIQUE (account_number, account_type);


--
-- Name: user_bank_accounts user_bank_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_bank_accounts
    ADD CONSTRAINT user_bank_accounts_pkey PRIMARY KEY (customer_id, account_type);


--
-- Name: user_information user_information_cnic_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_information
    ADD CONSTRAINT user_information_cnic_key UNIQUE (cnic);


--
-- Name: user_information user_information_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_information
    ADD CONSTRAINT user_information_email_key UNIQUE (email);


--
-- Name: user_information user_information_phone_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_information
    ADD CONSTRAINT user_information_phone_number_key UNIQUE (phone_number);


--
-- Name: user_information user_information_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_information
    ADD CONSTRAINT user_information_pkey PRIMARY KEY (id);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (id, role);


--
-- Name: zakaat zakaat_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.zakaat
    ADD CONSTRAINT zakaat_pkey PRIMARY KEY (year);


--
-- Name: zakaat_test zakaat_test_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.zakaat_test
    ADD CONSTRAINT zakaat_test_pkey PRIMARY KEY (id);


--
-- Name: idx_active_session_customers; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_active_session_customers ON public.user_active_session_roles USING btree (id, expires_at) WHERE (role = 'customer'::public.e_user_roles);


--
-- Name: idx_active_session_staff; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_active_session_staff ON public.user_active_session_roles USING btree (id, role, branch_id, expires_at) WHERE (role = ANY (ARRAY['admin'::public.e_user_roles, 'teller'::public.e_user_roles, 'owner'::public.e_user_roles]));


--
-- Name: idx_fetch_branch_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fetch_branch_id ON public.user_auth USING btree (id, branch_registered_in);


--
-- Name: idx_fetch_loan_amount_for_procedure; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fetch_loan_amount_for_procedure ON public.loans USING btree (customer_id) INCLUDE (id, amount) WHERE (status = 'active'::public.e_loan_status);


--
-- Name: idx_fetch_user_account; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fetch_user_account ON public.user_bank_accounts USING btree (customer_id, account_number, expires_at) INCLUDE (balance);


--
-- Name: idx_loans_rls; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_loans_rls ON public.loans USING btree (id) INCLUDE (customer_id);


--
-- Name: idx_role_allocator; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_role_allocator ON public.user_roles USING btree (id, role);


--
-- Name: idx_staff_see_audit_logs_loans; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_staff_see_audit_logs_loans ON public.audit_logs_loans_payment USING btree (loan_id);


--
-- Name: idx_unique_pending_ongoing_loan; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_unique_pending_ongoing_loan ON public.loans USING btree (customer_id) WHERE (status = 'active'::public.e_loan_status);


--
-- Name: user_auth_username_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX user_auth_username_idx ON public.user_auth USING btree (username);


--
-- Name: loans enforce_valid_approval_date; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_valid_approval_date BEFORE INSERT ON public.loans FOR EACH ROW EXECUTE FUNCTION public.prevent_invalid_approval_date();


--
-- Name: pending_loans enforce_valid_approval_date; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_valid_approval_date BEFORE INSERT OR UPDATE ON public.pending_loans FOR EACH ROW EXECUTE FUNCTION public.prevent_invalid_approval_date();


--
-- Name: user_information trigger_check_user_age; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_check_user_age BEFORE INSERT OR UPDATE ON public.user_information FOR EACH ROW EXECUTE FUNCTION public.check_user_is_adult();


--
-- Name: user_active_session_roles trigger_no_invalid_time; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_no_invalid_time BEFORE INSERT OR UPDATE ON public.user_active_session_roles FOR EACH ROW EXECUTE FUNCTION public.no_invalid_time_entering();


--
-- Name: user_auth_setup_token trigger_no_invalid_time; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_no_invalid_time BEFORE INSERT OR UPDATE ON public.user_auth_setup_token FOR EACH ROW EXECUTE FUNCTION public.no_invalid_time_entering();


--
-- Name: audit_logs_loans_payment audit_logs_loans_payment_loan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs_loans_payment
    ADD CONSTRAINT audit_logs_loans_payment_loan_id_fkey FOREIGN KEY (loan_id) REFERENCES public.loans(id) ON DELETE CASCADE;


--
-- Name: bank_branches bank_branches_city_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bank_branches
    ADD CONSTRAINT bank_branches_city_fkey FOREIGN KEY (city) REFERENCES public.cities(id);


--
-- Name: deposit_withdraw_audit_logs deposit_withdraw_audit_logs_account_number_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deposit_withdraw_audit_logs
    ADD CONSTRAINT deposit_withdraw_audit_logs_account_number_fkey FOREIGN KEY (account_number) REFERENCES public.user_bank_accounts(account_number) ON DELETE CASCADE;


--
-- Name: deposit_withdraw_audit_logs deposit_withdraw_audit_logs_done_by_doer_role_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deposit_withdraw_audit_logs
    ADD CONSTRAINT deposit_withdraw_audit_logs_done_by_doer_role_fkey FOREIGN KEY (done_by, doer_role) REFERENCES public.user_roles(id, role) ON DELETE CASCADE;


--
-- Name: loans loans_account_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.loans
    ADD CONSTRAINT loans_account_type_fkey FOREIGN KEY (account_type, bank_account_number) REFERENCES public.user_bank_accounts(account_type, account_number);


--
-- Name: loans loans_approved_by_approver_role_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.loans
    ADD CONSTRAINT loans_approved_by_approver_role_fkey FOREIGN KEY (approved_by, approver_role) REFERENCES public.user_roles(id, role);


--
-- Name: loans loans_customer_id_customer_role_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.loans
    ADD CONSTRAINT loans_customer_id_customer_role_fkey FOREIGN KEY (customer_id, customer_role) REFERENCES public.user_roles(id, role);


--
-- Name: pending_loans pending_loans_account_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pending_loans
    ADD CONSTRAINT pending_loans_account_type_fkey FOREIGN KEY (account_type, bank_account_number) REFERENCES public.user_bank_accounts(account_type, account_number);


--
-- Name: pending_loans pending_loans_customer_id_customer_role_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pending_loans
    ADD CONSTRAINT pending_loans_customer_id_customer_role_fkey FOREIGN KEY (customer_id, customer_role) REFERENCES public.user_roles(id, role);


--
-- Name: send_money_audit_logs send_money_audit_logs_receiver_account_number_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.send_money_audit_logs
    ADD CONSTRAINT send_money_audit_logs_receiver_account_number_fkey FOREIGN KEY (receiver_account_number) REFERENCES public.user_bank_accounts(account_number);


--
-- Name: send_money_audit_logs send_money_audit_logs_sender_account_number_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.send_money_audit_logs
    ADD CONSTRAINT send_money_audit_logs_sender_account_number_fkey FOREIGN KEY (sender_account_number) REFERENCES public.user_bank_accounts(account_number);


--
-- Name: user_active_session_roles user_active_session_roles_id_role_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_active_session_roles
    ADD CONSTRAINT user_active_session_roles_id_role_fkey FOREIGN KEY (id, role) REFERENCES public.user_roles(id, role) ON DELETE CASCADE;


--
-- Name: user_auth user_auth_branch_registered_in_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_auth
    ADD CONSTRAINT user_auth_branch_registered_in_fkey FOREIGN KEY (branch_registered_in) REFERENCES public.bank_branches(branch_number) ON DELETE CASCADE;


--
-- Name: user_auth_setup_token user_auth_setup_token_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_auth_setup_token
    ADD CONSTRAINT user_auth_setup_token_id_fkey FOREIGN KEY (id) REFERENCES public.user_auth(id) ON DELETE CASCADE;


--
-- Name: user_bank_accounts user_bank_accounts_customer_id_role_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_bank_accounts
    ADD CONSTRAINT user_bank_accounts_customer_id_role_fkey FOREIGN KEY (customer_id, role) REFERENCES public.user_roles(id, role) ON DELETE CASCADE;


--
-- Name: user_information user_information_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_information
    ADD CONSTRAINT user_information_id_fkey FOREIGN KEY (id) REFERENCES public.user_auth(id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_id_fkey FOREIGN KEY (id) REFERENCES public.user_auth(id) ON DELETE CASCADE;


--
-- Name: zakaat zakaat_logged_by_logger_role_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.zakaat
    ADD CONSTRAINT zakaat_logged_by_logger_role_fkey FOREIGN KEY (logged_by, logger_role) REFERENCES public.user_roles(id, role);


--
-- Name: user_auth_setup_token admins_manage_login_tokens; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY admins_manage_login_tokens ON public.user_auth_setup_token USING ((EXISTS ( SELECT 1
   FROM public.user_active_session_roles uasr
  WHERE ((uasr.id = (current_setting('myapp.user_id'::text))::uuid) AND (uasr.role = 'admin'::public.e_user_roles) AND (uasr.expires_at > now()) AND (uasr.branch_id = ( SELECT user_auth.branch_registered_in
           FROM public.user_auth
          WHERE (user_auth.id = user_auth_setup_token.id)))))));


--
-- Name: user_roles admins_manage_user_roles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY admins_manage_user_roles ON public.user_roles FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.user_active_session_roles uasr
  WHERE ((uasr.id = (current_setting('myapp.user_id'::text))::uuid) AND (uasr.role = 'admin'::public.e_user_roles) AND (uasr.expires_at > now()) AND (uasr.branch_id = ( SELECT user_auth.branch_registered_in
           FROM public.user_auth
          WHERE (user_auth.id = user_roles.id)))))));


--
-- Name: user_roles admins_manage_user_roles2; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY admins_manage_user_roles2 ON public.user_roles USING ((EXISTS ( SELECT 1
   FROM public.user_active_session_roles uasr
  WHERE ((uasr.id = (current_setting('myapp.user_id'::text))::uuid) AND (uasr.role = 'admin'::public.e_user_roles) AND (uasr.expires_at > now()) AND (uasr.branch_id = ( SELECT user_auth.branch_registered_in
           FROM public.user_auth
          WHERE (user_auth.id = user_roles.id)))))));


--
-- Name: user_bank_accounts admins_see_all_accounts; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY admins_see_all_accounts ON public.user_bank_accounts FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.user_active_session_roles uasr
  WHERE ((uasr.id = (current_setting('myapp.user_id'::text))::uuid) AND (uasr.role = 'admin'::public.e_user_roles) AND (uasr.expires_at > now()) AND (uasr.branch_id = ( SELECT user_auth.branch_registered_in
           FROM public.user_auth
          WHERE (user_auth.id = user_bank_accounts.customer_id)))))));


--
-- Name: deposit_withdraw_audit_logs admins_see_all_audit_logs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY admins_see_all_audit_logs ON public.deposit_withdraw_audit_logs USING ((EXISTS ( SELECT 1
   FROM public.user_active_session_roles uasr
  WHERE ((uasr.id = (current_setting('myapp.user_id'::text))::uuid) AND (uasr.role = 'admin'::public.e_user_roles) AND (uasr.expires_at > now()) AND (uasr.branch_id = ( SELECT user_auth.branch_registered_in
           FROM public.user_auth
          WHERE (user_auth.id = ( SELECT user_bank_accounts.customer_id
                   FROM public.user_bank_accounts
                  WHERE (user_bank_accounts.account_number = deposit_withdraw_audit_logs.account_number)))))))));


--
-- Name: user_information admins_see_all_data; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY admins_see_all_data ON public.user_information USING ((EXISTS ( SELECT 1
   FROM public.user_active_session_roles uasr
  WHERE ((uasr.id = (current_setting('myapp.user_id'::text))::uuid) AND (uasr.role = 'admin'::public.e_user_roles) AND (uasr.expires_at > now()) AND (uasr.branch_id = ( SELECT user_auth.branch_registered_in
           FROM public.user_auth
          WHERE (user_auth.id = user_information.id)))))));


--
-- Name: user_auth admins_see_all_users; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY admins_see_all_users ON public.user_auth FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.user_active_session_roles uasr
  WHERE ((uasr.id = (current_setting('myapp.user_id'::text))::uuid) AND (uasr.role = 'admin'::public.e_user_roles) AND (uasr.expires_at > now()) AND (uasr.branch_id = user_auth.branch_registered_in)))));


--
-- Name: audit_logs_loans_payment; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.audit_logs_loans_payment ENABLE ROW LEVEL SECURITY;

--
-- Name: user_bank_accounts customers_see_their_accounts; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY customers_see_their_accounts ON public.user_bank_accounts FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.user_active_session_roles uasr
  WHERE ((uasr.id = (current_setting('myapp.user_id'::text))::uuid) AND (uasr.role = 'customer'::public.e_user_roles) AND (user_bank_accounts.customer_id = uasr.id) AND (uasr.expires_at > now())))));


--
-- Name: loans; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.loans ENABLE ROW LEVEL SECURITY;

--
-- Name: user_active_session_roles manage_sessions_data; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY manage_sessions_data ON public.user_active_session_roles USING ((public.get_current_user_role() = 'admin'::public.e_user_roles));


--
-- Name: user_auth_setup_token p4; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY p4 ON public.user_auth_setup_token USING (((id = (current_setting('myapp.user_id'::text))::uuid) AND (EXISTS ( SELECT 1
   FROM public.user_roles
  WHERE ((user_roles.id = (current_setting('myapp.user_id'::text))::uuid) AND (user_roles.role = 'admin'::public.e_user_roles))))));


--
-- Name: user_roles p6; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY p6 ON public.user_roles FOR SELECT USING ((id = (current_setting('myapp.user_id'::text, true))::uuid));


--
-- Name: pending_loans; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.pending_loans ENABLE ROW LEVEL SECURITY;

--
-- Name: user_active_session_roles read_sessions_teller; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY read_sessions_teller ON public.user_active_session_roles FOR SELECT USING (((id = (current_setting('myapp.user_id'::text))::uuid) OR (public.get_current_user_role() = 'teller'::public.e_user_roles)));


--
-- Name: audit_logs_loans_payment staff_see_audit_logs_loans; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY staff_see_audit_logs_loans ON public.audit_logs_loans_payment FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.user_active_session_roles uasr
  WHERE ((uasr.id = (current_setting('myapp.user_id'::text))::uuid) AND (uasr.role = ANY (ARRAY['teller'::public.e_user_roles, 'admin'::public.e_user_roles])) AND (uasr.branch_id = ( SELECT user_auth.branch_registered_in
           FROM public.user_auth
          WHERE (user_auth.id = ( SELECT loans.customer_id
                   FROM public.loans
                  WHERE (loans.id = audit_logs_loans_payment.loan_id))))) AND (uasr.expires_at > now())))));


--
-- Name: loans tenant_loans; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_loans ON public.loans FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.user_active_session_roles uasr
  WHERE ((uasr.id = (current_setting('myapp.user_id'::text))::uuid) AND (uasr.role = ANY (ARRAY['teller'::public.e_user_roles, 'admin'::public.e_user_roles])) AND (uasr.branch_id = ( SELECT user_auth.branch_registered_in
           FROM public.user_auth
          WHERE (user_auth.id = loans.customer_id))) AND (uasr.expires_at > now())))));


--
-- Name: pending_loans tenant_pending_loans; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_pending_loans ON public.pending_loans FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.user_active_session_roles uasr
  WHERE ((uasr.id = (current_setting('myapp.user_id'::text))::uuid) AND (uasr.role = ANY (ARRAY['teller'::public.e_user_roles, 'admin'::public.e_user_roles])) AND (uasr.branch_id = ( SELECT user_auth.branch_registered_in
           FROM public.user_auth
          WHERE (user_auth.id = pending_loans.customer_id))) AND (uasr.expires_at > now())))));


--
-- Name: user_active_session_roles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.user_active_session_roles ENABLE ROW LEVEL SECURITY;

--
-- Name: user_auth; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.user_auth ENABLE ROW LEVEL SECURITY;

--
-- Name: user_auth_setup_token; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.user_auth_setup_token ENABLE ROW LEVEL SECURITY;

--
-- Name: user_bank_accounts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.user_bank_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: user_roles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

--
-- Name: loans user_see_their_own_loans; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY user_see_their_own_loans ON public.loans FOR SELECT USING (((customer_id = (current_setting('myapp.user_id'::text))::uuid) AND (EXISTS ( SELECT 1
   FROM public.user_active_session_roles uasr
  WHERE ((uasr.id = (current_setting('myapp.user_id'::text))::uuid) AND (uasr.role = 'customer'::public.e_user_roles) AND (uasr.expires_at > now()))))));


--
-- Name: audit_logs_loans_payment user_see_their_own_paid_loans; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY user_see_their_own_paid_loans ON public.audit_logs_loans_payment FOR SELECT USING (((EXISTS ( SELECT 1
   FROM public.loans
  WHERE ((audit_logs_loans_payment.loan_id = loans.id) AND (loans.customer_id = (current_setting('myapp.user_id'::text))::uuid)))) AND (EXISTS ( SELECT 1
   FROM public.user_active_session_roles uasr
  WHERE ((uasr.id = (current_setting('myapp.user_id'::text))::uuid) AND (uasr.role = 'customer'::public.e_user_roles) AND (uasr.expires_at > now()))))));


--
-- Name: user_roles users_see_own_roles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY users_see_own_roles ON public.user_roles FOR SELECT USING ((id = (current_setting('myapp.user_id'::text))::uuid));


--
-- Name: user_information users_update_their_own_data; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY users_update_their_own_data ON public.user_information FOR UPDATE USING (((id = (current_setting('myapp.user_id'::text))::uuid) AND (EXISTS ( SELECT 1
   FROM public.user_active_session_roles uasr
  WHERE ((uasr.id = (current_setting('myapp.user_id'::text))::uuid) AND (uasr.expires_at > now()))))));


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO testuser;


--
-- Name: FUNCTION allocate_role(p_user_id uuid, p_user_role public.e_user_roles); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.allocate_role(p_user_id uuid, p_user_role public.e_user_roles) TO testuser;


--
-- Name: FUNCTION no_invalid_time_entering(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.no_invalid_time_entering() TO testuser;


--
-- Name: PROCEDURE set_user_password_and_delete_token(IN p_password_hash text, IN p_username text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.set_user_password_and_delete_token(IN p_password_hash text, IN p_username text) TO testuser;


--
-- Name: PROCEDURE set_user_password_and_delete_token(IN p_password_hash text, IN p_username text, IN p_token uuid); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.set_user_password_and_delete_token(IN p_password_hash text, IN p_username text, IN p_token uuid) TO testuser;


--
-- Name: TABLE audit_logs_loans_payment; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.audit_logs_loans_payment TO PUBLIC;
GRANT ALL ON TABLE public.audit_logs_loans_payment TO testuser;


--
-- Name: TABLE bank_branches; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.bank_branches TO testuser;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.bank_branches TO PUBLIC;


--
-- Name: SEQUENCE bank_branches_branch_number_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.bank_branches_branch_number_seq TO testuser;


--
-- Name: TABLE cities; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.cities TO testuser;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.cities TO PUBLIC;


--
-- Name: SEQUENCE cities_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.cities_id_seq TO testuser;


--
-- Name: TABLE deposit_withdraw_audit_logs; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.deposit_withdraw_audit_logs TO testuser;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.deposit_withdraw_audit_logs TO PUBLIC;


--
-- Name: SEQUENCE deposit_withdraw_audit_logs_log_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.deposit_withdraw_audit_logs_log_id_seq TO testuser;


--
-- Name: TABLE loans; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.loans TO PUBLIC;
GRANT ALL ON TABLE public.loans TO testuser;


--
-- Name: TABLE loan_payments; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.loan_payments TO testuser;


--
-- Name: TABLE pending_loans; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.pending_loans TO PUBLIC;
GRANT ALL ON TABLE public.pending_loans TO testuser;


--
-- Name: TABLE send_money_audit_logs; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.send_money_audit_logs TO testuser;


--
-- Name: TABLE staging; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.staging TO testuser;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.staging TO PUBLIC;


--
-- Name: TABLE test_balances; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.test_balances TO testuser;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.test_balances TO PUBLIC;


--
-- Name: SEQUENCE test_balances_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.test_balances_id_seq TO testuser;


--
-- Name: TABLE user_active_session_roles; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_active_session_roles TO testuser;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.user_active_session_roles TO PUBLIC;


--
-- Name: TABLE user_auth; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_auth TO testuser;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.user_auth TO PUBLIC;


--
-- Name: TABLE user_auth_setup_token; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_auth_setup_token TO testuser;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.user_auth_setup_token TO PUBLIC;


--
-- Name: TABLE user_bank_accounts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_bank_accounts TO testuser;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.user_bank_accounts TO PUBLIC;


--
-- Name: TABLE user_information; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_information TO testuser;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.user_information TO PUBLIC;


--
-- Name: TABLE user_roles; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_roles TO testuser;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.user_roles TO PUBLIC;


--
-- Name: TABLE v_balance; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.v_balance TO testuser;


--
-- Name: TABLE v_sender_balance; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.v_sender_balance TO testuser;


--
-- Name: TABLE zakaat; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.zakaat TO testuser;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.zakaat TO PUBLIC;


--
-- Name: TABLE zakaat_test; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.zakaat_test TO testuser;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.zakaat_test TO PUBLIC;


--
-- Name: SEQUENCE zakaat_test_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.zakaat_test_id_seq TO testuser;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT,INSERT,UPDATE ON TABLES TO testuser;


--
-- PostgreSQL database dump complete
--

\unrestrict Mwrtj3Wh6kYlXINe7AIb9NoZRMIRZjW8vDvyuLGWHXBk3yqZP4cSXHCW6ZSrWhF

