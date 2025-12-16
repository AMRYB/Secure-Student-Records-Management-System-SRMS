
async function apiFetch(path, { method = "GET", body = null } = {}) {
  const opts = {
    method,
    headers: { "Content-Type": "application/json" },
    credentials: "include",
  };
  if (body !== null) opts.body = JSON.stringify(body);

  const res = await fetch(path, opts);
  const data = await res.json().catch(() => null);

  if (!res.ok || !data?.ok) {
    throw new Error(data?.error || `Request failed (HTTP ${res.status})`);
  }
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

async function loadCourses() {
  const msg = document.getElementById("msg");
  const tbody = document.querySelector("#coursesTable tbody");

  msg.textContent = "";
  tbody.innerHTML = "";

  try {
    const data = await apiFetch("/api/public/courses");
    const rows = data.rows || [];

    if (rows.length === 0) {
      msg.textContent = "No public courses found.";
      return;
    }

    for (const r of rows) {
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td>${escapeHtml(r.CourseID)}</td>
        <td>${escapeHtml(r.CourseName)}</td>
        <td>${escapeHtml(r.PublicInfo)}</td>
      `;
      tbody.appendChild(tr);
    }
  } catch (e) {
    msg.textContent = e.message || "Failed to load courses";
  }
}

async function doLogout() {
  try {
    await apiFetch("/api/logout", { method: "POST" });
  } catch {
    // حتى لو فشل، رجّع المستخدم للوجين
  }
  window.location.href = "/login";
}

document.getElementById("logoutBtn").addEventListener("click", doLogout);

// load on open
loadCourses();
