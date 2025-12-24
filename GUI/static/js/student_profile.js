const msg = document.getElementById("msg");
function setMsg(t){ msg.textContent = t || ""; }

fetch("/api/student/profile", { credentials: "include" })
  .then(r => r.json())
  .then(data => {
    const p = data.profile;
    if (!p) return setMsg("Profile not found.");

    document.getElementById("sid").textContent = p.StudentID ?? "";
    document.getElementById("name").textContent = p.FullName ?? "";
    document.getElementById("email").textContent = p.Email ?? "";
    document.getElementById("dob").textContent = p.DOB ?? "";
    document.getElementById("dept").textContent = p.Department ?? "";
    document.getElementById("cl").textContent = p.ClearanceLevel ?? "";
  })
  .catch(() => setMsg("Error loading profile."));
