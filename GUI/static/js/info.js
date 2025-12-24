const msg = document.getElementById("msg");
const whoLine = document.getElementById("whoLine");

function setMsg(text, ok=false){
  msg.textContent = text || "";
  msg.className = "msg " + (ok ? "ok" : "err");
}

async function apiGetMe(){
  const res = await fetch("/api/me", { credentials: "include" });
  const data = await res.json().catch(()=> ({}));
  if(!res.ok || !data.ok) throw new Error(data.error || "Failed to load profile");
  return data.profile;
}

async function apiUpdateMe(payload){
  const res = await fetch("/api/me", {
    method:"POST",
    headers:{ "Content-Type":"application/json" },
    credentials:"include",
    body: JSON.stringify(payload)
  });
  const data = await res.json().catch(()=> ({}));
  if(!res.ok || !data.ok) throw new Error(data.error || "Update failed");
  return true;
}

function fillForm(profile){
  const role = profile.role;
  const u = profile.data || {};

  whoLine.textContent = `Role: ${role} | UserID: ${profile.user_id} | Clearance: ${profile.clearance}`;

  // Student: data from STUDENT table
  // Admin/TA: data from USERS table (sp_ViewMyUserProfile)
  document.getElementById("fullName").value = u.FullName || u.fullName || "";
  document.getElementById("email").value = u.Email || u.email || "";
  document.getElementById("dob").value = (u.DOB || "").slice(0,10);
  document.getElementById("dept").value = u.Department || "";

  // Disable DOB/Department if not student
  const isStudent = role === "Student";
  document.getElementById("dob").disabled = !isStudent;
  document.getElementById("dept").disabled = !isStudent;
}

async function load(){
  try{
    setMsg("");
    const profile = await apiGetMe();
    fillForm(profile);

    // Guest: disable form
    if(profile.role === "Guest"){
      document.querySelectorAll("#infoForm input, #infoForm button[type=submit]").forEach(x => x.disabled = true);
      setMsg("Guest has no editable profile.", false);
    }

  }catch(e){
    setMsg(e.message || "Error", false);
  }
}

document.getElementById("infoForm").addEventListener("submit", async (e)=>{
  e.preventDefault();
  setMsg("");

  const payload = {
    full_name: document.getElementById("fullName").value.trim(),
    email: document.getElementById("email").value.trim(),
    dob: document.getElementById("dob").value || null,
    department: document.getElementById("dept").value.trim() || null,
  };

  try{
    await apiUpdateMe(payload);
    setMsg("Saved successfully ", true);
    await load();
  }catch(err){
    setMsg(err.message || "Update failed", false);
  }
});

document.getElementById("reloadBtn").addEventListener("click", load);

document.getElementById("logoutBtn").addEventListener("click", async ()=>{
  await fetch("/api/logout", { method:"POST", credentials:"include" });
  location.href = "/login";
});

load();
