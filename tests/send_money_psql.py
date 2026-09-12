import os
from decimal import Decimal

import psycopg2
import pytest
from dotenv import load_dotenv


load_dotenv()


DATABASE_URL = os.getenv("DATABASE_URL")

SENDER_ID = "a0fabb0b-550b-491d-8bc6-9840c2811230"
RECEIVER_ACCOUNT_NUMBER = "650b8f0d-3080-447a-8776-1e24fbf4c110"
SENDER_ACCOUNT_TYPE = "saving"


def get_connection():
    return psycopg2.connect(DATABASE_URL)


def login_user(connection, user_id, role="customer"):
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT set_config('myapp.user_id', %s, false)
            """,
            (str(user_id),)
        )

        cursor.execute(
            """
            SELECT allocate_role(%s::e_user_roles)
            """,
            (role,)
        )

        return cursor.fetchone()[0]

@pytest.fixture(scope="module", autouse=True)
def login_once():
    conn = get_connection()

    try:
        expiry_hours = login_user(
            conn,
            SENDER_ID,
            "customer",
        )

        assert expiry_hours == 2

        # Keep the active session for the tests.
        conn.commit()

    finally:
        conn.close()



def call_test_send_money(
    cursor,
    sender_balance,
    receiver_balance,
    amount,
    sender_id               = SENDER_ID,
    sender_account_type     = SENDER_ACCOUNT_TYPE,
    sender_account_number   = SENDER_ACCOUNT_NUMBER,
    receiver_account_number = RECEIVER_ACCOUNT_NUMBER
):

    cursor.execute(
        "SELECT set_config('myapp.user_id', %s, false)",
        (SENDER_ID,)
    )

    cursor.execute(
        """
        SELECT test_send_money(
            %s::UUID,
            %s::DECIMAL,
            %s::e_account_type,
            %s::UUID,
            %s::DECIMAL,
            %s::DECIMAL
        );
        """,    
        (
            SENDER_ID,
            sender_balance,
            SENDER_ACCOUNT_TYPE,
            receiver_account_number,
            receiver_balance,
            amount,
        ),
    )

    return cursor.fetchone()[0]


def test_send_money_success():
    conn = get_connection()

    try:
        with conn.cursor() as cursor:
            result = call_test_send_money(
                cursor=cursor,
                sender_balance=Decimal("10000.00"),
                receiver_balance=Decimal("2000.00"),
                amount=Decimal("5000.00"),
                receiver_account_number='4bbee994-ebda-49a0-90aa-1c1c267836c2'

            )

            assert result == Decimal("7000.00")

    finally:
        # Undo everything test_send_money changed.
        conn.rollback()
        conn.close()


def test_send_money_fail():
    conn = get_connection()

    try:
        with conn.cursor() as cursor:
            with pytest.raises(
                psycopg2.errors.RaiseException,
                match="not possible",
            ):
                # self send.
                call_test_send_money(
                    cursor=cursor,
                    sender_balance=Decimal("10000.00"),
                    receiver_balance=Decimal("2000.00"),
                    amount=Decimal("5000.00"),
                    receiver_account_number='650b8f0d-3080-447a-8776-1e24fbf4c110'
                )

    finally:
        conn.rollback()
        conn.close()


def test_negative_balance_fails():
    conn = get_connection()

    try:
        with conn.cursor() as cursor:

            with pytest.raises(psycopg2.errors.CheckViolation):
                call_test_send_money(
                    cursor=cursor,
                    sender_balance=Decimal("-1.00"),
                    receiver_balance=Decimal("2000.00"),
                    amount=Decimal("5000.00"),
                )

    finally:
        conn.rollback()
        conn.close()


def test_cannot_send_more_than_available():
    conn = get_connection()

    try:
        with conn.cursor() as cursor:

            with pytest.raises(psycopg2.Error):
                call_test_send_money(
                    cursor=cursor,
                    sender_balance=Decimal("10000.00"),
                    receiver_balance=Decimal("2000.00"),
                    amount=Decimal("15000.00"),
                )

    finally:
        conn.rollback()
        conn.close()