ALTER TABLE loans ENABLE ROW LEVEL SECURITY;
ALTER TABLE pending_loans ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs_loans_payment ENABLE ROW LEVEL SECURITY;


CREATE POLICY tenant_loans
ON loans FOR SELECT
TO PUBLIC USING(
    EXISTS (
        SELECT 1 FROM user_active_session_roles AS uasr
        WHERE uasr.id = current_setting('myapp.user_id')::UUID
        AND uasr.role IN ('teller'::e_user_roles, 'admin'::e_user_roles)
        AND uasr.branch_id = (SELECT branch_registered_in
        FROM user_auth WHERE user_auth.id = loans.customer_id::UUID)
        AND uasr.expires_at > now()
    )
);

SET ROLE postgres;
CREATE POLICY user_see_their_own_loans
ON loans FOR SELECT 
TO PUBLIC USING(
    loans.customer_id = current_setting('myapp.user_id')::UUID
    AND
    EXISTS (
        SELECT 1 FROM user_active_session_roles AS uasr
        WHERE uasr.id = current_setting('myapp.user_id')::UUID
        AND uasr.role = 'customer'::e_user_roles
        AND uasr.expires_at > now()
    )
);


CREATE POLICY tenant_pending_loans
ON pending_loans FOR SELECT
TO PUBLIC USING(
    EXISTS (
        SELECT 1 FROM user_active_session_roles AS uasr
        WHERE uasr.id = current_setting('myapp.user_id')::UUID
        AND uasr.role IN ('teller'::e_user_roles, 'admin'::e_user_roles)
        AND uasr.branch_id = (SELECT branch_registered_in
        FROM user_auth WHERE user_auth.id = pending_loans.customer_id::UUID)
        AND uasr.expires_at > now()
    )
);

CREATE POLICY staff_see_audit_logs_loans
ON audit_logs_loans_payment FOR SELECT
TO PUBLIC USING (
    EXISTS (
        SELECT 1 FROM user_active_session_roles AS uasr
        WHERE uasr.id = current_setting('myapp.user_id')::UUID
        AND uasr.role IN ('teller'::e_user_roles, 'admin'::e_user_roles)
        AND uasr.branch_id = (SELECT branch_registered_in FROM user_auth
        WHERE user_auth.id = (SELECT loans.customer_id  FROM loans 
        WHERE loans.id = audit_logs_loans_payment.loan_id))
        AND uasr.expires_at > now()
    )
);

CREATE POLICY user_see_their_own_paid_loans
ON audit_logs_loans_payment FOR SELECT 
TO PUBLIC USING(
    EXISTS
    (
        SELECT 1 FROM loans
        WHERE audit_logs_loans_payment.loan_id = loans.id
        AND loans.customer_id = current_setting('myapp.user_id')::UUID
    )
    AND
    EXISTS (
        SELECT 1 FROM user_active_session_roles AS uasr
        WHERE uasr.id = current_setting('myapp.user_id')::UUID
        AND uasr.role = 'customer'::e_user_roles
        AND uasr.expires_at > now()
    )
);




