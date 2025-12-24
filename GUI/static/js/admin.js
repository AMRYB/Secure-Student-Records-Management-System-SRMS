/* =========================
   Helpers
========================= */
function setMsg(text, ok = true) {
  const el = document.getElementById("dashMsg");
  el.textContent = text || "";
  el.classList.remove("ok", "err");
  if (text) el.classList.add(ok ? "ok" : "err");
}

function showSec(name, btn) {
  document.querySelectorAll(".dashSection").forEach(s => s.classList.add("hidden"));
  document.getElementById(`sec-${name}`).classList.remove("hidden");

  document.querySelectorAll(".dash__navItem").forEach(b => b.classList.remove("active"));
  if (btn) btn.classList.add("active");

  // Load section data when opened
  if (name === "profile") loadMe();
  if (name === "grades") loadGrades();
  if (name === "attendance") loadAttendance();
  if (name === "users") { loadUsers(); loadRequests(); }
  if (name === "public") loadPublicCourses();
}

/* Search filter for any table */
function filterTable(tableId, q) {
  q = (q || "").toLowerCase();
  const rows = document.querySelectorAll(`#${tableId} tbody tr`);
  rows.forEach(tr => {
    tr.style.display = tr.textContent.toLowerCase().includes(q) ? "" : "none";
  });
}

/* =========================
   BONUS: Block copy/print/save on Secret panels
   (best effort)
========================= */
function applySecretGuards() {
  const secretPanels = document.querySelectorAll(".secretPanel");

  // Disable selection (CSS-like via JS)
  secretPanels.forEach(p => {
    p.style.userSelect = "none";
    p.style.webkitUserSelect = "none";
    p.style.msUserSelect = "none";
  });

  // Block right click
  document.addEventListener("contextmenu", (e) => {
    if (e.target.closest(".secretPanel")) e.preventDefault();
  });

  // Block copy/cut/paste + Ctrl+C
  ["copy", "cut", "paste"].forEach(evt => {
    document.addEventListener(evt, (e) => {
      if (e.target.closest(".secretPanel")) {
        e.preventDefault();
        setMsg("Copy/Export is blocked on Secret panels.", false);
      }
    });
  });

  document.addEventListener("keydown", (e) => {
    const inSecret = document.activeElement?.closest?.(".secretPanel") || e.target.closest?.(".secretPanel");
    if (!inSecret) return;

    const k = e.key.toLowerCase();
    if ((e.ctrlKey || e.metaKey) && ["c", "x", "s", "p"].includes(k)) {
      e.preventDefault();
      setMsg("Copy/Save/Print is blocked on Secret panels.", false);
    }
    if (k === "printscreen") {
      // Can't fully block screenshots; best effort
      setMsg("Screenshots are not allowed for Secret panels.", false);
    }
  });
}

/* =========================
   Auth
========================= */
async function logout() {
  await fetch("/api/logout", { method: "POST" });
  window.location.href = "/login";
}

/* =========================
   Profile (View/Edit own)
========================= */
async function loadMe() {
  const res = await fetch("/api/me", { credentials: "include" });
  const data = await res.json();
  if (!res.ok || !data.ok) {
    setMsg(data.error || "Failed to load profile", false);
    return;
  }

  const p = data.profile || {};
  const d = p.data || {};

  document.getElementById("meLine").textContent = `${p.role || "Admin"} • Clearance ${p.clearance ?? "-"}`;

  document.getElementById("myFullName").value = d.FullName || "";
  document.getElementById("myEmail").value = d.Email || "";
  document.getElementById("myRole").value = p.role || "Admin";
}

async function saveMyProfile() {
  const full_name = document.getElementById("myFullName").value.trim();
  const email = document.getElementById("myEmail").value.trim();

  const msg = document.getElementById("profileMsg");
  msg.textContent = "";

  const res = await fetch("/api/me", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ full_name, email }),
    credentials: "include",
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.ok) {
    msg.textContent = data.error || "Failed to save profile";
    setMsg(msg.textContent, false);
    return;
  }

  msg.textContent = "Saved successfully.";
  setMsg("Profile updated.", true);
  loadMe();
}

/* =========================
   Manage Users (list)
========================= */
async function loadUsers() {
  const res = await fetch("/api/admin/users", { credentials: "include" });
  const data = await res.json();

  const tbody = document.querySelector("#usersTable tbody");
  tbody.innerHTML = "";

  if (!res.ok) {
    setMsg(data.error || "Failed to load users", false);
    return;
  }

  (data.users || []).forEach(u => {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${u.UserID}</td>
      <td>${u.Role}</td>
      <td>${u.ClearanceLevel}</td>
      <td>${u.StudentID ?? "-"}</td>
      <td>${u.InstructorID ?? "-"}</td>
    `;
    tbody.appendChild(tr);
  });

  document.getElementById("statUsers").textContent = (data.users || []).length;
}

/* =========================
   Role Requests (approve/deny)
========================= */
async function loadRequests() {
  const res = await fetch("/api/admin/role-requests", { credentials: "include" });
  const data = await res.json();

  const tbody = document.querySelector("#requestsTable tbody");
  tbody.innerHTML = "";

  if (!res.ok) {
    setMsg(data.error || "Failed to load role requests", false);
    return;
  }

  (data.requests || []).forEach(r => {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${r.RequestID}</td>
      <td>${r.UserID}</td>
      <td>${r.CurrentRole}</td>
      <td>${r.RequestedRole}</td>
      <td>${r.Reason}</td>
      <td>${r.RequestDate || "-"}</td>
      <td><span class="badge badge--pending">${r.Status}</span></td>
      <td>
        <button class="miniBtn" onclick="approveReq(${r.RequestID})">Approve</button>
        <button class="miniBtn danger" onclick="denyReq(${r.RequestID})">Deny</button>
      </td>
    `;
    tbody.appendChild(tr);
  });

  document.getElementById("statReq").textContent = (data.requests || []).length;
}

async function approveReq(id) {
  const res = await fetch("/api/admin/role-requests/approve", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ request_id: id }),
    credentials: "include",
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.ok) {
    setMsg(data.error || "Approve failed", false);
    return;
  }
  setMsg("Request approved.", true);
  loadUsers();
  loadRequests();
}

async function denyReq(id) {
  const res = await fetch("/api/admin/role-requests/deny", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ request_id: id }),
    credentials: "include",
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.ok) {
    setMsg(data.error || "Deny failed", false);
    return;
  }
  setMsg("Request denied.", true);
  loadRequests();
}

/* =========================
   Grades (view/edit)
========================= */
async function loadGrades() {
  const res = await fetch("/api/admin/grades", { credentials: "include" });
  const data = await res.json();

  const tbody = document.querySelector("#gradesTable tbody");
  tbody.innerHTML = "";

  if (!res.ok) {
    setMsg(data.error || "Failed to load grades", false);
    return;
  }

  const grades = data.grades || [];
  grades.forEach(g => {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${g.GradeID}</td>
      <td>${g.StudentID}</td>
      <td>${g.CourseID}</td>
      <td>${g.Grade ?? ""}</td>
      <td>${g.IsPublished ? "Yes" : "No"}</td>
      <td>${g.DateEntered || "-"}</td>
      <td>${g.PublishedDate || "-"}</td>
    `;
    tbody.appendChild(tr);
  });

  document.getElementById("statGrades").textContent = grades.length;
}

async function insertGrade() {
  const student_id = Number(document.getElementById("gStudent").value);
  const course_id = Number(document.getElementById("gCourse").value);
  const grade = Number(document.getElementById("gValue").value);

  const msg = document.getElementById("gradeInsertMsg");
  msg.textContent = "";

  const res = await fetch("/api/admin/grades/insert", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ student_id, course_id, grade }),
    credentials: "include",
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.ok) {
    msg.textContent = data.error || "Insert failed";
    setMsg(msg.textContent, false);
    return;
  }

  msg.textContent = "Inserted.";
  setMsg("Grade inserted.", true);
  loadGrades();
}

async function publishGrade() {
  const grade_id = Number(document.getElementById("pubGradeId").value);
  const publish = document.getElementById("pubFlag").value === "true";

  const msg = document.getElementById("gradePublishMsg");
  msg.textContent = "";

  const res = await fetch("/api/admin/grades/publish", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ grade_id, publish }),
    credentials: "include",
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.ok) {
    msg.textContent = data.error || "Publish failed";
    setMsg(msg.textContent, false);
    return;
  }

  msg.textContent = "Applied.";
  setMsg("Publish flag updated.", true);
  loadGrades();
}

/* =========================
   Attendance (view/edit)
========================= */
async function loadAttendance() {
  const sid = document.getElementById("attFilterStudent").value.trim();
  const cid = document.getElementById("attFilterCourse").value.trim();

  const qs = new URLSearchParams();
  if (sid) qs.set("student_id", sid);
  if (cid) qs.set("course_id", cid);

  const res = await fetch(`/api/admin/attendance?${qs.toString()}`, { credentials: "include" });
  const data = await res.json();

  const tbody = document.querySelector("#attTable tbody");
  tbody.innerHTML = "";

  if (!res.ok) {
    setMsg(data.error || "Failed to load attendance", false);
    return;
  }

  (data.attendance || []).forEach(a => {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${a.AttendanceID}</td>
      <td>${a.StudentID}</td>
      <td>${a.CourseID}</td>
      <td>${a.Status ? "Present" : "Absent"}</td>
      <td>${a.DateRecorded || "-"}</td>
      <td>${a.RecordedByUserID ?? "-"}</td>
    `;
    tbody.appendChild(tr);
  });
}

async function recordAttendance() {
  const student_id = Number(document.getElementById("aStudent").value);
  const course_id = Number(document.getElementById("aCourse").value);
  const status = document.getElementById("aStatus").value === "true";

  const msg = document.getElementById("attMsg");
  msg.textContent = "";

  const res = await fetch("/api/admin/attendance/record", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ student_id, course_id, status }),
    credentials: "include",
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.ok) {
    msg.textContent = data.error || "Record failed";
    setMsg(msg.textContent, false);
    return;
  }

  msg.textContent = "Recorded.";
  setMsg("Attendance recorded.", true);
  loadAttendance();
}

/* =========================
   Public Courses (view)
========================= */
async function loadPublicCourses() {
  const res = await fetch("/api/courses/public", { credentials: "include" });
  const data = await res.json();

  const tbody = document.querySelector("#publicTable tbody");
  tbody.innerHTML = "";

  if (!res.ok) {
    setMsg(data.error || "Failed to load public courses", false);
    return;
  }

  (data.courses || []).forEach(c => {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${c.CourseID}</td>
      <td>${c.CourseName}</td>
      <td>${c.PublicInfo || ""}</td>
    `;
    tbody.appendChild(tr);
  });
}

/* =========================
   Refresh all
========================= */
async function refreshAll() {
  setMsg("Refreshing...", true);
  await Promise.allSettled([loadMe(), loadUsers(), loadRequests(), loadGrades(), loadAttendance(), loadPublicCourses()]);
  setMsg("Updated.", true);
}

/* =========================
   Init
========================= */
document.addEventListener("DOMContentLoaded", async () => {
  applySecretGuards();
  await refreshAll();
});
