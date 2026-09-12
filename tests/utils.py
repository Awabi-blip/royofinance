import os

import psycopg2
import pytest
from dotenv import load_dotenv


load_dotenv()


DATABASE_URL = os.getenv("DATABASE_URL")

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
