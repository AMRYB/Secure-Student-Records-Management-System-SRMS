const tableBody = document.querySelector("#coursesTable tbody");
const msgEl = document.getElementById("msg");
const logoutBtn = document.getElementById("logoutBtn");

function setMsg(text, type = "info") {
  if (!msgEl) return;
  msgEl.textContent = text || "";
  msgEl.className = "page__msg " + (type ? `is-${type}` : "");
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
  setMsg("Loading courses...", "info");
  try {
    const res = await fetch("/api/courses/public");
    const data = await res.json();

    if (!res.ok) {
      setMsg(data?.error || "Failed to load courses.", "error");
      return;
    }

    const courses = data.courses || [];
    if (!tableBody) return;

    tableBody.innerHTML = courses
      .map(
        (c) => `
        <tr>
          <td>${escapeHtml(c.CourseID)}</td>
          <td>${escapeHtml(c.CourseName)}</td>
          <td>${escapeHtml(c.PublicInfo)}</td>
        </tr>
      `
      )
      .join("");

    setMsg(courses.length ? "" : "No public courses found.", courses.length ? "success" : "info");
  } catch (e) {
    setMsg("Server error while loading courses.", "error");
  }
}

if (logoutBtn) {
  logoutBtn.addEventListener("click", async () => {
    try {
      await fetch("/api/logout", { method: "POST" });
    } catch (_) {}
    window.location.href = "/login";
  });
}

loadCourses();
