// static/js/login.js

function redirectByRole(role) {
  if (role === "Admin") window.location.href = "/admin";
  else if (role === "Student") window.location.href = "/student";
  else if (role === "TA") window.location.href = "/ta";
  else if (role === "Instructor") window.location.href = "/instructor";
  else if (role === "Guest") window.location.href = "/guest";
  else window.location.href = "/login";
}

async function apiLogin(username, password) {
  const res = await fetch("/api/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "include", // important for session cookies
    body: JSON.stringify({ username, password }),
  });

  const data = await res.json().catch(() => null);

  if (!res.ok || !data?.ok) {
    throw new Error(data?.error || `Login failed (HTTP ${res.status})`);
  }

  return data.user;
}

document.getElementById("loginForm").addEventListener("submit", async function (event) {
  event.preventDefault();

  const userId = document.getElementById("userId").value.trim();
  const password = document.getElementById("password").value.trim();
  const errorElement = document.getElementById("error");

  errorElement.textContent = "";

  try {
    const user = await apiLogin(userId, password);
    redirectByRole(user.role);
  } catch (err) {
    errorElement.textContent = err.message || "Username or password is incorrect";
  }
});

// input label animation
document.querySelectorAll(".input-field").forEach((input) => {
  input.addEventListener("focus", () => input.classList.add("active"));
  input.addEventListener("blur", () => {
    if (input.value === "") input.classList.remove("active");
  });
});

// show/hide password
const togglePassword = document.querySelector("#login-eye");
const passwordField = document.querySelector("#password");

togglePassword.addEventListener("click", function () {
  const type = passwordField.getAttribute("type") === "password" ? "text" : "password";
  passwordField.setAttribute("type", type);
  this.classList.toggle("ri-eye-off-line");
  this.classList.toggle("ri-eye-line");
});

// Guest login
document.getElementById("guestLink").addEventListener("click", async () => {
  const errorElement = document.getElementById("error");
  errorElement.textContent = "";

  try {
    // uses seeded user: guest / guest123
    const user = await apiLogin("guest", "guest123");
    redirectByRole(user.role);
  } catch (err) {
    errorElement.textContent = err.message || "Guest login failed";
  }
});
