CREATE INDEX idx_active_session_staff 
ON user_active_session_roles(
    id, role, branch_id, expires_at
) WHERE role IN ('admin'::e_user_roles, 'teller'::e_user_roles, 'owner'::e_user_roles);

CREATE INDEX idx_active_session_customers ON user_active_session_roles(
    id, expires_at
) WHERE role = 'customer'::e_user_roles;

CREATE INDEX idx_fetch_branch_id 
ON user_auth
(id, branch_registered_in);

CREATE INDEX idx_fetch_user_account
ON user_bank_accounts
(customer_id, account_number, expires_at)
INCLUDE (balance);

CREATE INDEX idx_fetch_loan_amount_for_procedure
ON loans (customer_id)
INCLUDE (id, amount)
 WHERE status = 'active';

CREATE INDEX idx_loans_rls 
ON loans (id)
INCLUDE (customer_id);

CREATE INDEX idx_staff_see_audit_logs_loans
ON audit_logs_loans_payment (
    loan_id
);

