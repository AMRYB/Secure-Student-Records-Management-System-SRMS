const body = document.getElementById("attBody");
const msg = document.getElementById("msg");
function setMsg(t){ msg.textContent = t || ""; }

fetch("/api/student/attendance", { credentials: "include" })
  .then(r => r.json())
  .then(data => {
    const items = data.attendance || [];
    if (!items.length) setMsg("No attendance records found.");

    body.innerHTML = items.map(a => `
      <tr>
        <td>${a.AttendanceID}</td>
        <td>${a.CourseID}</td>
        <td>${a.Status ? "Present" : "Absent"}</td>
        <td>${a.DateRecorded ?? ""}</td>
      </tr>
    `).join("");
  })
  .catch(() => setMsg("Error loading attendance."));
