CREATE OR REPLACE FUNCTION check_no_new_accounts_with_invalid_expiries(
)
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_validate_account_expiry
BEFORE INSERT OR UPDATE ON user_bank_accounts
FOR EACH ROW
EXECUTE FUNCTION check_no_new_accounts_with_invalid_expiries();

CREATE OR REPLACE FUNCTION check_valid_minimum_balance_for_saving_accounts(
)
RETURNS TRIGGER AS $$
DECLARE
BEGIN

    IF NEW.account_type = 'saving'::e_account_type
        AND NEW.balance < 1000
    THEN
        RAISE NOTICE 'money in saving account cant be less than 1000 for account_number %s', NEW.account_number;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_validate_minimal_balance
BEFORE INSERT OR UPDATE ON user_bank_accounts
FOR EACH ROW
EXECUTE FUNCTION check_valid_minimum_balance_for_saving_accounts();


