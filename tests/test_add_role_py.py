from utils import get_connection, login_user, login_once
import psycopg2
import pytest

ADMIN_ID = "87998288-c261-49f5-81fe-f623148921dd"



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