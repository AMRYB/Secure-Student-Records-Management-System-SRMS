from flask import Flask, request, jsonify, session, render_template
from config import Config

from db.connection import get_connection, set_session_context
from db.procedures import (
    sp_login,
    get_public_courses,

    sp_get_student_profile,
    vw_student_own_data,
    sp_submit_role_request,

    vw_instructor_students,
    sp_add_student,
    sp_add_grade,
    sp_get_grades,
    sp_get_aggregate_grades,

    vw_ta_assigned_students,
    list_attendance_for_ta,
    sp_update_attendance,

    sp_get_pending_requests,
    sp_approve_request,
    sp_deny_request,
    get_audit_logs,

    sp_admin_list_users,
    sp_admin_create_user,
    sp_admin_update_user_role,
)


def create_app() -> Flask:
    app = Flask(__name__, template_folder="templates", static_folder="static")
    app.config.from_object(Config)

    # =========================================================
    # Pages (GUI)
    # =========================================================
    @app.get("/")
    def home():
        return render_template("login.html")
    
    @app.get("/guest")
    def page_guest():
        return render_template("guest.html")

    @app.get("/login")
    def page_login():
        return render_template("login.html")

    @app.get("/admin")
    def page_admin():
        return render_template("admin.html")

    @app.get("/student")
    def page_student():
        return render_template("student.html")

    @app.get("/ta")
    def page_ta():
        return render_template("ta.html")

    @app.get("/instructor")
    def page_instructor():
        return render_template("instructor.html")

    # =========================================================
    # Health
    # =========================================================
    @app.get("/health")
    def health():
        return jsonify({"ok": True})

    # =========================================================
    # Auth
    # =========================================================
    @app.post("/api/login")
    def api_login():
        data = request.get_json(silent=True) or {}
        username = (data.get("username") or "").strip()
        password = data.get("password") or ""

        if not username or not password:
            return jsonify({"ok": False, "error": "Missing username/password"}), 400

        conn = get_connection()
        try:
            user = sp_login(conn, username, password)
            if not user:
                session.clear()
                return jsonify({"ok": False, "error": "Invalid credentials"}), 401

            session["username"] = user["username"]
            session["role"] = user["role"]
            session["clearance"] = user["clearance"]
            session["student_pk_id"] = user["student_pk_id"]
            session["instructor_id"] = user["instructor_id"]

            return jsonify({"ok": True, "user": user})
        finally:
            conn.close()

    @app.post("/api/logout")
    def api_logout():
        session.clear()
        return jsonify({"ok": True})

    @app.get("/api/me")
    def api_me():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401

        return jsonify({
            "ok": True,
            "user": {
                "username": session.get("username"),
                "role": session.get("role"),
                "clearance": session.get("clearance"),
                "student_pk_id": session.get("student_pk_id"),
                "instructor_id": session.get("instructor_id"),
            }
        })

    # =========================================================
    # Public
    # =========================================================
    @app.get("/api/public/courses")
    def api_public_courses():
        conn = get_connection()
        try:
            rows = get_public_courses(conn)
            return jsonify({"ok": True, "rows": rows})
        finally:
            conn.close()

    # =========================================================
    # Role Requests (Student/TA/Instructor allowed by SP)
    # =========================================================
    @app.post("/api/role-requests")
    def api_submit_role_request():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401

        data = request.get_json(silent=True) or {}
        requested_role = (data.get("requested_role") or "").strip()
        reason = (data.get("reason") or "").strip()

        if not requested_role or not reason:
            return jsonify({"ok": False, "error": "Missing requested_role/reason"}), 400

        conn = get_connection()
        try:
            sp_submit_role_request(conn, session["username"], requested_role, reason)
            return jsonify({"ok": True})
        finally:
            conn.close()

    # =========================================================
    # Student
    # =========================================================
    @app.get("/api/student/profile")
    def api_student_profile():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") != "Student":
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        conn = get_connection()
        try:
            set_session_context(conn)
            rows = sp_get_student_profile(conn)
            return jsonify({"ok": True, "rows": rows})
        finally:
            conn.close()

    @app.get("/api/student/own-data")
    def api_student_own_data():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") != "Student":
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        conn = get_connection()
        try:
            rows = vw_student_own_data(conn)
            return jsonify({"ok": True, "rows": rows})
        finally:
            conn.close()

    # =========================================================
    # Instructor
    # =========================================================
    @app.get("/api/instructor/students")
    def api_instructor_students():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") not in ("Instructor", "Admin"):
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        conn = get_connection()
        try:
            set_session_context(conn)
            rows = vw_instructor_students(conn)
            return jsonify({"ok": True, "rows": rows})
        finally:
            conn.close()

    @app.post("/api/instructor/students")
    def api_instructor_add_student():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") not in ("Instructor", "Admin"):
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        data = request.get_json(silent=True) or {}
        required = ["student_id", "full_name", "email", "phone", "dob", "department"]
        for k in required:
            v = data.get(k)
            if v is None or str(v).strip() == "":
                return jsonify({"ok": False, "error": f"Missing {k}"}), 400

        classification = int(data.get("classification", 1))

        conn = get_connection()
        try:
            sp_add_student(
                conn,
                student_id_input=str(data["student_id"]),
                full_name=str(data["full_name"]),
                email=str(data["email"]),
                phone=str(data["phone"]),
                dob=str(data["dob"]),  # YYYY-MM-DD
                department=str(data["department"]),
                classification=classification,
                requester_username=session["username"],
            )
            return jsonify({"ok": True})
        finally:
            conn.close()

    @app.post("/api/instructor/grades")
    def api_instructor_add_grade():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") not in ("Instructor", "Admin"):
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        data = request.get_json(silent=True) or {}
        for k in ["student_pk_id", "course_id", "grade_value"]:
            if data.get(k) is None:
                return jsonify({"ok": False, "error": f"Missing {k}"}), 400

        conn = get_connection()
        try:
            sp_add_grade(
                conn,
                student_pk_id=int(data["student_pk_id"]),
                course_id=int(data["course_id"]),
                grade_value=float(data["grade_value"]),
                instructor_username=session["username"],
            )
            return jsonify({"ok": True})
        finally:
            conn.close()

    @app.get("/api/instructor/grades")
    def api_instructor_get_grades():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") not in ("Instructor", "Admin"):
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        course_id = request.args.get("course_id", type=int)
        if not course_id:
            return jsonify({"ok": False, "error": "Missing course_id"}), 400

        conn = get_connection()
        try:
            set_session_context(conn)
            rows = sp_get_grades(conn, course_id)
            return jsonify({"ok": True, "rows": rows})
        finally:
            conn.close()

    @app.get("/api/instructor/grades/aggregate")
    def api_instructor_get_aggregate():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") not in ("Instructor", "Admin"):
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        course_id = request.args.get("course_id", type=int)
        if not course_id:
            return jsonify({"ok": False, "error": "Missing course_id"}), 400

        conn = get_connection()
        try:
            set_session_context(conn)
            rows = sp_get_aggregate_grades(conn, course_id)
            return jsonify({"ok": True, "rows": rows})
        finally:
            conn.close()

    # =========================================================
    # TA
    # =========================================================
    @app.get("/api/ta/students")
    def api_ta_students():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") != "TA":
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        conn = get_connection()
        try:
            set_session_context(conn)
            rows = vw_ta_assigned_students(conn)
            return jsonify({"ok": True, "rows": rows})
        finally:
            conn.close()

    @app.get("/api/ta/attendance")
    def api_ta_attendance_list():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") != "TA":
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        course_id = request.args.get("course_id", type=int)
        if not course_id:
            return jsonify({"ok": False, "error": "Missing course_id"}), 400

        conn = get_connection()
        try:
            rows = list_attendance_for_ta(conn, course_id, session["username"])
            return jsonify({"ok": True, "rows": rows})
        finally:
            conn.close()

    @app.post("/api/ta/attendance/update")
    def api_ta_attendance_update():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") != "TA":
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        data = request.get_json(silent=True) or {}
        if data.get("attendance_id") is None or data.get("new_status") is None:
            return jsonify({"ok": False, "error": "Missing attendance_id/new_status"}), 400

        conn = get_connection()
        try:
            sp_update_attendance(
                conn,
                attendance_id=int(data["attendance_id"]),
                new_status=bool(data["new_status"]),
                ta_username=session["username"],
            )
            return jsonify({"ok": True})
        finally:
            conn.close()

    # =========================================================
    # Admin - Role Requests
    # =========================================================
    @app.get("/api/admin/role-requests/pending")
    def api_admin_pending_requests():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") != "Admin":
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        conn = get_connection()
        try:
            rows = sp_get_pending_requests(conn, session["username"])
            return jsonify({"ok": True, "rows": rows})
        finally:
            conn.close()

    @app.post("/api/admin/role-requests/<int:request_id>/approve")
    def api_admin_approve_request(request_id: int):
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") != "Admin":
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        data = request.get_json(silent=True) or {}
        comments = data.get("comments")

        conn = get_connection()
        try:
            sp_approve_request(conn, request_id, session["username"], comments)
            return jsonify({"ok": True})
        finally:
            conn.close()

    @app.post("/api/admin/role-requests/<int:request_id>/deny")
    def api_admin_deny_request(request_id: int):
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") != "Admin":
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        data = request.get_json(silent=True) or {}
        comments = data.get("comments")

        conn = get_connection()
        try:
            sp_deny_request(conn, request_id, session["username"], comments)
            return jsonify({"ok": True})
        finally:
            conn.close()

    @app.get("/api/admin/audit")
    def api_admin_audit():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") != "Admin":
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        limit = request.args.get("limit", default=200, type=int)

        conn = get_connection()
        try:
            rows = get_audit_logs(conn, limit=limit)
            return jsonify({"ok": True, "rows": rows})
        finally:
            conn.close()

    # =========================================================
    # Admin - Users Management
    # Requires SQL SPs:
    #   sp_AdminListUsers
    #   sp_AdminCreateUser
    #   sp_AdminUpdateUserRole
    # =========================================================
    @app.get("/api/admin/users")
    def api_admin_list_users():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") != "Admin":
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        conn = get_connection()
        try:
            rows = sp_admin_list_users(conn, session["username"])
            return jsonify({"ok": True, "rows": rows})
        finally:
            conn.close()

    @app.post("/api/admin/users")
    def api_admin_create_user():
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") != "Admin":
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        data = request.get_json(silent=True) or {}
        new_username = (data.get("username") or "").strip()
        new_password = data.get("password") or ""
        new_role = (data.get("role") or "").strip()

        # optional
        clearance = data.get("clearance")
        student_pk_id = data.get("student_pk_id")
        instructor_id = data.get("instructor_id")

        if not new_username or not new_password or not new_role:
            return jsonify({"ok": False, "error": "Missing username/password/role"}), 400

        conn = get_connection()
        try:
            sp_admin_create_user(
                conn,
                admin_username=session["username"],
                new_username=new_username,
                new_password=new_password,
                new_role=new_role,
                clearance_level=clearance,
                student_pk_id=student_pk_id,
                instructor_id=instructor_id,
            )
            return jsonify({"ok": True})
        finally:
            conn.close()

    @app.post("/api/admin/users/<username>/role")
    def api_admin_update_user_role(username: str):
        if "username" not in session:
            return jsonify({"ok": False, "error": "Not logged in"}), 401
        if session.get("role") != "Admin":
            return jsonify({"ok": False, "error": "Forbidden"}), 403

        data = request.get_json(silent=True) or {}
        new_role = (data.get("role") or "").strip()
        new_clearance = data.get("clearance")

        if not new_role:
            return jsonify({"ok": False, "error": "Missing role"}), 400

        conn = get_connection()
        try:
            sp_admin_update_user_role(
                conn,
                admin_username=session["username"],
                target_username=username,
                new_role=new_role,
                new_clearance=new_clearance,
            )
            return jsonify({"ok": True})
        finally:
            conn.close()

    return app


if __name__ == "__main__":
    app = create_app()
    app.run(debug=True)
