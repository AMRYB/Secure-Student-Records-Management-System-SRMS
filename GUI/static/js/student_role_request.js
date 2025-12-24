const msg = document.getElementById("msg");
function setMsg(t){ msg.textContent = t || ""; }

document.getElementById("sendBtn").addEventListener("click", async () => {
  setMsg("");

  const requested_role = document.getElementById("requestedRole").value;
  const reason = document.getElementById("reason").value.trim();

  const res = await fetch("/api/student/role-request", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "include",
    body: JSON.stringify({ requested_role, reason })
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) return setMsg(data.error || "Failed to submit request.");

  setMsg("Request submitted successfully ");
  document.getElementById("reason").value = "";
});
