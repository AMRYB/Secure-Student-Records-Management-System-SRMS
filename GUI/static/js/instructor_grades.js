const gradesBody = document.getElementById("gradesBody");
const insertMsg = document.getElementById("insertMsg");
const pubMsg = document.getElementById("pubMsg");

function setMsg(el, text, ok=false){
  el.textContent = text || "";
  el.className = "msg " + (ok ? "ok" : "err");
}

async function loadGrades(){
  const res = await fetch("/api/instructor/grades", { credentials: "include" });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) return;

  const items = data.grades || [];
  gradesBody.innerHTML = items.map(g => `
    <tr>
      <td>${g.GradeID}</td>
      <td>${g.StudentID}</td>
      <td>${g.CourseID}</td>
      <td>${g.Grade}</td>
      <td>${g.IsPublished ? "Yes" : "No"}</td>
      <td>${g.DateEntered ?? ""}</td>
      <td>${g.PublishedDate ?? ""}</td>
    </tr>
  `).join("");
}

document.getElementById("insertBtn")?.addEventListener("click", async () => {
  insertMsg.textContent = "";

  const student_id = Number(document.getElementById("studentId").value);
  const course_id = Number(document.getElementById("courseId").value);
  const grade = Number(document.getElementById("grade").value);

  if (!student_id || !course_id || Number.isNaN(grade)){
    return setMsg(insertMsg, "Please enter valid StudentID, CourseID and Grade.");
  }

  const res = await fetch("/api/instructor/grades/insert", {
    method: "POST",
    headers: {"Content-Type":"application/json"},
    credentials: "include",
    body: JSON.stringify({ student_id, course_id, grade })
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) return setMsg(insertMsg, data.error || "Insert failed.");

  setMsg(insertMsg, "Grade inserted ", true);
  await loadGrades();
});

document.getElementById("publishBtn")?.addEventListener("click", async () => {
  pubMsg.textContent = "";

  const grade_id = Number(document.getElementById("gradeId").value);
  const publish = document.getElementById("publish").value === "true";

  if (!grade_id) return setMsg(pubMsg, "Please enter a valid GradeID.");

  const res = await fetch("/api/instructor/grades/publish", {
    method: "POST",
    headers: {"Content-Type":"application/json"},
    credentials: "include",
    body: JSON.stringify({ grade_id, publish })
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) return setMsg(pubMsg, data.error || "Update failed.");

  setMsg(pubMsg, "Publish status updated ", true);
  await loadGrades();
});

loadGrades();
