--TODO : enum type for saving vs active account
CREATE TYPE e_account_type AS ENUM('active', 'saving');

--TODO : table for banks, imp: saving min balance 1000, cant withdraw if less than 1000
CREATE TABLE IF NOT EXISTS user_bank_accounts(
    customer_id UUID NOT NULL,
    role e_user_roles NOT NULL CHECK (role = 'customer'::e_user_roles), -- need this to confirm foreign key relation
    account_type e_account_type NOT NULL,
    account_number UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(), -- this is unique, can reference as a fk, lets see
    balance DECIMAL(18,2) NOT NULL CHECK (balance >= 0), --quadrillions,
    date_created DATE DEFAULT CURRENT_DATE NOT NULL, --don't need exact timestamp for this tbh
    expires_at DATE NOT NULL,
    UNIQUE(account_number, account_type),
    PRIMARY KEY(customer_id, account_type), --ok why the flip did i do this, mmm, ionno
    FOREIGN KEY (customer_id, role) REFERENCES user_roles(id, role) ON DELETE CASCADE
);
--forgot to add this:
ALTER TABLE user_bank_accounts DROP CONSTRAINT "user_bank_accounts_balance_check" 

--bank rule, every account expires in 2 years unless verified, minimum 6 months cant just expire tomorrow
ALTER TABLE user_bank_accounts ADD CONSTRAINT no_negative_balance CHECK (balance >= 0);

--TODO 
--make an enum type for, action, wether its withdraw or, deposit.
--store the timestamp of withdraw with maybe time zone?
--with time zone i can check hours more accurately i think, tho it should still be in scope
--because usually transactions are carried out per branch, so non time range ones are also scoped
--maybe good practice, i guess. but i have all columns as time stamp with time range so ill do that.
--

CREATE TYPE e_action_type AS ENUM('withdraw', 'deposit');
CREATE TABLE deposit_withdraw_audit_logs(
    log_id BIGSERIAL,
    account_number UUID NOT NULL,
    action_type e_action_type NOT NULL,
    amount DECIMAL(9,2) NOT NULL,
    happened_at TIMESTAMPTZ NOT NULL DEFAULT now(), 
    done_by UUID NOT NULL,
    doer_role e_user_roles NOT NULL CHECK(doer_role IN ('teller', 'admin', 'owner')),
    PRIMARY KEY (log_id),
    FOREIGN KEY (account_number) REFERENCES user_bank_accounts(account_number) ON DELETE CASCADE,
    FOREIGN KEY (done_by, doer_role) REFERENCES user_roles(id, role) ON DELETE CASCADE
);
ALTER TABLE deposit_withdraw_audit_logs ALTER COLUMN happened_at SET DEFAULT now();
--reading the docs feel good lowkey

CREATE TABLE send_money_audit_logs (
    id SERIAL PRIMARY KEY,
    sender_account_number UUID NOT NULL,
    receiver_account_number UUID NOT NULL,
    amount DECIMAL(9,2) NOT NULL,
    happened_at TIMESTAMP DEFAULT NOW(),
    FOREIGN KEY (sender_account_number) REFERENCES user_bank_accounts(account_number),
    FOREIGN KEY (receiver_account_number) REFERENCES user_bank_accounts(account_number)
);

