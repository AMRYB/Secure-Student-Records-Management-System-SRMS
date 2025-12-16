import { apiFetch } from "./api.js";

export async function login(username, password) {
  return await apiFetch("/api/login", {
    method: "POST",
    body: { username, password },
  });
}

export async function logout() {
  return await apiFetch("/api/logout", { method: "POST" });
}

export async function me() {
  return await apiFetch("/api/me");
}

export function redirectByRole(role) {
  if (role === "Admin") window.location.href = "/admin";
  else if (role === "Student") window.location.href = "/student";
  else if (role === "TA") window.location.href = "/ta";
  else if (role === "Instructor") window.location.href = "/instructor";
  else window.location.href = "/login";
}
