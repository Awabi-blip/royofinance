import os
from decimal import Decimal

import psycopg2
import pytest
from dotenv import load_dotenv


load_dotenv()


DATABASE_URL = os.getenv("DATABASE_URL")
ADMIN_ID = "87998288-c261-49f5-81fe-f623148921dd"

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
            ADMIN_ID,
            "admin",
        )

        assert expiry_hours == 6

        # Keep the active session for the tests.
        conn.commit()

    finally:
        conn.close()


def insert_role(cursor, user_id, role):
    cursor.execute(
        "SELECT set_config('myapp.user_id', %s, false)",
        (ADMIN_ID,),
    )

    cursor.execute(
        """
        INSERT INTO user_roles (id, role)
        VALUES (%s::UUID, %s::e_user_roles)
        """,
        (user_id, role),
    )

def test_existing_role_should_fail():
    conn = get_connection()

    try:
        with conn.cursor() as cursor:
            with pytest.raises(psycopg2.Error):
                insert_role(
                    cursor,
                    "36db91c6-5f45-43aa-8d99-c0310f1aaf77",
                    "customer",
                )

    finally:
        conn.rollback()
        conn.close()

def test_different_branch_should_fail():
    conn = get_connection()

    try:
        with conn.cursor() as cursor:
            with pytest.raises(psycopg2.Error):
                insert_role(
                    cursor,
                    "b13ab668-31ac-4c14-87a8-7b1efc500f36",
                    "teller",
                )

    finally:
        conn.rollback()
        conn.close()


def test_same_branch_should_succeed():
    conn = get_connection()

    try:
        with conn.cursor() as cursor:
            insert_role(
                cursor,
                "36db91c6-5f45-43aa-8d99-c0310f1aaf77",
                "teller",
            )

            cursor.execute(
                """
                SELECT 1
                FROM user_roles
                WHERE id = %s::UUID
                AND role = %s::e_user_roles
                """,
                (
                    "36db91c6-5f45-43aa-8d99-c0310f1aaf77",
                    "teller",
                ),
            )

            assert cursor.fetchone() is not None

    finally:
        conn.rollback()
        conn.close()