async function apiLogin(username, password) {
  const res = await fetch("/api/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "include",
    body: JSON.stringify({ username, password }),
  });

  const data = await res.json().catch(() => null);

  if (!res.ok || !data?.ok) {
    throw new Error(data?.error || "Login failed");
  }

  return data.redirect;
}

document.getElementById("loginForm").addEventListener("submit", async (event) => {
  event.preventDefault();

  const username = document.getElementById("userId").value.trim();
  const password = document.getElementById("password").value.trim();
  const errorElement = document.getElementById("error");

  errorElement.textContent = "";

  if (!username || !password) {
    errorElement.textContent = "Please enter username and password";
    return;
  }

  try {
    const redirectUrl = await apiLogin(username, password);
    window.location.href = redirectUrl;
  } catch (err) {
    errorElement.textContent = err.message || "Username or password is incorrect";
  }
});

document.querySelectorAll(".input-field").forEach((input) => {
  input.addEventListener("focus", () => input.classList.add("active"));
  input.addEventListener("blur", () => {
    if (input.value === "") input.classList.remove("active");
  });
});

const togglePassword = document.querySelector("#login-eye");
const passwordField = document.querySelector("#password");

togglePassword.addEventListener("click", () => {
  const type =
    passwordField.getAttribute("type") === "password" ? "text" : "password";
  passwordField.setAttribute("type", type);
  togglePassword.classList.toggle("ri-eye-off-line");
  togglePassword.classList.toggle("ri-eye-line");
});


document.getElementById("guestLink").addEventListener("click", async () => {
  const errorElement = document.getElementById("error");
  errorElement.textContent = "";

  try {
    const res = await fetch("/api/login/guest", {
      method: "POST",
      credentials: "include",
    });

    const data = await res.json();
    if (!res.ok) throw new Error("Guest login failed");

    window.location.href = data.redirect;
  } catch (err) {
    errorElement.textContent = err.message || "Guest login failed";
  }
});
