CREATE VIEW loan_payments 
WITH (security_invoker = true ) AS
SELECT 
allp.loan_id AS loan_id, 
allp.amount_paid AS amount_paid, 
allp.happened_at AS paid_at,
l.status AS loan_status
FROM audit_logs_loans_payment AS allp
JOIN loans as l
ON l.id = allp.loan_id;


SELECT * from loan_payments;




