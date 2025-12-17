// static/js/admin.js

async function apiFetch(path, { method = "GET", body = null } = {}) {
  const opts = {
    method,
    headers: { "Content-Type": "application/json" },
    credentials: "include",
  };
  if (body !== null) opts.body = JSON.stringify(body);

  const res = await fetch(path, opts);
  const data = await res.json().catch(() => null);

  if (!res.ok || !data?.ok) throw new Error(data?.error || `Request failed (HTTP ${res.status})`);
  return data;
}

function escapeHtml(s) {
  return String(s ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function setMsg(text, ok = false) {
  const el = document.getElementById("globalMsg");
  el.textContent = text || "";
  el.classList.toggle("ok", !!ok);
  el.classList.toggle("err", !ok);
  if (!text) { el.classList.remove("ok"); el.classList.remove("err"); }
}

async function ensureAdmin() {
  try {
    const data = await apiFetch("/api/me");
    const u = data.user;

    document.getElementById("meName").textContent = u.username ?? "-";
    document.getElementById("meRole").textContent = u.role ?? "-";
    document.getElementById("meClr").textContent = u.clearance ?? "-";

    if (u.role !== "Admin") {
      window.location.href = "/login";
      return false;
    }
    return true;
  } catch {
    window.location.href = "/login";
    return false;
  }
}

async function logout() {
  try { await apiFetch("/api/logout", { method: "POST" }); } catch {}
  window.location.href = "/login";
}

/* ---------- Sections ---------- */
function showSection(key) {
  document.querySelectorAll(".dash__navItem").forEach(btn => {
    btn.classList.toggle("active", btn.dataset.section === key);
  });

  document.getElementById("section-users").classList.toggle("hidden", key !== "users");
  document.getElementById("section-requests").classList.toggle("hidden", key !== "requests");
  document.getElementById("section-audit").classList.toggle("hidden", key !== "audit");
}

/* ---------- Stats ---------- */
function setStats({ users = null, requests = null, audit = null } = {}) {
  if (users !== null) document.getElementById("statUsers").textContent = String(users);
  if (requests !== null) document.getElementById("statRequests").textContent = String(requests);
  if (audit !== null) document.getElementById("statAudit").textContent = String(audit);
}

/* ---------- Users ---------- */
let allUsersCache = [];

function renderUsersTable(list) {
  const tbody = document.querySelector("#usersTable tbody");
  tbody.innerHTML = "";

  if (!list.length) {
    tbody.innerHTML = `<tr><td colspan="6">No users found.</td></tr>`;
    return;
  }

  for (const r of list) {
    const username = r.Username ?? r.username ?? "";
    const role = r.Role ?? r.role ?? "";
    const clearance = r.ClearanceLevel ?? r.clearance ?? r.Clearance ?? "";
    const studentPk = r.Student_PK_ID ?? r.student_pk_id ?? "";
    const instructorId = r.InstructorID ?? r.instructor_id ?? "";

    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${escapeHtml(username)}</td>
      <td>${escapeHtml(role)}</td>
      <td>${escapeHtml(clearance)}</td>
      <td>${escapeHtml(studentPk)}</td>
      <td>${escapeHtml(instructorId)}</td>
      <td>
        <div class="inlineCtl">
          <select class="miniSelect" data-role>
            <option value="Admin" ${role === "Admin" ? "selected" : ""}>Admin</option>
            <option value="Instructor" ${role === "Instructor" ? "selected" : ""}>Instructor</option>
            <option value="TA" ${role === "TA" ? "selected" : ""}>TA</option>
            <option value="Student" ${role === "Student" ? "selected" : ""}>Student</option>
            <option value="Guest" ${role === "Guest" ? "selected" : ""}>Guest</option>
          </select>

          <input class="miniInput" data-clr type="number" min="0" max="3" value="${escapeHtml(clearance)}" />
          <button class="miniBtn" data-save>Save</button>
        </div>
      </td>
    `;

    const saveBtn = tr.querySelector("[data-save]");
    const roleSel = tr.querySelector("[data-role]");
    const clrInp = tr.querySelector("[data-clr]");

    saveBtn.addEventListener("click", async () => {
      setMsg("");
      const newRole = roleSel.value;
      const clrVal = clrInp.value.trim();
      const payload = { role: newRole };
      if (clrVal !== "") payload.clearance = Number(clrVal);

      try {
        await apiFetch(`/api/admin/users/${encodeURIComponent(username)}/role`, {
          method: "POST",
          body: payload,
        });
        setMsg("User updated successfully.", true);
        await loadUsers();
      } catch (e) {
        setMsg(e.message || "Failed to update user.");
      }
    });

    tbody.appendChild(tr);
  }
}

async function loadUsers() {
  setMsg("");
  const data = await apiFetch("/api/admin/users");
  allUsersCache = data.rows || [];
  setStats({ users: allUsersCache.length });

  const q = (document.getElementById("userSearch").value || "").trim().toLowerCase();
  const filtered = !q ? allUsersCache : allUsersCache.filter(u =>
    String(u.Username ?? u.username ?? "").toLowerCase().includes(q)
  );

  renderUsersTable(filtered);
}

async function createUser(e) {
  e.preventDefault();
  const msg = document.getElementById("createMsg");
  msg.textContent = "";
  msg.style.color = "#555";

  const username = document.getElementById("cu_username").value.trim();
  const password = document.getElementById("cu_password").value;
  const role = document.getElementById("cu_role").value;

  const clearance = document.getElementById("cu_clearance").value.trim();
  const student_pk_id = document.getElementById("cu_student_pk_id").value.trim();
  const instructor_id = document.getElementById("cu_instructor_id").value.trim();

  const payload = { username, password, role };
  if (clearance !== "") payload.clearance = Number(clearance);
  if (student_pk_id !== "") payload.student_pk_id = Number(student_pk_id);
  if (instructor_id !== "") payload.instructor_id = Number(instructor_id);

  try {
    await apiFetch("/api/admin/users", { method: "POST", body: payload });
    msg.style.color = "#0b6b2f";
    msg.textContent = "Created successfully.";
    e.target.reset();
    await loadUsers();
  } catch (err) {
    msg.style.color = "#b00020";
    msg.textContent = err.message || "Failed to create user.";
  }
}

/* ---------- Requests ---------- */
async function loadRequests() {
  setMsg("");
  const data = await apiFetch("/api/admin/role-requests/pending");
  const rows = data.rows || [];
  setStats({ requests: rows.length });

  const tbody = document.querySelector("#reqTable tbody");
  tbody.innerHTML = "";

  if (!rows.length) {
    tbody.innerHTML = `<tr><td colspan="7">No pending requests.</td></tr>`;
    return;
  }

  for (const r of rows) {
    const requestId = r.RequestID ?? r.request_id;
    const username = r.Username ?? r.username;
    const currentRole = r.CurrentRole ?? r.current_role;
    const requestedRole = r.RequestedRole ?? r.requested_role;
    const reason = r.Reason ?? r.reason;
    const status = r.Status ?? r.status;

    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${escapeHtml(requestId)}</td>
      <td>${escapeHtml(username)}</td>
      <td>${escapeHtml(currentRole)}</td>
      <td>${escapeHtml(requestedRole)}</td>
      <td>${escapeHtml(reason)}</td>
      <td>${escapeHtml(status)}</td>
      <td>
        <div class="inlineCtl">
          <input class="miniInput" data-comment placeholder="comments (optional)" />
          <button class="miniBtn" data-approve>Approve</button>
          <button class="miniBtn danger" data-deny>Deny</button>
        </div>
      </td>
    `;

    const approveBtn = tr.querySelector("[data-approve]");
    const denyBtn = tr.querySelector("[data-deny]");
    const commentInp = tr.querySelector("[data-comment]");

    approveBtn.addEventListener("click", async () => {
      setMsg("");
      try {
        await apiFetch(`/api/admin/role-requests/${requestId}/approve`, {
          method: "POST",
          body: { comments: commentInp.value.trim() || null },
        });
        setMsg("Request approved.", true);
        await loadRequests();
        await loadUsers();
      } catch (e) {
        setMsg(e.message || "Approve failed.");
      }
    });

    denyBtn.addEventListener("click", async () => {
      setMsg("");
      try {
        await apiFetch(`/api/admin/role-requests/${requestId}/deny`, {
          method: "POST",
          body: { comments: commentInp.value.trim() || null },
        });
        setMsg("Request denied.", true);
        await loadRequests();
      } catch (e) {
        setMsg(e.message || "Deny failed.");
      }
    });

    tbody.appendChild(tr);
  }
}

/* ---------- Audit ---------- */
async function loadAudit() {
  setMsg("");
  const limit = Number(document.getElementById("auditLimit").value || 100);

  const data = await apiFetch(`/api/admin/audit?limit=${encodeURIComponent(limit)}`);
  const rows = data.rows || [];
  setStats({ audit: rows.length });

  const tbody = document.querySelector("#auditTable tbody");
  tbody.innerHTML = "";

  if (!rows.length) {
    tbody.innerHTML = `<tr><td colspan="6">No audit logs.</td></tr>`;
    return;
  }

  for (const r of rows) {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${escapeHtml(r.LogID ?? r.log_id)}</td>
      <td>${escapeHtml(r.Username ?? r.username)}</td>
      <td>${escapeHtml(r.Action ?? r.action)}</td>
      <td>${escapeHtml(r.TableName ?? r.table_name)}</td>
      <td>${escapeHtml(r.RecordID ?? r.record_id)}</td>
      <td>${escapeHtml(r.Timestamp ?? r.timestamp)}</td>
    `;
    tbody.appendChild(tr);
  }
}

/* ---------- Wire up ---------- */
document.getElementById("logoutBtn").addEventListener("click", logout);

document.querySelectorAll(".dash__navItem").forEach(btn => {
  btn.addEventListener("click", () => {
    showSection(btn.dataset.section);
    setMsg("");
  });
});

document.getElementById("createUserForm").addEventListener("submit", createUser);
document.getElementById("refreshUsersBtn").addEventListener("click", loadUsers);
document.getElementById("refreshReqBtn").addEventListener("click", loadRequests);
document.getElementById("refreshAuditBtn").addEventListener("click", loadAudit);

document.getElementById("userSearch").addEventListener("input", () => {
  const q = (document.getElementById("userSearch").value || "").trim().toLowerCase();
  const filtered = !q ? allUsersCache : allUsersCache.filter(u =>
    String(u.Username ?? u.username ?? "").toLowerCase().includes(q)
  );
  renderUsersTable(filtered);
});

document.getElementById("auditLimit").addEventListener("change", loadAudit);

/* ---------- Init ---------- */
(async () => {
  const ok = await ensureAdmin();
  if (!ok) return;

  setStats({ users: 0, requests: 0, audit: 0 });
  showSection("users");

  // Load all (so stats show immediately)
  try { await loadUsers(); } catch (e) { setMsg(e.message || "Failed to load users."); }
  try { await loadRequests(); } catch (e) { setMsg(e.message || "Failed to load requests."); }
  try { await loadAudit(); } catch (e) { setMsg(e.message || "Failed to load audit."); }
})();
