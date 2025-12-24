const msg = document.getElementById("msg");

function setMsg(text, ok=false){
  msg.textContent = text || "";
  msg.className = "msg " + (ok ? "ok" : "err");
}

function setOut(id, val){
  document.getElementById(id).textContent = val ?? "-";
}

document.getElementById("searchBtn")?.addEventListener("click", async () => {
  setMsg("");
  const sid = document.getElementById("sid").value.trim();
  if (!sid) return setMsg("Please enter StudentID.");

  const res = await fetch(`/api/instructor/student-profile?student_id=${encodeURIComponent(sid)}`, { credentials: "include" });
  const data = await res.json().catch(() => ({}));

  if (!res.ok){
    setOut("outId","-"); setOut("outName","-"); setOut("outEmail","-");
    setOut("outDob","-"); setOut("outDept","-"); setOut("outCl","-");
    return setMsg(data.error || "No access or student not found.");
  }

  const p = data.profile;
  setOut("outId", p.StudentID);
  setOut("outName", p.FullName);
  setOut("outEmail", p.Email);
  setOut("outDob", p.DOB);
  setOut("outDept", p.Department);
  setOut("outCl", p.ClearanceLevel);

  setMsg("Profile loaded ", true);
});
