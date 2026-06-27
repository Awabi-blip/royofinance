# Auth:
## Auth Flow:
- A new user goes to the bank, and register their info.
- They are given a username which is agreed upon by them and the bank, an admin inserts their username into the user_auth table.
- An admin generates a token for the user to set their password themselves.
- The user then provides with a username, and a password, and a token to set their password.
- The token is then deleted.
- Upon creation of a new branch, it is plausible to add an admin there first. This will be done by the user with the postgres role, because the scope of an admin is only limited to one branch, (this was part of security platform requirments).
- The admin can add other admins, tellers, customers in their respsective branches

## Auth RLS:

### `user_auth`
- Admins can SELECT users in their own branch only
- Admins can INSERT users into their own branch only

### `user_roles`
- Admins can SELECT roles of users in their branch
- Admins can DELETE roles of users in their branch
- Users can SELECT their own role only

### `user_auth_setup_token`
- Admins have full access to setup tokens for users in their branch

### `user_active_session_roles`
- Users can SELECT their own session
- Tellers can SELECT all sessions
- Admins have full access to all session data

### Trigger Guards
- `user_auth` → blocks cross-branch inserts, blocks password being set on insert
- `user_auth_setup_token` → blocks token creation if user already has a password

# Issues:
## user_auth_setup_token
user auth setup token allows admin to add themselves into auth_token, need a fix
no security for user_auth_password_set