# Secure Student Records Management System (SRMS)

A **Database Security** course project that demonstrates how to protect student academic records using **SQL Server security controls** (RBAC, MLS/clearance levels, encrypted columns, inference control) with a small **Flask** web portal.

> ⚠️ **Educational project**: This repository is built for learning and course requirements. Do not use it as-is in production.

---

## ✨ Highlights

### Security-focused database design
- **Stored-procedure-only access**: direct table access is denied; roles are granted `EXECUTE` on approved stored procedures.
- **RBAC (Role-Based Access Control)**: Admin / Instructor / TA / Student / Guest.
- **MLS / Clearance levels**: access to records is restricted by clearance level.
- **Flow control (No Write Down)**: prevents users with lower clearance from writing to higher-classified records.
- **Column encryption (AES-256)** using master key + certificate + symmetric key (sensitive fields are stored encrypted).
- **Inference control** via a safe aggregation view (`vw_AvgGrades_Safe`) that only returns averages when **COUNT >= 3**.
- **Security test suite** (`Queries/Tests.sql`) to validate access restrictions.

### Functional portal
- Login + session-based role routing.
- Student: profile / grades (published only) / attendance / role-upgrade request.
- TA: record & view attendance (restricted by stored procedures).
- Instructor: insert & publish grades, record attendance.
- Admin: manage users + approve/deny role requests.

---

## 🖼️ Screenshots

> Screenshots are stored in `ADDs/Screenshots/`

![Login](ADDs/Screenshots/Screenshot%202025-12-21%20123849.png)

![Student Dashboard](ADDs/Screenshots/Screenshot%202025-12-21%20124123.png)

![Instructor Attendance](ADDs/Screenshots/Screenshot%202025-12-21%20124210.png)

---

## 🧰 Tech Stack

- **Backend:** Python + Flask
- **Database:** Microsoft SQL Server (stored procedures + roles + encryption)
- **DB Driver:** ODBC Driver 17 for SQL Server (via `pyodbc`)
- **Frontend:** HTML/CSS/JavaScript (Flask templates)

---

## 📁 Project Structure

```
.
├── GUI/                  # Flask app (routes + templates + static assets)
│   ├── app.py
│   ├── db.py
│   ├── templates/
│   └── static/
├── Queries/              # SQL scripts (DB creation, fixes, tests)
│   ├── Project.sql
│   ├── Fix.sql
│   └── Tests.sql
├── ADDs/
│   ├── SRMS.bak           # Optional DB backup
│   └── Screenshots/
└── Database-Security-–-Term-Project.pdf   # Course project specification
```

---

## ✅ Prerequisites

- Python **3.10+**
- Microsoft SQL Server (local instance is fine)
- ODBC Driver 17 for SQL Server
- (Recommended) SQL Server Management Studio (SSMS)

Python packages:
- `flask`
- `python-dotenv`
- `pyodbc`

---

## 🚀 Getting Started

### 1) Database setup

You have **two options**:

#### Option A — Run the SQL scripts (recommended)
1. Open **`Queries/Project.sql`** and execute it in SSMS.
2. Run **`Queries/Fix.sql`** (recommended).  
   - This adds profile fields used by `/info` and profile editing.

#### Option B — Restore the backup
Restore **`ADDs/SRMS.bak`** to a database named `SRMS`.

---

### 2) Configure environment variables

Create or edit `GUI/.env`:

```env
# Flask
FLASK_SECRET=your_secret_here

# SQL Server
DB_SERVER=YOUR_SERVER\INSTANCE
DB_NAME=SRMS

# Use Windows auth (Trusted Connection)
DB_TRUSTED_CONNECTION=yes

# Or set DB_TRUSTED_CONNECTION=no and use SQL auth:
# DB_USER=sa
# DB_PASSWORD=your_password

# ODBC Driver
ODBC_DRIVER=ODBC Driver 17 for SQL Server
```

#### Known small mismatch (easy fix)
In the repo, `.env` contains `FLASK_SECRET_KEY`, but `GUI/app.py` reads `FLASK_SECRET`.  
Fix it in either way:

- **Option 1 (recommended):** change `.env` key to `FLASK_SECRET=...`
- **Option 2:** update `app.py` to read `FLASK_SECRET_KEY`

---

### 3) Install dependencies

From the project root:

```bash
cd GUI
python -m venv .venv
# Windows:
.venv\Scripts\activate
# Linux/Mac:
# source .venv/bin/activate

pip install flask python-dotenv pyodbc
```

> Tip: You can also create a `requirements.txt` later and install via `pip install -r requirements.txt`.

---

### 4) Run the app

```bash
cd GUI
python app.py
```

Then open:
- `http://127.0.0.1:5000/login`

---

## 🔑 Demo Accounts

Seeded in `Queries/Project.sql`:

| Role | Username | Password |
|------|----------|----------|
| Admin | `ad` | `123` |
| Instructor | `in` | `123` |
| TA | `ta` | `123` |
| Students | `ze`, `do`, `am`, `fa`, `ma` | `123` |
| Guest | Continue as Guest | — |

---

## 🧪 Run Security Tests

After setting up the database, run:

- `Queries/Tests.sql`

This validates:
- direct table access is denied
- stored procedure access is allowed only for permitted roles
- MLS / clearance checks
- flow-control / "No Write Down" enforcement (where applicable)

---

## 🧠 Security Model (What to Look For)

- **Direct access denied** (e.g., `DENY SELECT/INSERT/UPDATE/DELETE ON dbo.<TABLE> TO PUBLIC`)
- **Roles & permissions**: database roles grant only `EXECUTE` on stored procedures.
- **Encryption**: master key + certificate + symmetric key (AES-256) to protect sensitive columns.
- **MLS**: clearance level checks are enforced inside SPs (e.g., viewing profiles/attendance).
- **No Write Down**: grade insertion checks that user's clearance is sufficient.
- **Inference control**: safe aggregation view requires at least 3 records (`HAVING COUNT(*) >= 3`).

---

## 🛠️ Troubleshooting

### `pyodbc` connection issues
- Verify the driver exists: `ODBC Driver 17 for SQL Server`
- Ensure `DB_SERVER` matches your SQL Server instance name.
- If not using Windows auth, set `DB_TRUSTED_CONNECTION=no` and provide `DB_USER` / `DB_PASSWORD`.

### Blank info page
- Make sure you executed `Queries/Fix.sql`.

---

## 📌 Notes

- The system is intentionally built around **stored procedures** to centralize and enforce security.
- UI restrictions (cache-control headers, best-effort anti-exfiltration headers) are included, but the **real security is in the database layer**.

---

## 🙏 Acknowledgements

Built as a term project for a **Database Security** course.
