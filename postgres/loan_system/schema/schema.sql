CREATE TYPE e_loan_status AS ENUM ('active', 'paid');

CREATE TABLE IF NOT EXISTS pending_loans(
    customer_id UUID,
    customer_role e_user_roles CHECK(customer_role = 'customer'::e_user_roles) NOT NULL,
    amount DECIMAL(9,2) NOT NULL CHECK(amount >= 0 AND amount <= 1000000),
    event_date DATE DEFAULT CURRENT_DATE NOT NULL,
    account_type e_account_type NOT NULL,
    bank_account_number UUID NOT NULL,
    PRIMARY KEY(customer_id),
    FOREIGN KEY(customer_id, customer_role) REFERENCES user_roles(id,role),
    FOREIGN KEY (account_type, bank_account_number) REFERENCES user_bank_accounts(account_type, account_number)
);

CREATE TABLE IF NOT EXISTS loans (
    id SERIAL,
    customer_id UUID NOT NULL,
    customer_role e_user_roles CHECK(customer_role = 'customer'::e_user_roles) NOT NULL,
    amount DECIMAL(9,2) NOT NULL CHECK(amount>= 0 AND amount <= 1000000),
    status e_loan_status NOT NULL DEFAULT 'active',
    approved_by UUID NOT NULL,
    approver_role e_user_roles NOT NULL,
    account_type e_account_type NOT NULL,
    bank_account_number UUID NOT NULL,
    event_date DATE DEFAULT CURRENT_DATE NOT NULL,
    PRIMARY KEY(id),
    FOREIGN KEY(customer_id, customer_role) REFERENCES user_roles(id, role),
    FOREIGN KEY(approved_by,approver_role) REFERENCES user_roles(id, role),
    FOREIGN KEY (account_type, bank_account_number) REFERENCES user_bank_accounts(account_type, account_number)
);

ALTER TABLE loans ADD constraint loan_amount_check CHECK (amount>= 0 AND amount <= 1000000);

CREATE UNIQUE INDEX idx_unique_pending_ongoing_loan
ON loans (customer_id) WHERE status IN ('active');

CREATE TABLE IF NOT EXISTS audit_logs_loans_payment(
    log_id SERIAL,
    loan_id INT NOT NULL,
    amount_paid DECIMAL(9,2) NOT NULL,
    happened_at TIMESTAMPTZ NOT NULL DEFAULT now(), 
    PRIMARY KEY (log_id),
    FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE
);


CREATE OR REPLACE FUNCTION prevent_invalid_approval_date()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if the new date_approved is strictly in the past
    IF NEW.event_date != CURRENT_DATE THEN
        RAISE EXCEPTION 'The event_date (%) cannot be in the past or future. Current date is %.', NEW.event_date, CURRENT_DATE;
    END IF;
    -- If the check passes, proceed with the insert/update
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER enforce_valid_approval_date
BEFORE INSERT ON loans
FOR EACH ROW
EXECUTE FUNCTION prevent_invalid_approval_date();

CREATE TRIGGER enforce_valid_approval_date
BEFORE INSERT OR UPDATE ON pending_loans
FOR EACH ROW
EXECUTE FUNCTION prevent_invalid_approval_date();



