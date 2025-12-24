const body = document.getElementById("gradesBody");
const msg = document.getElementById("msg");
function setMsg(t){ msg.textContent = t || ""; }

fetch("/api/student/grades", { credentials: "include" })
  .then(r => r.json())
  .then(data => {
    const grades = data.grades || [];
    if (!grades.length) setMsg("No published grades yet.");

    body.innerHTML = grades.map(g => `
      <tr>
        <td>${g.GradeID}</td>
        <td>${g.CourseID}</td>
        <td>${g.Grade}</td>
        <td>${g.IsPublished ? "Yes" : "No"}</td>
        <td>${g.PublishedDate ?? ""}</td>
      </tr>
    `).join("");
  })
  .catch(() => setMsg("Error loading grades."));
