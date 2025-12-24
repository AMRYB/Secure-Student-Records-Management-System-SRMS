import os
from functools import wraps

from dotenv import load_dotenv
from flask import Flask, request, session, jsonify, render_template, redirect, url_for

from db import call_sp

load_dotenv()

# =========================================================
# App + Template/Static paths (fix TemplateNotFound)
# =========================================================
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

app = Flask(
    __name__,
    template_folder=os.path.join(BASE_DIR, "templates"),
    static_folder=os.path.join(BASE_DIR, "static"),
)

# مهم: حط أي secret في .env أفضل
app.secret_key = os.getenv("FLASK_SECRET", "change-me-please")


# =========================================================
# Helpers
# =========================================================
def role_redirect(role: str) -> str:
    if role == "Admin":
        return "/admin"
    if role == "Instructor":
        return "/instructor"
    if role == "TA":
        return "/ta"
    if role == "Student":
        return "/student"
    return "/guest"


def login_required(view_func):
    @wraps(view_func)
    def wrapper(*args, **kwargs):
        if "user" not in session:
            return redirect(url_for("login_page"))
        return view_func(*args, **kwargs)

    return wrapper


def role_required(*allowed_roles):
    def decorator(view_func):
        @wraps(view_func)
        def wrapper(*args, **kwargs):
            u = session.get("user")
            if not u:
                return redirect(url_for("login_page"))
            if u.get("Role") not in allowed_roles:
                return redirect(role_redirect(u.get("Role", "Guest")))
            return view_func(*args, **kwargs)

        return wrapper

    return decorator


def is_secret_endpoint(path: str) -> bool:
    """
    Used for BONUS: prevent caching / exporting on secret panels.
    """
    p = (path or "").lower()
    return (
        "/student/grades" in p
        or "/student/attendance" in p
        or "/ta/attendance" in p
        or "/instructor/grades" in p
        or "/instructor/attendance" in p
        or "/api/student/grades" in p
        or "/api/student/attendance" in p
        or "/api/ta/attendance" in p
        or "/api/instructor/grades" in p
        or "/api/instructor/attendance" in p
        or "/api/admin/grades" in p
        or "/api/admin/attendance" in p
    )


# =========================================================
# BONUS: GUI Flow Restrictions (headers)
# - blocks saving/caching/printing in browsers (best effort)
# =========================================================
@app.after_request
def add_security_headers(response):
    # Always avoid caching for safety
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    response.headers["X-Content-Type-Options"] = "nosniff"

    # Stronger restrictions for Secret panels (Grades/Attendance)
    if is_secret_endpoint(request.path):
        # Prevent embedding and reduce data exfil (best effort)
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "img-src 'self' data:; "
            "style-src 'self' 'unsafe-inline' https:; "
            "script-src 'self' 'unsafe-inline' https:; "
            "connect-src 'self'; "
            "object-src 'none'; "
            "base-uri 'self'; "
            "frame-ancestors 'none'; "
            "form-action 'self'; "
            "upgrade-insecure-requests"
        )
    return response


# =========================================================
# Root / Login pages
# =========================================================
@app.get("/")
def root():
    u = session.get("user")
    if u:
        return redirect(role_redirect(u.get("Role", "Guest")))
    return redirect(url_for("login_page"))


@app.get("/login")
def login_page():
    return render_template("login.html")


# =========================================================
# Auth APIs
# =========================================================
@app.post("/api/login/guest")
def api_login_guest():
    """
    Guest يدخل من غير username/password
    """
    session["user"] = {"UserID": None, "Role": "Guest", "ClearanceLevel": 1}
    return jsonify({"ok": True, "redirect": "/guest"})


@app.post("/api/login")
def api_login():
    """
    Normal login:
    frontend يرسل {username, password}
    backend يجرب الدور تلقائيًا: Admin -> Instructor -> TA -> Student
    """
    data = request.get_json(force=True) or {}
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""

    if not username or not password:
        return jsonify({"error": "Please enter username and password."}), 400

    roles_to_try = ["Admin", "Instructor", "TA", "Student"]

    for role in roles_to_try:
        rows = call_sp("dbo.sp_AuthUser", (role, username, password))
        if rows:
            row = rows[0]
            session["user"] = {
                "UserID": row.get("UserID"),
                "Role": row.get("Role"),
                "ClearanceLevel": row.get("ClearanceLevel"),
            }
            return jsonify({"ok": True, "redirect": role_redirect(session["user"]["Role"])})

    return jsonify({"error": "Incorrect username or password."}), 401


@app.post("/api/logout")
def api_logout():
    session.clear()
    return jsonify({"ok": True, "redirect": "/login"})


# =========================================================
# /info (Unified: show who is logged in + edit if allowed)
# =========================================================
@app.get("/info")
@login_required
@role_required("Admin", "Instructor", "TA", "Student", "Guest")
def info_page():
    # لازم تعمل templates/info.html + static/js/info.js
    return render_template("info.html")


@app.get("/api/me")
@login_required
@role_required("Admin", "Instructor", "TA", "Student", "Guest")
def api_me_get():
    u = session["user"]
    role = u.get("Role", "Guest")
    user_id = u.get("UserID")
    clearance = u.get("ClearanceLevel", 1)

    # Guest case
    if role == "Guest" or user_id is None:
        return jsonify(
            {
                "ok": True,
                "profile": {
                    "role": "Guest",
                    "user_id": None,
                    "clearance": 1,
                    "data": {"note": "Guest has no editable profile."},
                },
            }
        )

    # Context from SP
    ctx_rows = call_sp("dbo.sp_GetUserContext", (user_id,))
    ctx = ctx_rows[0] if ctx_rows else {}

    # Role-based profile
    data_out = None
    if role == "Student":
        rows = call_sp(
            "dbo.sp_ViewStudent_Profile",
            (role, user_id, clearance, None),
        )
        data_out = rows[0] if rows else None

    elif role in ("Admin", "TA"):
        # Needs FIX SP: sp_ViewMyUserProfile
        # Returns: UserID, Role, ClearanceLevel, FullName, Email
        rows = call_sp("dbo.sp_ViewMyUserProfile", (role, user_id))
        data_out = rows[0] if rows else None

    elif role == "Instructor":
        # If you later add sp_ViewInstructor_Profile use it, for now use context.
        data_out = ctx

    return jsonify(
        {
            "ok": True,
            "profile": {
                "role": role,
                "user_id": user_id,
                "clearance": clearance,
                "context": ctx,
                "data": data_out,
            },
        }
    )


@app.post("/api/me")
@login_required
@role_required("Admin", "Instructor", "TA", "Student")
def api_me_update():
    """
    Uses FIX SP: dbo.sp_EditMyProfile
    """
    u = session["user"]
    role = u.get("Role")
    user_id = u.get("UserID")

    data = request.get_json(force=True) or {}
    full_name = (data.get("full_name") or "").strip()
    email = (data.get("email") or "").strip()
    dob = data.get("dob")  # "YYYY-MM-DD" or None
    department = (data.get("department") or "").strip() or None

    if not full_name or not email:
        return jsonify({"error": "Full name and email are required."}), 400

    try:
        call_sp("dbo.sp_EditMyProfile", (role, user_id, full_name, email, dob, department))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


# =========================================================
# Guest (Public Courses)
# =========================================================
@app.get("/guest")
@login_required
@role_required("Guest", "Student", "TA", "Instructor", "Admin")
def guest_page():
    return render_template("guest.html")


@app.get("/api/courses/public")
@login_required
def api_public_courses():
    u = session["user"]
    courses = call_sp("dbo.sp_Guest_ViewPublicCourses", (u.get("Role", "Guest"),))
    return jsonify({"courses": courses})


# =========================================================
# Student GUI (Pages)
# =========================================================
@app.get("/student")
@login_required
@role_required("Student", "Admin")
def student_home():
    return render_template("student_home.html")


@app.get("/student/profile")
@login_required
@role_required("Student", "Admin")
def student_profile_page():
    return render_template("student_profile.html")


@app.get("/student/grades")
@login_required
@role_required("Student", "Admin")
def student_grades_page():
    return render_template("student_grades.html")


@app.get("/student/attendance")
@login_required
@role_required("Student", "Admin")
def student_attendance_page():
    return render_template("student_attendance.html")


@app.get("/student/role-request")
@login_required
@role_required("Student", "Admin")
def student_role_request_page():
    return render_template("student_role_request.html")


# =========================================================
# Student GUI (APIs)
# =========================================================
@app.get("/api/student/profile")
@login_required
@role_required("Student", "Admin")
def api_student_profile():
    u = session["user"]
    rows = call_sp(
        "dbo.sp_ViewStudent_Profile",
        (u["Role"], u["UserID"], u["ClearanceLevel"], None),
    )
    return jsonify({"profile": rows[0] if rows else None})


@app.post("/api/student/profile/edit")
@login_required
@role_required("Student", "Admin")
def api_student_profile_edit():
    """
    Uses FIX SP: dbo.sp_EditStudent_Profile
    - Student edits own only
    - Admin can edit any student_id
    """
    u = session["user"]
    data = request.get_json(force=True) or {}

    student_id = data.get("student_id")
    full_name = (data.get("full_name") or "").strip()
    email = (data.get("email") or "").strip()
    department = (data.get("department") or "").strip()

    if not isinstance(student_id, int):
        return jsonify({"error": "student_id must be an integer."}), 400
    if not full_name or not email or not department:
        return jsonify({"error": "Full name, email, and department are required."}), 400

    try:
        call_sp(
            "dbo.sp_EditStudent_Profile",
            (u["Role"], u["UserID"], student_id, full_name, email, department),
        )
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


@app.get("/api/student/grades")
@login_required
@role_required("Student", "Admin")
def api_student_grades():
    u = session["user"]
    rows = call_sp("dbo.sp_ViewGrades", (u["Role"], u["UserID"]))
    return jsonify({"grades": rows})


@app.get("/api/student/attendance")
@login_required
@role_required("Student", "Admin")
def api_student_attendance():
    u = session["user"]
    rows = call_sp(
        "dbo.sp_ViewAttendance",
        (u["Role"], u["UserID"], u["ClearanceLevel"], None, None),
    )
    return jsonify({"attendance": rows})


@app.post("/api/student/role-request")
@login_required
@role_required("Student", "Admin")
def api_student_role_request():
    u = session["user"]
    data = request.get_json(force=True) or {}

    requested_role = (data.get("requested_role") or "").strip()
    reason = (data.get("reason") or "").strip()

    allowed = {"TA", "Instructor", "Admin"}
    if requested_role not in allowed:
        return jsonify({"error": "Invalid requested role."}), 400
    if len(reason) < 5:
        return jsonify({"error": "Please enter a reason (min 5 characters)."}), 400

    call_sp("dbo.sp_RequestRoleUpgrade", (u["Role"], u["UserID"], requested_role, reason))
    return jsonify({"ok": True})


# =========================================================
# TA GUI (Pages)
# =========================================================
@app.get("/ta")
@login_required
@role_required("TA", "Admin")
def ta_home():
    return render_template("ta_home.html")


@app.get("/ta/attendance")
@login_required
@role_required("TA", "Admin")
def ta_attendance_page():
    return render_template("ta_attendance.html")


@app.get("/ta/student-profile")
@login_required
@role_required("TA", "Admin")
def ta_student_profile_page():
    return render_template("ta_student_profile.html")


@app.get("/ta/role-request")
@login_required
@role_required("TA", "Admin")
def ta_role_request_page():
    return render_template("ta_role_request.html")


# =========================================================
# TA GUI (APIs)
# =========================================================
@app.get("/api/ta/attendance")
@login_required
@role_required("TA", "Admin")
def api_ta_view_attendance():
    u = session["user"]
    student_id = request.args.get("student_id")
    course_id = request.args.get("course_id")

    student_id = int(student_id) if student_id and student_id.isdigit() else None
    course_id = int(course_id) if course_id and course_id.isdigit() else None

    rows = call_sp(
        "dbo.sp_ViewAttendance",
        (u["Role"], u["UserID"], u["ClearanceLevel"], student_id, course_id),
    )
    return jsonify({"attendance": rows})


@app.post("/api/ta/attendance/record")
@login_required
@role_required("TA", "Admin")
def api_ta_record_attendance():
    u = session["user"]
    data = request.get_json(force=True) or {}

    student_id = data.get("student_id")
    course_id = data.get("course_id")
    status = data.get("status")

    if not isinstance(student_id, int) or not isinstance(course_id, int):
        return jsonify({"error": "student_id and course_id must be integers."}), 400
    if not isinstance(status, bool):
        return jsonify({"error": "status must be true/false."}), 400

    try:
        call_sp("dbo.sp_RecordAttendance", (u["Role"], u["UserID"], student_id, course_id, status))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


@app.get("/api/ta/student-profile")
@login_required
@role_required("TA", "Admin")
def api_ta_student_profile():
    u = session["user"]
    sid = request.args.get("student_id", "").strip()
    if not sid.isdigit():
        return jsonify({"error": "student_id is required and must be a number."}), 400

    sid_int = int(sid)
    rows = call_sp(
        "dbo.sp_ViewStudent_Profile",
        (u["Role"], u["UserID"], u["ClearanceLevel"], sid_int),
    )
    if not rows:
        return jsonify({"error": "No access or student not found."}), 404

    return jsonify({"profile": rows[0]})


@app.post("/api/ta/role-request")
@login_required
@role_required("TA", "Admin")
def api_ta_role_request():
    u = session["user"]
    data = request.get_json(force=True) or {}

    requested_role = (data.get("requested_role") or "").strip()
    reason = (data.get("reason") or "").strip()

    allowed = {"Instructor", "Admin"}
    if requested_role not in allowed:
        return jsonify({"error": "Invalid requested role."}), 400
    if len(reason) < 5:
        return jsonify({"error": "Please enter a reason (min 5 characters)."}), 400

    call_sp("dbo.sp_RequestRoleUpgrade", (u["Role"], u["UserID"], requested_role, reason))
    return jsonify({"ok": True})


# =========================================================
# Instructor GUI (Pages)
# =========================================================
@app.get("/instructor")
@login_required
@role_required("Instructor", "Admin")
def instructor_home():
    return render_template("instructor_home.html")


@app.get("/instructor/grades")
@login_required
@role_required("Instructor", "Admin")
def instructor_grades_page():
    return render_template("instructor_grades.html")


@app.get("/instructor/attendance")
@login_required
@role_required("Instructor", "Admin")
def instructor_attendance_page():
    return render_template("instructor_attendance.html")


@app.get("/instructor/student-profile")
@login_required
@role_required("Instructor", "Admin")
def instructor_student_profile_page():
    return render_template("instructor_student_profile.html")


# =========================================================
# Instructor GUI (APIs)
# =========================================================
@app.get("/api/instructor/grades")
@login_required
@role_required("Instructor", "Admin")
def api_instructor_view_grades():
    u = session["user"]
    rows = call_sp("dbo.sp_ViewGrades", (u["Role"], u["UserID"]))
    return jsonify({"grades": rows})


@app.post("/api/instructor/grades/insert")
@login_required
@role_required("Instructor", "Admin")
def api_instructor_insert_grade():
    u = session["user"]
    data = request.get_json(force=True) or {}

    student_id = data.get("student_id")
    course_id = data.get("course_id")
    grade = data.get("grade")

    if not isinstance(student_id, int) or not isinstance(course_id, int):
        return jsonify({"error": "student_id and course_id must be integers."}), 400
    if not isinstance(grade, (int, float)):
        return jsonify({"error": "grade must be a number."}), 400

    try:
        call_sp(
            "dbo.sp_InsertGrade",
            (u["Role"], u["UserID"], u["ClearanceLevel"], student_id, course_id, float(grade)),
        )
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


@app.post("/api/instructor/grades/publish")
@login_required
@role_required("Instructor", "Admin")
def api_instructor_publish_grade():
    u = session["user"]
    data = request.get_json(force=True) or {}

    grade_id = data.get("grade_id")
    publish = data.get("publish")

    if not isinstance(grade_id, int):
        return jsonify({"error": "grade_id must be an integer."}), 400
    if not isinstance(publish, bool):
        return jsonify({"error": "publish must be true/false."}), 400

    try:
        call_sp("dbo.sp_SetGradePublished", (u["Role"], grade_id, publish))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


@app.get("/api/instructor/attendance")
@login_required
@role_required("Instructor", "Admin")
def api_instructor_view_attendance():
    u = session["user"]
    student_id = request.args.get("student_id")
    course_id = request.args.get("course_id")

    student_id = int(student_id) if student_id and student_id.isdigit() else None
    course_id = int(course_id) if course_id and course_id.isdigit() else None

    rows = call_sp(
        "dbo.sp_ViewAttendance",
        (u["Role"], u["UserID"], u["ClearanceLevel"], student_id, course_id),
    )
    return jsonify({"attendance": rows})


@app.post("/api/instructor/attendance/record")
@login_required
@role_required("Instructor", "Admin")
def api_instructor_record_attendance():
    u = session["user"]
    data = request.get_json(force=True) or {}

    student_id = data.get("student_id")
    course_id = data.get("course_id")
    status = data.get("status")

    if not isinstance(student_id, int) or not isinstance(course_id, int):
        return jsonify({"error": "student_id and course_id must be integers."}), 400
    if not isinstance(status, bool):
        return jsonify({"error": "status must be true/false."}), 400

    try:
        call_sp("dbo.sp_RecordAttendance", (u["Role"], u["UserID"], student_id, course_id, status))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


@app.get("/api/instructor/student-profile")
@login_required
@role_required("Instructor", "Admin")
def api_instructor_student_profile():
    u = session["user"]
    sid = request.args.get("student_id", "").strip()
    if not sid.isdigit():
        return jsonify({"error": "student_id is required and must be a number."}), 400

    sid_int = int(sid)
    rows = call_sp(
        "dbo.sp_ViewStudent_Profile",
        (u["Role"], u["UserID"], u["ClearanceLevel"], sid_int),
    )
    if not rows:
        return jsonify({"error": "No access or student not found."}), 404

    return jsonify({"profile": rows[0]})


# =========================================================
# Admin GUI (Page)
# =========================================================
@app.get("/admin")
@login_required
@role_required("Admin")
def admin_home():
    return render_template("admin_home.html")


# =========================================================
# Admin - EXTRA APIs (Admin does everything in the table)
# =========================================================
@app.get("/api/admin/users")
@login_required
@role_required("Admin")
def api_admin_users():
    u = session["user"]
    rows = call_sp("dbo.sp_Admin_ListUsers", (u["Role"],))
    return jsonify({"users": rows})


@app.get("/api/admin/role-requests")
@login_required
@role_required("Admin")
def api_admin_role_requests():
    u = session["user"]
    rows = call_sp("dbo.sp_Admin_ListPendingRoleRequests", (u["Role"],))
    return jsonify({"requests": rows})


@app.post("/api/admin/role-requests/approve")
@login_required
@role_required("Admin")
def api_admin_role_requests_approve():
    u = session["user"]
    data = request.get_json(force=True) or {}
    request_id = data.get("request_id")

    if not isinstance(request_id, int):
        return jsonify({"error": "request_id must be an integer."}), 400

    try:
        call_sp("dbo.sp_Admin_ApproveRoleRequest", (u["Role"], request_id))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


@app.post("/api/admin/role-requests/deny")
@login_required
@role_required("Admin")
def api_admin_role_requests_deny():
    u = session["user"]
    data = request.get_json(force=True) or {}
    request_id = data.get("request_id")

    if not isinstance(request_id, int):
        return jsonify({"error": "request_id must be an integer."}), 400

    try:
        call_sp("dbo.sp_Admin_DenyRoleRequest", (u["Role"], request_id))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


# Admin view grades (same SP used)
@app.get("/api/admin/grades")
@login_required
@role_required("Admin")
def api_admin_view_grades():
    u = session["user"]
    rows = call_sp("dbo.sp_ViewGrades", (u["Role"], u["UserID"]))
    return jsonify({"grades": rows})


# Admin insert grade
@app.post("/api/admin/grades/insert")
@login_required
@role_required("Admin")
def api_admin_insert_grade():
    u = session["user"]
    data = request.get_json(force=True) or {}

    student_id = data.get("student_id")
    course_id = data.get("course_id")
    grade = data.get("grade")

    if not isinstance(student_id, int) or not isinstance(course_id, int):
        return jsonify({"error": "student_id and course_id must be integers."}), 400
    if not isinstance(grade, (int, float)):
        return jsonify({"error": "grade must be a number."}), 400

    try:
        call_sp(
            "dbo.sp_InsertGrade",
            (u["Role"], u["UserID"], u["ClearanceLevel"], student_id, course_id, float(grade)),
        )
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


# Admin publish grade
@app.post("/api/admin/grades/publish")
@login_required
@role_required("Admin")
def api_admin_publish_grade():
    u = session["user"]
    data = request.get_json(force=True) or {}
    grade_id = data.get("grade_id")
    publish = data.get("publish")

    if not isinstance(grade_id, int):
        return jsonify({"error": "grade_id must be an integer."}), 400
    if not isinstance(publish, bool):
        return jsonify({"error": "publish must be true/false."}), 400

    try:
        call_sp("dbo.sp_SetGradePublished", (u["Role"], grade_id, publish))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


# Admin view attendance
@app.get("/api/admin/attendance")
@login_required
@role_required("Admin")
def api_admin_view_attendance():
    u = session["user"]
    student_id = request.args.get("student_id")
    course_id = request.args.get("course_id")

    student_id = int(student_id) if student_id and student_id.isdigit() else None
    course_id = int(course_id) if course_id and course_id.isdigit() else None

    rows = call_sp(
        "dbo.sp_ViewAttendance",
        (u["Role"], u["UserID"], u["ClearanceLevel"], student_id, course_id),
    )
    return jsonify({"attendance": rows})


# Admin record attendance
@app.post("/api/admin/attendance/record")
@login_required
@role_required("Admin")
def api_admin_record_attendance():
    u = session["user"]
    data = request.get_json(force=True) or {}

    student_id = data.get("student_id")
    course_id = data.get("course_id")
    status = data.get("status")

    if not isinstance(student_id, int) or not isinstance(course_id, int):
        return jsonify({"error": "student_id and course_id must be integers."}), 400
    if not isinstance(status, bool):
        return jsonify({"error": "status must be true/false."}), 400

    try:
        call_sp("dbo.sp_RecordAttendance", (u["Role"], u["UserID"], student_id, course_id, status))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


# =========================================================
# Run
# =========================================================
if __name__ == "__main__":
    app.run(debug=True)
