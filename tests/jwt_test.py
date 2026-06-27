from jose import jwt

payload = {"id" : 1}

token = jwt.encode(payload, "awabikey", algorithm="HS256")

