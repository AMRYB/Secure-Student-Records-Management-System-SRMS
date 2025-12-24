import os
import pyodbc
from dotenv import load_dotenv

load_dotenv()  # reads .env

def _build_conn_str() -> str:
    driver = os.getenv("ODBC_DRIVER", "ODBC Driver 17 for SQL Server")
    server = os.getenv("DB_SERVER", ".")
    dbname = os.getenv("DB_NAME", "SRMS")
    trusted = (os.getenv("DB_TRUSTED_CONNECTION", "yes") or "yes").lower() in ("yes", "true", "1")

    if trusted:
        return (
            f"DRIVER={{{driver}}};"
            f"SERVER={server};"
            f"DATABASE={dbname};"
            "Trusted_Connection=yes;"
        )

    # SQL auth fallback (only used if trusted_connection=no)
    user = os.getenv("DB_USER", "")
    pwd = os.getenv("DB_PASSWORD", "")
    return (
        f"DRIVER={{{driver}}};"
        f"SERVER={server};"
        f"DATABASE={dbname};"
        f"UID={user};PWD={pwd};"
    )

def get_conn():
    """
    Returns a pyodbc connection to SQL Server using env vars.
    """
    conn_str = _build_conn_str()
    # autocommit False so we can commit where needed
    return pyodbc.connect(conn_str, autocommit=False)

def call_sp(sp_name: str, params: tuple = ()):
    """
    Execute a stored procedure and return rows as list[dict].
    If SP returns no result set, commit and return [].
    """
    with get_conn() as conn:
        cur = conn.cursor()

        if params:
            placeholders = ",".join(["?"] * len(params))
            sql = f"EXEC {sp_name} {placeholders}"
            cur.execute(sql, params)
        else:
            sql = f"EXEC {sp_name}"
            cur.execute(sql)

        # Try reading a result set
        try:
            if cur.description is None:
                conn.commit()
                return []

            columns = [c[0] for c in cur.description]
            rows = cur.fetchall()
            return [dict(zip(columns, r)) for r in rows]
        except pyodbc.ProgrammingError:
            # no results
            conn.commit()
            return []
        finally:
            # If SP made changes, commit
            try:
                conn.commit()
            except Exception:
                pass