let usersData = [];

function loadJSONData(filePath, deptName) {
  return fetch(filePath)
    .then((response) => {
      if (!response.ok) throw new Error(`Failed to fetch ${filePath}`);
      return response.json();
    })
    .then((data) => data.map((user) => ({ ...user, department: deptName })))
    .catch((error) => {
      console.error("Error loading JSON data:", error);
      return [];
    });
}

window.onload = function () {
  Promise.all([
    loadJSONData("assets/Login/2023/ds_users.json", "Data Science"),
    loadJSONData("assets/Login/2023/mse_users.json", "Multimedia Software"),
    loadJSONData("assets/Login/2023/rse_users.json", "Robotics Software"),
  ]).then((dataArrays) => {
    usersData = dataArrays.flat();
  });
};

document.getElementById("loginForm").addEventListener("submit", function (event) {
  event.preventDefault();

  const userId = document.getElementById("userId").value.trim();
  const password = document.getElementById("password").value.trim();
  const errorElement = document.getElementById("error");

  const user = usersData.find(
    (row) =>
      (row["SID-1"] == userId || row["SID-2"] == userId) &&
      row["Password"] === password
  );

  if (user) {
    localStorage.setItem("userNameEN", user["Sname-EN"]);
    localStorage.setItem("userNameAR", user["Sname-AR"]);
    localStorage.setItem("userId1", user["SID-1"]);
    localStorage.setItem("userId2", user["SID-2"] || "N/A");
    localStorage.setItem("userDept", user.department);
    window.location.href = "Result.html";
  } else {
    errorElement.textContent = "User ID or Password is incorrect";
  }
});

document.getElementById("userId").addEventListener("blur", function () {
  const userId = this.value.trim();
  const welcomeMessageElement = document.getElementById("welcomeMessage");

  welcomeMessageElement.textContent = "Welcome Back";

  const user = usersData.find((row) => row["SID-1"] == userId || row["SID-2"] == userId);
  if (user) {
    const fullNameEN = user["Sname-EN"].split(" ").slice(0, 2).join(" ");
    welcomeMessageElement.textContent = `Welcome ${fullNameEN}`;
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
