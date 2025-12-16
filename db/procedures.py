from typing import Optional, Dict, Any
import pyodbc
from db.connection import set_session_context


# ----------------------------
# Helpers
# ----------------------------
def _rows_to_dicts(cur: pyodbc.Cursor) -> list[dict]:
    cols = [c[0] for c in cur.description]
    rows = cur.fetchall()
    return [{cols[i]: r[i] for i in range(len(cols))} for r in rows]


def _advance_to_select(cur: pyodbc.Cursor) -> bool:
    """Skip non-SELECT resultsets until we find one (cur.description != None)."""
    while cur.description is None:
        has_more = cur.nextset()
        if not has_more:
            return False
    return True


def _open_key(cur: pyodbc.Cursor) -> None:
    cur.execute("OPEN SYMMETRIC KEY SRMS_SymmetricKey DECRYPTION BY CERTIFICATE SRMS_Certificate;")


def _close_key(cur: pyodbc.Cursor) -> None:
    cur.execute("CLOSE SYMMETRIC KEY SRMS_SymmetricKey;")


# ----------------------------
# Auth
# ----------------------------
def sp_login(conn: pyodbc.Connection, username: str, password: str) -> Optional[Dict[str, Any]]:
    cur = conn.cursor()
    cur.execute("EXEC sp_Login @Username=?, @Password=?;", username, password)

    if not _advance_to_select(cur):
        cur.close()
        conn.commit()
        return None

    row = cur.fetchone()
    cur.close()
    conn.commit()

    if not row:
        return None

    # Username, Role, ClearanceLevel, Student_PK_ID, InstructorID
    return {
        "username": row[0],
        "role": row[1],
        "clearance": int(row[2]),
        "student_pk_id": row[3],
        "instructor_id": row[4],
    }


# ----------------------------
# Public
# ----------------------------
def get_public_courses(conn: pyodbc.Connection) -> list[dict]:
    cur = conn.cursor()
    cur.execute("SELECT CourseID, CourseName, PublicInfo FROM vw_Public_Courses;")

    if cur.description is None:
        cur.close()
        conn.commit()
        return []

    out = _rows_to_dicts(cur)
    cur.close()
    conn.commit()
    return out


# ----------------------------
# Student
# ----------------------------
def sp_get_student_profile(conn: pyodbc.Connection) -> list[dict]:
    set_session_context(conn)
    cur = conn.cursor()
    cur.execute("EXEC sp_GetStudentProfile @Username=?;", "ignored")

    if cur.description is None:
        cur.close()
        conn.commit()
        return []

    out = _rows_to_dicts(cur)
    cur.close()
    conn.commit()
    return out


def vw_student_own_data(conn: pyodbc.Connection) -> list[dict]:
    """
    vw_Student_OwnData uses DECRYPTBYKEY so we must OPEN SYMMETRIC KEY in this session.
    """
    set_session_context(conn)
    cur = conn.cursor()

    _open_key(cur)
    cur.execute("SELECT * FROM vw_Student_OwnData;")

    if cur.description is None:
        _close_key(cur)
        cur.close()
        conn.commit()
        return []

    out = _rows_to_dicts(cur)
    _close_key(cur)
    cur.close()
    conn.commit()
    return out


def sp_submit_role_request(conn: pyodbc.Connection, username: str, requested_role: str, reason: str) -> None:
    cur = conn.cursor()
    cur.execute(
        "EXEC sp_SubmitRoleRequest @Username=?, @RequestedRole=?, @Reason=?;",
        username, requested_role, reason
    )
    cur.close()
    conn.commit()


# ----------------------------
# Instructor
# ----------------------------
def vw_instructor_students(conn: pyodbc.Connection) -> list[dict]:
    set_session_context(conn)
    cur = conn.cursor()
    cur.execute("SELECT * FROM vw_Instructor_Students ORDER BY FullName;")

    if cur.description is None:
        cur.close()
        conn.commit()
        return []

    out = _rows_to_dicts(cur)
    cur.close()
    conn.commit()
    return out


def sp_add_student(
    conn: pyodbc.Connection,
    student_id_input: str,
    full_name: str,
    email: str,
    phone: str,
    dob: str,  # YYYY-MM-DD
    department: str,
    classification: int,
    requester_username: str
) -> None:
    cur = conn.cursor()
    cur.execute(
        "EXEC sp_AddStudent "
        "@StudentID_Input=?, @FullName=?, @Email=?, @Phone=?, @DOB=?, @Department=?, @Classification=?, @RequesterUsername=?;",
        student_id_input, full_name, email, phone, dob, department, int(classification), requester_username
    )
    cur.close()
    conn.commit()


def sp_add_grade(conn: pyodbc.Connection, student_pk_id: int, course_id: int, grade_value: float, instructor_username: str) -> None:
    cur = conn.cursor()
    cur.execute(
        "EXEC sp_AddGrade @Student_PK_ID=?, @CourseID=?, @GradeValue=?, @InstructorUsername=?;",
        int(student_pk_id), int(course_id), float(grade_value), instructor_username
    )
    cur.close()
    conn.commit()


def sp_get_grades(conn: pyodbc.Connection, course_id: int) -> list[dict]:
    set_session_context(conn)
    cur = conn.cursor()
    cur.execute("EXEC sp_GetGrades @CourseID=?;", int(course_id))

    if not _advance_to_select(cur):
        cur.close()
        conn.commit()
        return []

    out = _rows_to_dicts(cur)
    cur.close()
    conn.commit()
    return out


def sp_get_aggregate_grades(conn: pyodbc.Connection, course_id: int) -> list[dict]:
    set_session_context(conn)
    cur = conn.cursor()
    cur.execute("EXEC sp_GetAggregateGrades @CourseID=?;", int(course_id))

    if not _advance_to_select(cur):
        cur.close()
        conn.commit()
        return []

    out = _rows_to_dicts(cur)
    cur.close()
    conn.commit()
    return out


# ----------------------------
# TA
# ----------------------------
def vw_ta_assigned_students(conn: pyodbc.Connection) -> list[dict]:
    set_session_context(conn)
    cur = conn.cursor()
    cur.execute("SELECT * FROM vw_TA_AssignedStudents ORDER BY FullName;")

    if cur.description is None:
        cur.close()
        conn.commit()
        return []

    out = _rows_to_dicts(cur)
    cur.close()
    conn.commit()
    return out


def sp_update_attendance(conn: pyodbc.Connection, attendance_id: int, new_status: bool, ta_username: str) -> None:
    cur = conn.cursor()
    cur.execute(
        "EXEC sp_UpdateAttendance @AttendanceID=?, @NewStatus=?, @TAUsername=?;",
        int(attendance_id), 1 if new_status else 0, ta_username
    )
    cur.close()
    conn.commit()


def list_attendance_for_ta(conn: pyodbc.Connection, course_id: int, ta_username: str) -> list[dict]:
    """
    مفيش SP جاهز لعرض attendance list، فبنجيبها SELECT مباشر
    + بنعمل scope check على TA_COURSES
    """
    cur = conn.cursor()

    cur.execute("SELECT 1 FROM TA_COURSES WHERE TAUsername=? AND CourseID=?;", ta_username, int(course_id))
    ok = cur.fetchone()
    if not ok:
        cur.close()
        conn.commit()
        return []

    cur.execute("""
        SELECT
            a.AttendanceID, a.CourseID, a.Student_PK_ID,
            s.FullName, s.Email, a.Status, a.DateRecorded, a.Classification
        FROM ATTENDANCE a
        INNER JOIN STUDENT s ON s.PK_ID = a.Student_PK_ID
        WHERE a.CourseID = ?
        ORDER BY s.FullName;
    """, int(course_id))

    if cur.description is None:
        cur.close()
        conn.commit()
        return []

    out = _rows_to_dicts(cur)
    cur.close()
    conn.commit()
    return out


# ----------------------------
# Admin - Role Requests
# ----------------------------
def sp_get_pending_requests(conn: pyodbc.Connection, admin_username: str) -> list[dict]:
    cur = conn.cursor()
    cur.execute("EXEC sp_GetPendingRequests @AdminUsername=?;", admin_username)

    if not _advance_to_select(cur):
        cur.close()
        conn.commit()
        return []

    out = _rows_to_dicts(cur)
    cur.close()
    conn.commit()
    return out


def sp_approve_request(conn: pyodbc.Connection, request_id: int, admin_username: str, comments: str | None) -> None:
    cur = conn.cursor()
    cur.execute(
        "EXEC sp_ApproveRequest @RequestID=?, @AdminUsername=?, @Comments=?;",
        int(request_id), admin_username, comments
    )
    cur.close()
    conn.commit()


def sp_deny_request(conn: pyodbc.Connection, request_id: int, admin_username: str, comments: str | None) -> None:
    cur = conn.cursor()
    cur.execute(
        "EXEC sp_DenyRequest @RequestID=?, @AdminUsername=?, @Comments=?;",
        int(request_id), admin_username, comments
    )
    cur.close()
    conn.commit()


def get_audit_logs(conn: pyodbc.Connection, limit: int = 200) -> list[dict]:
    cur = conn.cursor()
    cur.execute(
        "SELECT TOP (?) LogID, Username, Action, TableName, RecordID, Timestamp "
        "FROM AuditLog ORDER BY LogID DESC;",
        int(limit)
    )
    if cur.description is None:
        cur.close()
        conn.commit()
        return []
    out = _rows_to_dicts(cur)
    cur.close()
    conn.commit()
    return out


# ----------------------------
# Admin - Users Management (NEW)
# Requires SQL SPs:
#   sp_AdminListUsers
#   sp_AdminCreateUser
#   sp_AdminUpdateUserRole
# ----------------------------
def sp_admin_list_users(conn: pyodbc.Connection, admin_username: str) -> list[dict]:
    cur = conn.cursor()
    cur.execute("EXEC sp_AdminListUsers @AdminUsername=?;", admin_username)

    if not _advance_to_select(cur):
        cur.close()
        conn.commit()
        return []

    out = _rows_to_dicts(cur)
    cur.close()
    conn.commit()
    return out


def sp_admin_create_user(
    conn: pyodbc.Connection,
    admin_username: str,
    new_username: str,
    new_password: str,
    new_role: str,
    clearance_level: int | None = None,
    student_pk_id: int | None = None,
    instructor_id: int | None = None
) -> None:
    cur = conn.cursor()
    cur.execute(
        "EXEC sp_AdminCreateUser "
        "@AdminUsername=?, @NewUsername=?, @NewPassword=?, @NewRole=?, "
        "@ClearanceLevel=?, @Student_PK_ID=?, @InstructorID=?;",
        admin_username,
        new_username,
        new_password,
        new_role,
        clearance_level,
        student_pk_id,
        instructor_id
    )
    cur.close()
    conn.commit()


def sp_admin_update_user_role(
    conn: pyodbc.Connection,
    admin_username: str,
    target_username: str,
    new_role: str,
    new_clearance: int | None = None
) -> None:
    cur = conn.cursor()
    cur.execute(
        "EXEC sp_AdminUpdateUserRole "
        "@AdminUsername=?, @TargetUsername=?, @NewRole=?, @NewClearance=?;",
        admin_username,
        target_username,
        new_role,
        new_clearance
    )
    cur.close()
    conn.commit()
