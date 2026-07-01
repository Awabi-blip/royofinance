import jose
from jose import jwt, JWTError
from fastapi import FastAPI, Header, HTTPException, Depends, Request, Response, Cookie
from fastapi.responses import RedirectResponse, JSONResponse
from contextlib import asynccontextmanager
from pydantic import BaseModel, TypeAdapter, Field, field_validator
from typing import Annotated
import os
from dotenv import load_dotenv
from database_driver import DatabaseDriver
from datetime import datetime, timezone, timedelta
from pwdlib import PasswordHash
from enum import Enum
import uuid
import asyncpg
from decimal import Decimal

db = DatabaseDriver()

@asynccontextmanager
async def lifespan(app: FastAPI):
    await db.connect()
    yield
    await db.pool.close()

app = FastAPI(lifespan=lifespan)

load_dotenv()
jwt_key = str(os.getenv("JWT_KEY")).strip()
bank_verification_password = str(os.getenv("BANK_VERIFICATION_PASSWORD")).strip()

pwd_hash = PasswordHash.recommended()

@app.exception_handler(ValueError)
async def value_error_handler(request: Request, exc: ValueError):
    return JSONResponse(
        status_code=400,
        content={"error": "Invalid value provided.", "details": str(exc)}
    )

# Catch any DataType mismatch globally
@app.exception_handler(TypeError)
async def type_error_handler(request: Request, exc: TypeError):
    return JSONResponse(
        status_code=400,
        content={"error": "Data type mismatch.", "details": str(exc)}
    )

# Catch Missing Keys (like missing column names from the DB)
@app.exception_handler(KeyError)
async def key_error_handler(request: Request, exc: KeyError):
    return JSONResponse(
        status_code=400,
        content={"error": "Missing required data key.", "details": str(exc)}
    )

@app.exception_handler(asyncpg.exceptions.RaiseError)
async def plpgsql_exception_handler(request, exc):
    return JSONResponse(status_code=400, 
    content={"detail": exc.message}
    )

@app.exception_handler(asyncpg.PostgresError)
async def postgres_exception_handler(request, exc):
    return JSONResponse(status_code=500, 
    content={"detail": str(exc)})


"""
RLS WILL HANDLE ALL THE SELECTS, YOU DONT HAVE TO WRITE ANY WHERE CLAUSES!
"""

class StripStringsMixin(BaseModel):
    @model_validator(mode='before')
    @classmethod
    def strip_strings(cls, values):
        return {
            k: v.strip() if isinstance(v, str) else v
            for k,v in values.items()
        }

class UserSignup(StripStringsMixin, BaseModel):
    username: str
    password: str
    token: uuid.UUID

# first time sign in function
@app.post("/signup")
async def signup(user: UserSignup):
    hashed_password = pwd_hash.hash(user.password)

    """
    Function Params:
    PROCEDURE set_user_password_and_delete_token(
        p_password_hash TEXT, 
        p_username TEXT, 
        p_token UUID)
    """

    await db.execute(
        """
        CALL set_user_password_and_delete_token($1, $2, $3)
        """, hashed_password, user.username, user.token
    )

    return {"Success": "Ok"}
    # return RedirectResponse(url="/login")


class UserLogin(StripStringsMixin, BaseModel):
    username: str
    password: str

@app.post("/login")
async def login(user: UserLogin, response: Response):
    
    row = await db.fetch("""
            SELECT * FROM user_login($1)
        """, user.username)
    

    # if row is None:
    #     raise HTTPException('user does not exist.')
    
    if len(row) != 1:
        raise HTTPException(400, 'account not found sorrie maybe try siging up first')
    
    user_id: uuid.UUID = row[0]["r_id"]
    password_hash: str = row[0]["r_password_hash"]

    if not pwd_hash.verify(user.password, password_hash):
        raise HTTPException(400, 'user not found')

    expiry_time = datetime.utcnow() + timedelta(hours=12)

    payload = {
        "id": str(user_id),
        "username": str(user.username),
        "exp": expiry_time
    }    

    role_selection_cookie = jwt.encode(payload, jwt_key, algorithm="HS256") 

    response.set_cookie(
        key="role_selection_cookie",
        value=role_selection_cookie,
        httponly=True,
        secure=False,
        samesite="lax"
    )

    # return RedirectResponse(url = "/role_select", status_code=303)



@app.get("/role_select")
async def show_roles(response: Response, role_selection_cookie: str = Cookie(None)):

    if role_selection_cookie is None:
        raise HTTPException(400, "not logged in")
    
    try:
        decoded_token = jwt.decode(role_selection_cookie, jwt_key, algorithms=["HS256"])
    except jose.exceptions.JWTError:
        raise HTTPException(404, "bad request")

    u_id = decoded_token["id"]


    role_rows = await db.fetch(
        
        """
        SELECT role FROM user_roles 
        WHERE id = $1
        """, u_id, user_id=u_id
    )

    return role_rows

class e_user_roles(str, Enum):
    admin = "admin"
    teller = "teller"
    customer = "customer"
    
class Roles(BaseModel):
    role: e_user_roles

@app.post("/role_select")
async def role_select(r: Roles, 
response: Response, role_selection_cookie: str = Cookie(None)):  
    
    if role_selection_cookie is None:
        raise HTTPException(400, "not logged in")
    
    try:
        decoded_token = jwt.decode(role_selection_cookie, jwt_key, algorithms=["HS256"])
    except jose.exceptions.JWTError:
        raise HTTPException(404, "bad request")

    """
    Function Params:
        FUNCTION allocate_role(
        p_user_id UUID, p_user_role e_user_roles)
        RETURNS INT: expiry_time
    """

    u_id = str(decoded_token["id"])
    u_name = str(decoded_token["username"])

    row = await db.fetch(
        """
        SELECT allocate_role($1, $2)
        """, decoded_token["id"], r.role
    )
    
    if len(row) != 1:
        raise HTTPException(400, 'user session not verified')
    
    expiry_duration = row[0][0]
    expiry_time = datetime.utcnow() + timedelta(hours=expiry_duration)

    payload = {
        "id": u_id,
        "username": u_name,
        "exp": expiry_time,
        "role": r.role
    }
        
    session_cookie = jwt.encode(payload, jwt_key, algorithm="HS256")

    response.set_cookie(
        key="session_cookie",
        value=session_cookie,
        httponly=True,
        secure=False,      # set False if you're on localhost (no HTTPS)
        samesite="lax"
    )

    return {"status": "OK"}
    

class PayloadApp(StripStringsMixin, BaseModel):
    id: uuid.UUID
    username: str
    exp: datetime
    role: e_user_roles


async def verify_user(session_cookie:str = Cookie(None)):

    if session_cookie is None:
        raise HTTPException(400, "role not assigned/user not logged in")

    try:
        payload = jwt.decode(session_cookie, jwt_key, algorithms=["HS256"])
    except jose.exceptions.JWTError:
        raise HTTPException(400, "bad request")

    payload = PayloadApp.model_validate(payload)
    
    return payload

class LoanRequest(BaseModel):
    amount : Decimal = Field(
        ge=Decimal('10000.00'),
        le=Decimal('1000000.00')
    )

@app.post("/loan_request")
async def loan_request(amount: LoanRequest, 
user = Depends(verify_user)):

    if user.role != e_user_roles.customer:
        raise HTTPException(400, "bad request")

    """
    Function Params:
    PROCEDURE request_loan( 
        p_balance DECIMAL(9,2)
    )
    """
    
    await db.execute("""CALL request_loan($1)""", 
    amount.amount, user_id=user.id)

    return {"status":"OK"}

@app.get("/view_loan_payments_history")
async def view_loan_payments(user = Depends(verify_user)):
    if user.role != e_user_roles.customer:
        raise HTTPException(400, "bad_request")

    payments = await db.fetch(
    """
    SELECT loan_id, amount_paid, paid_at FROM loan_payments
    WHERE loan_status = 'paid'::e_loan_status;
    
    """, user_id=user.id)

    return payments
  

@app.get("/view_loans_and_payments")
async def view_loan_payments(user = Depends(verify_user)):
    if user.role != e_user_roles.customer:
        raise HTTPException(400, "bad_request")

    loans, payments = await asyncio.gather (
    db.fetch(
    """
    SELECT 
        id as loan_id,
        amount as amount_left_to_pay,
        event_date as date_approved
    FROM loans WHERE status = 'active'::e_loan_status
    """, user_id=user.id),
    
    db.fetch(
    """
    SELECT loan_id, amount_paid, paid_at FROM loan_payments
    WHERE loan_status = 'active'::e_loan_status
    """, user_id=user.id))

    return loans, payments
  
class e_account_type(str, Enum):
    active = "active"
    saving = "saving"

class loanPayment(BaseModel):
    amount : Decimal = Field(
        ge=Decimal('50.00'),
        le=Decimal('1000000.00')
    )
    account_type: e_account_type

@app.post("/pay_for_loans")
async def pay_for_loans(info: loanPayment, 
user = Depends(verify_user)
):

    if user.role != e_user_roles.customer:
        raise HTTPException(400, "bad_request")

    """
    Function Params:
    PROCEDURE pay_for_loan (
        amount_paid DECIMAL(9,2),
        p_account_type e_account_type
    )
    """
    
    await db.execute(
       """
        CALL pay_for_loan($1,$2)
        """, info.amount, info.account_type, user_id=user.id
    )

    return f"""payment for your loan has been completed, amount_paid:{info.amount}
    and account_type_used:{info.account_type}"""
    # return RedirectResponse(url="/pay_for_loans", status_code=303)


# see their balance
@app.get("/account_info")
async def account_info(user = Depends(verify_user)):
    
    if user.role != e_user_roles.customer:
        raise HTTPException(400, "bad request")

    user_bank_account_rows = await db.fetch(
        """
        SELECT * FROM user_bank_accounts
        """, user_id = user.id)

    return user_bank_account_rows

class sendMoney(BaseModel):
    sender_account_number: uuid.UUID
    receiver_account_number: uuid.UUID
    amount : Decimal = Field(
        ge=Decimal('0.00'),
        le=Decimal('4000000.00')
    )
@app.get("/send_money")
async def show_money(
    user = Depends(verify_user)
):
    if user.role != e_user_roles.customer:
        raise HTTPException(400, "bad_request")
    
    rows = await db.fetch(
        """
        SELECT account_number, balance FROM user_bank_accounts
        WHERE CURRENT_DATE < expires_at
        """, user_id = user.id
    )

    return rows


@app.post("/send_money")
async def send_money(
info: sendMoney,
user = Depends(verify_user)):

    if user.role != e_user_roles.customer:
        raise HTTPException(400, "bad_request")

    """
    Function Params:
    PROCEDURE send_money (
    p_sender_account_number UUID,
    p_receiver_account_number UUID,
    p_amount DECIMAL(9,2))  
    """

    await db.execute(
        "CALL send_money($1, $2, $3)",
        info.sender_account_number, 
        info.receiver_account_number, info.amount, user_id=user.id
    )

    # return RedirectResponse(url="/account_info", status_code=303)


# ADMIN ONLY FUNCTIONS BELOW 

raiden_vs_armstrong = """
        ARMSTRONGGGGGGGG!!! I SAID MY SWORD WAS A TOOL OF JUSTICE.
        NOT USED IN ANGER.
        NOT USED FOR VENGEANCE.
        BUT NOW.
        NOW IM NOT SO SURE AND BESIDES, THIS. ISNT. MY. SWORD
        OK, LETS DANCE! STANDING HERE I REALISEEEEEEEEEEEEEEEEE.
        """

class depositMoney(StripStringsMixin, BaseModel):
    account_number: uuid.UUID
    customer_id: uuid.UUID
    amount : Decimal = Field(
        ge=Decimal('50.00'),
        le=Decimal('4000000.00')
    )    
    bank_verification_password: str = Field(strip_whitespace=True)

@app.post("/deposit_money")
async def deposit_money(info: depositMoney,
user = Depends(verify_user)):
    
    if user.role not in [e_user_roles.admin, e_user_roles.teller]:
        raise HTTPException(400, "bad request")
    
    if info.bank_verification_password != bank_verification_password:
        raise HTTPException(400, raiden_vs_armstrong)

    """
    Function Params:
    PROCEDURE deposit_money (
        p_account_number UUID, 
        p_customer_id UUID,
        p_deposit_amount DECIMAL(9,2),
        p_happened_at TIMESTAMPTZ DEFAULT NULL)                         
    """

    await db.execute(
    """
    CALL deposit_money($1, $2, $3, now())
    """, info.account_number, info.customer_id, info.amount, user_id=user.id)

    return {"status" : "OK"}

    # return RedirectResponse(url="/account_info", status_code=303)

class withdrawMoney(StripStringsMixin,BaseModel):
    account_number : uuid.UUID
    customer_id: uuid.UUID
    amount : Decimal = Field(
        ge=Decimal('50.00'),
        le=Decimal('4000000.00')
    )    
    emergency: bool
    bank_verification_password: str = Field(strip_whitespace=True)


@app.post("/withdraw_money")
async def withdraw_money(info: withdrawMoney,
user = Depends(verify_user)):
    
    if user.role not in [e_user_roles.admin, e_user_roles.teller]:
        raise HTTPException(400, "bad request")
    
    if info.bank_verification_password != bank_verification_password:
        raise HTTPException(400, raiden_vs_armstrong)
    
    """
    Function Params:
    PROCEDURE withdraw_money (
        p_account_number UUID, 
        p_customer_id UUID,
        p_withdraw_amount DECIMAL(9,2),
        p_emergency BOOLEAN,
        p_happened_at TIMESTAMPTZ DEFAULT NULL)
    """

    await db.execute(
        """
        CALL withdraw_money($1, $2, $3, $4, now())
        """, info.account_number, info.customer_id, info.amount, info.emergency,
        user_id=user.id
    )


    return {"status" : "OK"}
    # return RedirectResponse(url="/account_info", status_code=303)

@app.get("/view_user_info")
async def view_user_info(user = Depends(verify_user)):
    if user.role != e_user_roles.admin:
        raise HTTPException(400, 'unauthorized')
    
    rows = await db.fetch(
        """
        SELECT * FROM admins_view_user_info
        """, user_id = user.id
    )

    return rows
