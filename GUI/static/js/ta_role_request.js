const msg = document.getElementById("msg");

function setMsg(text, ok=false){
  msg.textContent = text || "";
  msg.className = "msg " + (ok ? "ok" : "err");
}

document.getElementById("sendBtn")?.addEventListener("click", async () => {
  setMsg("");

  const requested_role = document.getElementById("requestedRole").value;
  const reason = document.getElementById("reason").value.trim();

  const res = await fetch("/api/ta/role-request", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "include",
    body: JSON.stringify({ requested_role, reason })
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) return setMsg(data.error || "Failed to submit request.");

  setMsg("Request submitted successfully ", true);
  document.getElementById("reason").value = "";
});
