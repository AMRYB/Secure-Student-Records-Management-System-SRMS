document.getElementById("logoutBtn").addEventListener("click", async () => {
  await fetch("/api/logout", { method: "POST", credentials: "include" });
  window.location.href = "/login";
});
