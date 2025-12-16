import pyodbc
from flask import session
from config import Config

def _make_conn_str() -> str:
    driver = Config.ODBC_DRIVER
    server = Config.DB_SERVER
    database = Config.DB_NAME

    if Config.DB_TRUSTED_CONNECTION:
        return (
            f"DRIVER={{{driver}}};"
            f"SERVER={server};"
            f"DATABASE={database};"
            "Trusted_Connection=yes;"
        )

    # SQL Auth
    return (
        f"DRIVER={{{driver}}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        f"UID={Config.DB_USER};"
        f"PWD={Config.DB_PASSWORD};"
        "TrustServerCertificate=yes;"
    )

def get_connection() -> pyodbc.Connection:
    conn = pyodbc.connect(_make_conn_str(), autocommit=False)
    return conn

def set_session_context(conn: pyodbc.Connection) -> None:

    username = session.get("username")
    clearance = session.get("clearance", 0)
    student_pk_id = session.get("student_pk_id")

    cur = conn.cursor()

    cur.execute("EXEC sys.sp_set_session_context @key=N'Username', @value=NULL;")
    cur.execute("EXEC sys.sp_set_session_context @key=N'Clearance', @value=0;")
    cur.execute("EXEC sys.sp_set_session_context @key=N'Student_PK_ID', @value=NULL;")

    if username:
        cur.execute("EXEC sys.sp_set_session_context @key=N'Username', @value=?;", username)
        cur.execute("EXEC sys.sp_set_session_context @key=N'Clearance', @value=?;", int(clearance))
        cur.execute("EXEC sys.sp_set_session_context @key=N'Student_PK_ID', @value=?;", student_pk_id)

    cur.close()
