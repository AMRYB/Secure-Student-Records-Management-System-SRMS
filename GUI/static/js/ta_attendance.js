const recordMsg = document.getElementById("recordMsg");
const loadMsg = document.getElementById("loadMsg");
const attBody = document.getElementById("attBody");

function setMsg(el, text, ok=false){
  el.textContent = text || "";
  el.className = "msg " + (ok ? "ok" : "err");
}

async function recordAttendance(){
  recordMsg.textContent = "";

  const student_id = Number(document.getElementById("studentId").value);
  const course_id = Number(document.getElementById("courseId").value);
  const status = document.getElementById("status").value === "true";

  if (!student_id || !course_id){
    setMsg(recordMsg, "Please enter valid StudentID and CourseID.");
    return;
  }

  const res = await fetch("/api/ta/attendance/record", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "include",
    body: JSON.stringify({ student_id, course_id, status })
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) return setMsg(recordMsg, data.error || "Failed to record attendance.");

  setMsg(recordMsg, "Attendance recorded successfully ", true);
}

async function loadAttendance(){
  loadMsg.textContent = "";
  attBody.innerHTML = "";

  const fs = document.getElementById("filterStudentId").value.trim();
  const fc = document.getElementById("filterCourseId").value.trim();

  const params = new URLSearchParams();
  if (fs) params.set("student_id", fs);
  if (fc) params.set("course_id", fc);

  const res = await fetch(`/api/ta/attendance?${params.toString()}`, { credentials: "include" });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) return setMsg(loadMsg, data.error || "Failed to load attendance.");

  const items = data.attendance || [];
  if (!items.length) setMsg(loadMsg, "No attendance records found.", true);

  attBody.innerHTML = items.map(a => `
    <tr>
      <td>${a.AttendanceID}</td>
      <td>${a.StudentID}</td>
      <td>${a.CourseID}</td>
      <td>${a.Status ? "Present" : "Absent"}</td>
      <td>${a.DateRecorded ?? ""}</td>
    </tr>
  `).join("");
}

document.getElementById("recordBtn")?.addEventListener("click", recordAttendance);
document.getElementById("loadBtn")?.addEventListener("click", loadAttendance);

loadAttendance();
