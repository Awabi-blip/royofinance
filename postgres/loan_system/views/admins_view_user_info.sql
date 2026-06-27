CREATE VIEW admins_view_user_info 
WITH (security_invoker = true) AS
SELECT user_auth.id AS id, 
user_auth.username AS username,
user_bank_accounts.account_number AS account_number, 
user_bank_accounts.account_type AS account_type,
user_bank_accounts.balance AS balance
FROM user_auth JOIN user_bank_accounts
ON user_auth.id = user_bank_accounts.customer_id;

SELECT * FROM admins_view_user_info;

