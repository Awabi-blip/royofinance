ALTER TABLE user_bank_accounts ENABLE ROW LEVEL SECURITY;
SET ROLE postgres;
CREATE POLICY customers_see_their_accounts 
ON user_bank_accounts
FOR SELECT TO PUBLIC
USING (
    EXISTS(
        SELECT 1 FROM user_active_session_roles AS uasr
        WHERE uasr.id = current_setting('myapp.user_id')::UUID
        AND uasr.role = 'customer'::e_user_roles
        AND user_bank_accounts.customer_id = uasr.id
        AND uasr.expires_at > now()
    )
);

CREATE POLICY admins_see_all_accounts 
ON user_bank_accounts 
FOR SELECT TO PUBLIC
USING (
    EXISTS (
        SELECT 1 FROM user_active_session_roles as uasr
        WHERE uasr.id = current_setting('myapp.user_id')::UUID
        AND uasr.role = 'admin'::e_user_roles
        AND uasr.expires_at > now()
        AND uasr.branch_id = (SELECT branch_registered_in FROM user_auth
        WHERE id = user_bank_accounts.customer_id)
        )
);

SET ROLE postgres;

CREATE POLICY admins_see_all_audit_logs
ON deposit_withdraw_audit_logs
USING(
    EXISTS(
        SELECT 1 FROM user_active_session_roles as uasr
        WHERE uasr.id = current_setting('myapp.user_id')::UUID
        AND uasr.role = 'admin'::e_user_roles
        AND uasr.expires_at > now()
        AND uasr.branch_id = (SELECT user_auth.branch_registered_in FROM user_auth WHERE user_auth.id = 
            (SELECT user_bank_accounts.customer_id FROM user_bank_accounts WHERE user_bank_accounts.account_number = 
            deposit_withdraw_audit_logs.account_number)
        )
    )
);  

CREATE TABLE send_money_audit_logs (
    id SERIAL PRIMARY KEY,
    sender_account_number UUID NOT NULL,
    receiver_account_number UUID NOT NULL,
    amount DECIMAL(9,2) NOT NULL,
    happened_at TIMESTAMP DEFAULT NOW(),
    FOREIGN KEY (sender_account_number) REFERENCES user_bank_accounts(account_number),
    FOREIGN KEY (receiver_account_number) REFERENCES user_bank_accounts(account_number)
);

CREATE POLICY staff_sees_send_money_logs
ON send_money_audit_logs
FOR SELECT TO PUBLIC
USING (
    EXISTS (
        SELECT 1 FROM user_active_session_roles as uasr
        WHERE uasr.id = current_setting('myapp.user_id')::UUID
        AND uasr.role IN ('admin'::e_user_roles, 'teller'::e_user_roles)
        AND uasr.expires_at > now())

); -- no branch id because an admin can see all incoming and outgoing transactions highkey

CREATE POLICY staff_sees_send_money_logs
ON send_money_audit_logs
FOR SELECT TO PUBLIC
USING (
    EXISTS (
        SELECT 1 FROM user_active_session_roles as uasr
        WHERE uasr.id = current_setting('myapp.user_id')::UUID
        AND uasr.role = 'customer'::e_user_roles
        AND uasr.expires_at > now()
        AND uasr.id = (
            SELECT uba.customer_id 
            FROM user_bank_accounts AS uba
            WHERE uba.account_number = sender_account_number)
        )

);
