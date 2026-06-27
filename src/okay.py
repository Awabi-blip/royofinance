from pwdlib import PasswordHash
password_hash = PasswordHash.recommended()
hashed_string = password_hash.hash("cristiano_ronaldo")
print(hashed_string)

