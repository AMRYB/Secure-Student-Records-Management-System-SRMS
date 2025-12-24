USE master;
GO

IF DB_ID('SRMS') IS NOT NULL
BEGIN
    ALTER DATABASE SRMS SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SRMS;
END
GO

CREATE DATABASE SRMS;
GO
USE SRMS;
GO

/* =========================
   0) ENCRYPTION SETUP
   ========================= */
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'FinalProjectHNU@2025';
GO

CREATE CERTIFICATE SRMS_Cert
WITH SUBJECT = 'SRMS Certificate for encryption';
GO

CREATE SYMMETRIC KEY SRMS_SymKey
WITH ALGORITHM = AES_256
ENCRYPTION BY CERTIFICATE SRMS_Cert;
GO

/* =========================
   1) TABLES
   ========================= */

-- STUDENT (Confidential)
CREATE TABLE dbo.STUDENT (
    StudentID            INT IDENTITY(1,1) PRIMARY KEY,
    StudentIDEncrypted   VARBINARY(MAX) NULL,
    FullName             NVARCHAR(100) NOT NULL,
    Email                NVARCHAR(100) NOT NULL,
    PhoneEncrypted       VARBINARY(MAX) NULL,
    DOB                  DATE NULL,
    Department           NVARCHAR(100) NULL,
    ClearanceLevel       INT NOT NULL
);
GO

-- INSTRUCTOR (Confidential)
CREATE TABLE dbo.INSTRUCTOR (
    InstructorID    INT IDENTITY(1,1) PRIMARY KEY,
    FullName        NVARCHAR(100) NOT NULL,
    Email           NVARCHAR(100) NOT NULL,
    ClearanceLevel  INT NOT NULL
);
GO

-- COURSE (Unclassified / PublicInfo visible to Guest)
CREATE TABLE dbo.COURSE (
    CourseID      INT IDENTITY(1,1) PRIMARY KEY,
    CourseName    NVARCHAR(100) NOT NULL,
    Description   NVARCHAR(MAX) NULL,
    PublicInfo    NVARCHAR(MAX) NULL,
    InstructorID  INT NULL
);
GO

ALTER TABLE dbo.COURSE
ADD CONSTRAINT FK_Course_Instructor
FOREIGN KEY (InstructorID) REFERENCES dbo.INSTRUCTOR(InstructorID);
GO

-- ENROLLMENT (Unclassified)
CREATE TABLE dbo.ENROLLMENT (
    EnrollmentID INT IDENTITY(1,1) PRIMARY KEY,
    StudentID INT NOT NULL,
    CourseID  INT NOT NULL,
    EnrollDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_Enroll_Student FOREIGN KEY (StudentID) REFERENCES dbo.STUDENT(StudentID) ON DELETE CASCADE,
    CONSTRAINT FK_Enroll_Course  FOREIGN KEY (CourseID)  REFERENCES dbo.COURSE(CourseID) ON DELETE CASCADE,
    CONSTRAINT UQ_Enroll UNIQUE(StudentID, CourseID)
);
GO

-- USERS (Authentication + identity binding)
CREATE TABLE dbo.USERS (
    UserID             INT IDENTITY(1,1) PRIMARY KEY,
    UsernameEncrypted  VARBINARY(MAX) NOT NULL,
    PasswordEncrypted  VARBINARY(MAX) NOT NULL,
    Role               NVARCHAR(50) NOT NULL
        CHECK (Role IN ('Admin','Instructor','TA','Student','Guest')),
    ClearanceLevel     INT NOT NULL,
    StudentID          INT NULL,
    InstructorID       INT NULL,
    CONSTRAINT FK_Users_Student    FOREIGN KEY (StudentID)    REFERENCES dbo.STUDENT(StudentID),
    CONSTRAINT FK_Users_Instructor FOREIGN KEY (InstructorID) REFERENCES dbo.INSTRUCTOR(InstructorID)
);
GO

-- TA ↔ Course assignments
CREATE TABLE dbo.TA_COURSE (
    AssignmentID INT IDENTITY(1,1) PRIMARY KEY,
    TAUserID INT NOT NULL,
    CourseID INT NOT NULL,
    AssignDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_TACourse_User   FOREIGN KEY (TAUserID) REFERENCES dbo.USERS(UserID) ON DELETE CASCADE,
    CONSTRAINT FK_TACourse_Course FOREIGN KEY (CourseID) REFERENCES dbo.COURSE(CourseID) ON DELETE CASCADE,
    CONSTRAINT UQ_TACourse UNIQUE(TAUserID, CourseID)
);
GO

-- GRADES (Secret)
CREATE TABLE dbo.GRADES (
    GradeID              INT IDENTITY(1,1) PRIMARY KEY,
    StudentIDEncrypted   VARBINARY(MAX) NOT NULL,
    StudentID            INT NOT NULL,
    CourseID             INT NOT NULL,
    GradeValueEncrypted  VARBINARY(MAX) NULL,
    IsPublished          BIT NOT NULL DEFAULT 0,
    DateEntered          DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    PublishedDate        DATETIME2 NULL,
    CONSTRAINT FK_Grades_Student FOREIGN KEY (StudentID) REFERENCES dbo.STUDENT(StudentID) ON DELETE CASCADE,
    CONSTRAINT FK_Grades_Course  FOREIGN KEY (CourseID)  REFERENCES dbo.COURSE(CourseID) ON DELETE CASCADE
);
GO

-- ATTENDANCE (Secret)
CREATE TABLE dbo.ATTENDANCE (
    AttendanceID            INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    StudentID               INT NOT NULL,
    CourseID                INT NOT NULL,
    Status                  BIT NOT NULL,
    DateRecorded            DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    RecordedByUserID        INT NULL,
    CONSTRAINT FK_Attendance_Student FOREIGN KEY (StudentID) REFERENCES dbo.STUDENT(StudentID) ON DELETE CASCADE,
    CONSTRAINT FK_Attendance_Course  FOREIGN KEY (CourseID)  REFERENCES dbo.COURSE(CourseID) ON DELETE CASCADE,
    CONSTRAINT FK_Attendance_User FOREIGN KEY (RecordedByUserID) REFERENCES dbo.USERS(UserID)
);
GO

-- ROLE REQUESTS (Part B)
CREATE TABLE dbo.ROLE_REQUESTS (
    RequestID      INT IDENTITY(1,1) PRIMARY KEY,
    UserID         INT NOT NULL,
    CurrentRole    NVARCHAR(50) NOT NULL,
    RequestedRole  NVARCHAR(50) NOT NULL,
    Reason         NVARCHAR(255) NOT NULL,
    Status         NVARCHAR(20) NOT NULL DEFAULT 'Pending'
        CHECK (Status IN ('Pending','Approved','Denied')),
    RequestDate    DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_RoleReq_User FOREIGN KEY (UserID) REFERENCES dbo.USERS(UserID) ON DELETE CASCADE
);
GO

/* =========================
   2) RBAC (Roles + deny direct access)
   ========================= */
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='Admin')      CREATE ROLE Admin;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='Instructor') CREATE ROLE Instructor;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='TA')         CREATE ROLE TA;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='Student')    CREATE ROLE Student;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='Guest')      CREATE ROLE Guest;
GO

DENY SELECT, INSERT, UPDATE, DELETE ON dbo.STUDENT       TO PUBLIC;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.INSTRUCTOR    TO PUBLIC;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.COURSE        TO PUBLIC;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.ENROLLMENT    TO PUBLIC;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.USERS         TO PUBLIC;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.TA_COURSE     TO PUBLIC;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.GRADES        TO PUBLIC;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.ATTENDANCE    TO PUBLIC;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.ROLE_REQUESTS TO PUBLIC;
GO

/* =========================
   3) INFERENCE CONTROL (Query Set Size >= 3)
   ========================= */
CREATE OR ALTER VIEW dbo.vw_AvgGrades_Safe
AS
SELECT
    CourseID,
    AVG(CAST(DecryptByKey(GradeValueEncrypted) AS DECIMAL(5,2))) AS AvgGrade,
    COUNT(*) AS RecordsCount
FROM dbo.GRADES
GROUP BY CourseID
HAVING COUNT(*) >= 3;
GO

/* =========================
   4) STORED PROCEDURES (ALL ACCESS)
   ========================= */

CREATE OR ALTER PROCEDURE dbo.sp_GetUserContext
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT UserID, Role, ClearanceLevel, StudentID, InstructorID
    FROM dbo.USERS
    WHERE UserID = @UserID;
END
GO

/* ---------- Admin ---------- */

CREATE OR ALTER PROCEDURE dbo.sp_Admin_ListUsers
    @UserRole NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserRole <> 'Admin'
    BEGIN
        RAISERROR('Access Denied: Admin only.',16,1);
        RETURN;
    END

    SELECT UserID, Role, ClearanceLevel, StudentID, InstructorID
    FROM dbo.USERS
    ORDER BY UserID;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Admin_ListPendingRoleRequests
    @UserRole NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserRole <> 'Admin'
    BEGIN
        RAISERROR('Access Denied: Admin only.',16,1);
        RETURN;
    END

    SELECT RequestID, UserID, CurrentRole, RequestedRole, Reason, RequestDate, Status
    FROM dbo.ROLE_REQUESTS
    WHERE Status='Pending'
    ORDER BY RequestDate DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Admin_ApproveRoleRequest
    @UserRole NVARCHAR(50),
    @RequestID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserRole <> 'Admin'
    BEGIN
        RAISERROR('Access Denied: Admin only.',16,1);
        RETURN;
    END

    DECLARE @UserID INT, @NewRole NVARCHAR(50);

    SELECT @UserID=UserID, @NewRole=RequestedRole
    FROM dbo.ROLE_REQUESTS
    WHERE RequestID=@RequestID AND Status='Pending';

    IF @UserID IS NULL
    BEGIN
        RAISERROR('Invalid RequestID or request not Pending.',16,1);
        RETURN;
    END

    UPDATE dbo.USERS SET Role=@NewRole WHERE UserID=@UserID;
    UPDATE dbo.ROLE_REQUESTS SET Status='Approved' WHERE RequestID=@RequestID;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Admin_DenyRoleRequest
    @UserRole NVARCHAR(50),
    @RequestID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserRole <> 'Admin'
    BEGIN
        RAISERROR('Access Denied: Admin only.',16,1);
        RETURN;
    END

    UPDATE dbo.ROLE_REQUESTS
    SET Status='Denied'
    WHERE RequestID=@RequestID AND Status='Pending';

    IF @@ROWCOUNT=0
        RAISERROR('Invalid RequestID or request not Pending.',16,1);
END
GO

/* ---------- Authentication ---------- */

CREATE OR ALTER PROCEDURE dbo.sp_AuthUser
    @Role NVARCHAR(50),
    @UsernamePlain NVARCHAR(100),
    @PasswordPlain NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    OPEN SYMMETRIC KEY SRMS_SymKey
        DECRYPTION BY CERTIFICATE SRMS_Cert;

    ;WITH U AS (
        SELECT
            UserID,
            CONVERT(NVARCHAR(100), DecryptByKey(UsernameEncrypted)) AS UsernamePlain,
            CONVERT(NVARCHAR(100), DecryptByKey(PasswordEncrypted)) AS PasswordPlain,
            Role,
            ClearanceLevel
        FROM dbo.USERS
    )
    SELECT TOP 1 UserID, Role, ClearanceLevel
    FROM U
    WHERE Role = @Role
      AND UsernamePlain = @UsernamePlain
      AND (
            (@Role='Guest' AND (PasswordPlain = '' OR @PasswordPlain = '' OR @PasswordPlain IS NULL))
            OR
            (@Role<>'Guest' AND PasswordPlain = @PasswordPlain)
          );

    CLOSE SYMMETRIC KEY SRMS_SymKey;
END
GO

/* ---------- Student Profile (Confidential) ---------- */

CREATE OR ALTER PROCEDURE dbo.sp_ViewStudent_Profile
    @UserRole NVARCHAR(50),
    @UserID INT,
    @UserClearance INT,
    @StudentID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserRole NOT IN ('Admin','Instructor','TA','Student')
    BEGIN
        RAISERROR('Access Denied',16,1);
        RETURN;
    END

    IF @UserRole = 'Student'
    BEGIN
        SELECT @StudentID = StudentID
        FROM dbo.USERS
        WHERE UserID = @UserID AND Role='Student';

        IF @StudentID IS NULL
        BEGIN
            RAISERROR('Student identity not linked to this account.',16,1);
            RETURN;
        END
    END

    IF @UserRole = 'TA'
    BEGIN
        IF @StudentID IS NULL
        BEGIN
            RAISERROR('TA must specify StudentID.',16,1);
            RETURN;
        END

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.TA_COURSE tc
            JOIN dbo.ENROLLMENT e ON e.CourseID = tc.CourseID AND e.StudentID = @StudentID
            WHERE tc.TAUserID = @UserID
        )
        BEGIN
            RAISERROR('Access Denied: Student not in your assigned courses.',16,1);
            RETURN;
        END
    END

    SELECT StudentID, FullName, Email, DOB, Department, ClearanceLevel
    FROM dbo.STUDENT
    WHERE StudentID = @StudentID
      AND ClearanceLevel <= @UserClearance;
END
GO

/* ---------- Grades (Secret) ---------- */

CREATE OR ALTER PROCEDURE dbo.sp_ViewGrades
    @UserRole NVARCHAR(50),
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserRole NOT IN ('Admin','Instructor','Student')
    BEGIN
        RAISERROR('Access Denied: Grades not allowed for this role.',16,1);
        RETURN;
    END

    OPEN SYMMETRIC KEY SRMS_SymKey
        DECRYPTION BY CERTIFICATE SRMS_Cert;

    IF @UserRole IN ('Admin','Instructor')
    BEGIN
        SELECT
            GradeID,
            StudentID,
            CourseID,
            CAST(DecryptByKey(GradeValueEncrypted) AS DECIMAL(5,2)) AS Grade,
            IsPublished,
            DateEntered,
            PublishedDate
        FROM dbo.GRADES
        ORDER BY GradeID DESC;
    END
    ELSE
    BEGIN
        DECLARE @SID INT;
        SELECT @SID = StudentID
        FROM dbo.USERS
        WHERE UserID=@UserID AND Role='Student';

        IF @SID IS NULL
        BEGIN
            RAISERROR('Student identity not linked to this account.',16,1);
            CLOSE SYMMETRIC KEY SRMS_SymKey;
            RETURN;
        END

        SELECT
            GradeID,
            StudentID,
            CourseID,
            CAST(DecryptByKey(GradeValueEncrypted) AS DECIMAL(5,2)) AS Grade,
            IsPublished,
            DateEntered,
            PublishedDate
        FROM dbo.GRADES
        WHERE StudentID = @SID
          AND IsPublished = 1
        ORDER BY GradeID DESC;
    END

    CLOSE SYMMETRIC KEY SRMS_SymKey;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_InsertGrade
    @UserRole NVARCHAR(50),
    @UserID INT,
    @UserClearance INT,
    @StudentID INT,
    @CourseID INT,
    @Grade DECIMAL(5,2)
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserRole NOT IN ('Admin','Instructor')
    BEGIN
        RAISERROR('Access Denied: Admin/Instructor only.',16,1);
        RETURN;
    END

    DECLARE @StudentClearance INT;
    SELECT @StudentClearance = ClearanceLevel
    FROM dbo.STUDENT
    WHERE StudentID = @StudentID;

    IF @StudentClearance IS NULL
    BEGIN
        RAISERROR('Student not found.',16,1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.COURSE WHERE CourseID=@CourseID)
    BEGIN
        RAISERROR('Course not found.',16,1);
        RETURN;
    END

    IF @UserClearance < @StudentClearance
    BEGIN
        RAISERROR('No Write Down violation: insufficient clearance.',16,1);
        RETURN;
    END

    OPEN SYMMETRIC KEY SRMS_SymKey
        DECRYPTION BY CERTIFICATE SRMS_Cert;

    INSERT INTO dbo.GRADES (StudentIDEncrypted, StudentID, CourseID, GradeValueEncrypted, IsPublished)
    VALUES (
        EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(16), @StudentID)),
        @StudentID,
        @CourseID,
        EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(16), @Grade)),
        0
    );

    CLOSE SYMMETRIC KEY SRMS_SymKey;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_SetGradePublished
    @UserRole NVARCHAR(50),
    @GradeID INT,
    @Publish BIT
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserRole NOT IN ('Admin','Instructor')
    BEGIN
        RAISERROR('Access Denied: Admin/Instructor only.',16,1);
        RETURN;
    END

    UPDATE dbo.GRADES
    SET IsPublished = @Publish,
        PublishedDate = CASE WHEN @Publish=1 THEN SYSUTCDATETIME() ELSE NULL END
    WHERE GradeID = @GradeID;

    IF @@ROWCOUNT = 0
        RAISERROR('GradeID not found.',16,1);
END
GO

/* ---------- Attendance (Secret) ---------- */

CREATE OR ALTER PROCEDURE dbo.sp_ViewAttendance
    @UserRole NVARCHAR(50),
    @UserID INT,
    @UserClearance INT,
    @StudentID INT = NULL,
    @CourseID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserRole NOT IN ('Admin','Instructor','TA','Student')
    BEGIN
        RAISERROR('Access Denied',16,1);
        RETURN;
    END

    IF @UserRole = 'Student'
    BEGIN
        SELECT @StudentID = StudentID
        FROM dbo.USERS
        WHERE UserID=@UserID AND Role='Student';

        IF @StudentID IS NULL
        BEGIN
            RAISERROR('Student identity not linked to this account.',16,1);
            RETURN;
        END
    END

    ;WITH Allowed AS (
        SELECT a.*
        FROM dbo.ATTENDANCE a
        JOIN dbo.STUDENT s ON s.StudentID = a.StudentID
        WHERE s.ClearanceLevel <= @UserClearance
          AND (@StudentID IS NULL OR a.StudentID = @StudentID)
          AND (@CourseID  IS NULL OR a.CourseID  = @CourseID)
    )
    SELECT AttendanceID, StudentID, CourseID, Status, DateRecorded, RecordedByUserID
    FROM Allowed
    WHERE
        (@UserRole <> 'TA')
        OR EXISTS (SELECT 1 FROM dbo.TA_COURSE tc WHERE tc.TAUserID=@UserID AND tc.CourseID=Allowed.CourseID)
    ORDER BY AttendanceID DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_RecordAttendance
    @UserRole NVARCHAR(50),
    @UserID INT,
    @StudentID INT,
    @CourseID INT,
    @Status BIT
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserRole NOT IN ('Admin','Instructor','TA')
    BEGIN
        RAISERROR('Access Denied: cannot edit attendance.',16,1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.STUDENT WHERE StudentID=@StudentID)
    BEGIN
        RAISERROR('Student not found.',16,1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.COURSE WHERE CourseID=@CourseID)
    BEGIN
        RAISERROR('Course not found.',16,1);
        RETURN;
    END

    IF @UserRole='TA'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.TA_COURSE WHERE TAUserID=@UserID AND CourseID=@CourseID)
        BEGIN
            RAISERROR('Access Denied: TA not assigned to this course.',16,1);
            RETURN;
        END
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.ENROLLMENT WHERE StudentID=@StudentID AND CourseID=@CourseID)
    BEGIN
        RAISERROR('Student is not enrolled in this course.',16,1);
        RETURN;
    END

    INSERT INTO dbo.ATTENDANCE (StudentID, CourseID, Status, RecordedByUserID)
    VALUES (@StudentID, @CourseID, @Status, @UserID);
END
GO

/* ---------- Role requests (Part B) ---------- */

CREATE OR ALTER PROCEDURE dbo.sp_RequestRoleUpgrade
    @UserRole NVARCHAR(50),
    @UserID INT,
    @RequestedRole NVARCHAR(50),
    @Reason NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserRole NOT IN ('Student','TA')
    BEGIN
        RAISERROR('Only Student/TA can submit upgrade requests.',16,1);
        RETURN;
    END

    DECLARE @CurrentRole NVARCHAR(50);
    SELECT @CurrentRole = Role FROM dbo.USERS WHERE UserID=@UserID;

    INSERT INTO dbo.ROLE_REQUESTS (UserID, CurrentRole, RequestedRole, Reason)
    VALUES (@UserID, @CurrentRole, @RequestedRole, @Reason);
END
GO

/* ---------- Guest public course view ---------- */

CREATE OR ALTER PROCEDURE dbo.sp_Guest_ViewPublicCourses
    @UserRole NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserRole NOT IN ('Guest','Student','TA','Instructor','Admin')
    BEGIN
        RAISERROR('Access Denied',16,1);
        RETURN;
    END

    SELECT CourseID, CourseName, PublicInfo
    FROM dbo.COURSE
    ORDER BY CourseID;
END
GO

/* =========================
   5) RBAC: GRANT/REVOKE (execute-only)
   ========================= */

REVOKE EXECUTE TO PUBLIC;
GO

-- Admin can execute everything
GRANT EXECUTE ON dbo.sp_GetUserContext                 TO Admin;
GRANT EXECUTE ON dbo.sp_Admin_ListUsers               TO Admin;
GRANT EXECUTE ON dbo.sp_Admin_ListPendingRoleRequests TO Admin;
GRANT EXECUTE ON dbo.sp_Admin_ApproveRoleRequest      TO Admin;
GRANT EXECUTE ON dbo.sp_Admin_DenyRoleRequest         TO Admin;
GRANT EXECUTE ON dbo.sp_AuthUser                      TO Admin;
GRANT EXECUTE ON dbo.sp_ViewStudent_Profile           TO Admin;
GRANT EXECUTE ON dbo.sp_ViewGrades                    TO Admin;
GRANT EXECUTE ON dbo.sp_InsertGrade                   TO Admin;
GRANT EXECUTE ON dbo.sp_SetGradePublished             TO Admin;
GRANT EXECUTE ON dbo.sp_ViewAttendance                TO Admin;
GRANT EXECUTE ON dbo.sp_RecordAttendance              TO Admin;
GRANT EXECUTE ON dbo.sp_RequestRoleUpgrade            TO Admin;
GRANT EXECUTE ON dbo.sp_Guest_ViewPublicCourses       TO Admin;
GO

-- Instructor
GRANT EXECUTE ON dbo.sp_GetUserContext            TO Instructor;
GRANT EXECUTE ON dbo.sp_AuthUser                  TO Instructor;
GRANT EXECUTE ON dbo.sp_ViewStudent_Profile       TO Instructor;
GRANT EXECUTE ON dbo.sp_ViewGrades                TO Instructor;
GRANT EXECUTE ON dbo.sp_InsertGrade               TO Instructor;
GRANT EXECUTE ON dbo.sp_SetGradePublished         TO Instructor;
GRANT EXECUTE ON dbo.sp_ViewAttendance            TO Instructor;
GRANT EXECUTE ON dbo.sp_RecordAttendance          TO Instructor;
GRANT EXECUTE ON dbo.sp_Guest_ViewPublicCourses   TO Instructor;
GO

-- TA
GRANT EXECUTE ON dbo.sp_GetUserContext            TO TA;
GRANT EXECUTE ON dbo.sp_AuthUser                  TO TA;
GRANT EXECUTE ON dbo.sp_ViewStudent_Profile       TO TA;
GRANT EXECUTE ON dbo.sp_ViewAttendance            TO TA;
GRANT EXECUTE ON dbo.sp_RecordAttendance          TO TA;
GRANT EXECUTE ON dbo.sp_RequestRoleUpgrade        TO TA;
GRANT EXECUTE ON dbo.sp_Guest_ViewPublicCourses   TO TA;
GO

-- Student
GRANT EXECUTE ON dbo.sp_GetUserContext            TO Student;
GRANT EXECUTE ON dbo.sp_AuthUser                  TO Student;
GRANT EXECUTE ON dbo.sp_ViewStudent_Profile       TO Student;
GRANT EXECUTE ON dbo.sp_ViewAttendance            TO Student;
GRANT EXECUTE ON dbo.sp_ViewGrades                TO Student;
GRANT EXECUTE ON dbo.sp_RequestRoleUpgrade        TO Student;
GRANT EXECUTE ON dbo.sp_Guest_ViewPublicCourses   TO Student;
GO

-- Guest
GRANT EXECUTE ON dbo.sp_GetUserContext            TO Guest;
GRANT EXECUTE ON dbo.sp_AuthUser                  TO Guest;
GRANT EXECUTE ON dbo.sp_Guest_ViewPublicCourses   TO Guest;
GO

/* =========================
   6) SEED DATA (UPDATED)
   ========================= */

INSERT INTO dbo.INSTRUCTOR (FullName, Email, ClearanceLevel)
VALUES
(N'Dr. Mohamed Attia',     N'mohamed.attia@uni.edu', 3),
(N'Dr. Ahmed ElSayed',     N'ahmed.elsayed@uni.edu', 3),
(N'Dr. Mahmoud AlMaslawi', N'mahmoud.maslawi@uni.edu', 3),
(N'Dr. Soha Ahmed',        N'soha.ahmed@uni.edu', 3);
GO


-- Students (5)
OPEN SYMMETRIC KEY SRMS_SymKey
DECRYPTION BY CERTIFICATE SRMS_Cert;

INSERT INTO dbo.STUDENT (StudentIDEncrypted, FullName, Email, PhoneEncrypted, DOB, Department, ClearanceLevel)
VALUES
(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(16), 1)),
 N'Zeinab Mahmoud', N'zeinab.mahmoud@uni.edu',
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'01011112222')),
 '2005-06-12', N'CS', 2),

(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(16), 2)),
 N'Doha Mohamed', N'doha.mohamed@uni.edu',
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'01022223333')),
 '2005-07-21', N'CS', 2),

(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(16), 3)),
 N'Amr Yasser', N'amr.yasser@uni.edu',
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'01033334444')),
 '2005-10-30', N'IS', 2),

(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(16), 4)),
 N'Farid Mohamed', N'farid.mohamed@uni.edu',
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'01044445555')),
 '2005-02-10', N'CS', 2),

(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(16), 5)),
 N'Mariem Taha', N'mariem.taha@uni.edu',
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'01055556666')),
 '2005-03-15', N'IS', 2);
GO

-- Courses
INSERT INTO dbo.COURSE (CourseName, Description, PublicInfo, InstructorID)
VALUES
(N'Database Security',
 N'Focuses on securing database systems through access control models, authentication/authorization, encryption, auditing, and defenses against common attacks (e.g., SQL injection). Includes practical labs using secure DB configurations.',
 N'Introduction to database security concepts and best practices.',
 1),

(N'Advanced Database',
 N'Covers advanced database topics such as transaction management, concurrency control, recovery techniques, indexing and query optimization, and distributed databases. Emphasizes performance and reliability in real-world systems.',
 N'Advanced database concepts: transactions, recovery, optimization, and distributed systems.',
 2),

(N'Computer Networks',
 N'Introduces computer networking fundamentals including OSI/TCP-IP models, addressing, routing and switching, transport protocols, and basic network security. Includes hands-on exercises and troubleshooting.',
 N'Networking fundamentals: protocols, routing, switching, and practical networking.',
 3),

(N'Operating Systems',
 N'Explores core operating system concepts such as process/thread management, CPU scheduling, synchronization, deadlocks, memory management, and file systems. Connects theory with modern OS behavior.',
 N'Operating system basics: processes, memory, scheduling, and file systems.',
 4);
GO


-- Enrollment (so attendance rules work)
INSERT INTO dbo.ENROLLMENT (StudentID, CourseID)
VALUES
(1,1),(1,2),
(2,1),(2,3),
(3,1),(3,4),
(4,1),(4,2),
(5,1),(5,3);
GO

-- USERS (encrypted credentials + identity binding)
-- Admin/Instructor/TA passwords = 123, usernames first two letters
INSERT INTO dbo.USERS (UsernameEncrypted, PasswordEncrypted, Role, ClearanceLevel, StudentID, InstructorID)
VALUES
(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'ad')),
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'123')),
 N'Admin', 5, NULL, NULL),

(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'in')),
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'123')),
 N'Instructor', 3, NULL, 1),

(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'ta')),
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'123')),
 N'TA', 2, NULL, NULL),

-- Students (first two letters, pass 123)
(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'ze')),
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'123')),
 N'Student', 2, 1, NULL),

(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'do')),
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'123')),
 N'Student', 2, 2, NULL),

(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'am')),
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'123')),
 N'Student', 2, 3, NULL),

(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'fa')),
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'123')),
 N'Student', 2, 4, NULL),

(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'ma')),
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'123')),
 N'Student', 2, 5, NULL),

-- Guest: password empty
(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'guest')),
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(MAX), N'')),
 N'Guest', 1, NULL, NULL);
GO

CLOSE SYMMETRIC KEY SRMS_SymKey;
GO

-- TA assigned to courses 1 and 2 (TAUserID = 3 in this seed order)
INSERT INTO dbo.TA_COURSE (TAUserID, CourseID)
VALUES (3,1),(3,2);
GO

-- Demo grades
OPEN SYMMETRIC KEY SRMS_SymKey
DECRYPTION BY CERTIFICATE SRMS_Cert;

INSERT INTO dbo.GRADES (StudentIDEncrypted, StudentID, CourseID, GradeValueEncrypted, IsPublished, PublishedDate)
VALUES
(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(16), 1)), 1, 1,
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(16), 88.50)), 1, SYSUTCDATETIME()),
(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(16), 1)), 1, 2,
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(16), 91.00)), 0, NULL),
(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(16), 2)), 2, 1,
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(16), 75.00)), 1, SYSUTCDATETIME()),
(EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(16), 3)), 3, 1,
 EncryptByKey(Key_GUID('SRMS_SymKey'), CONVERT(VARBINARY(16), 83.00)), 1, SYSUTCDATETIME());
GO

CLOSE SYMMETRIC KEY SRMS_SymKey;
GO

-- Demo attendance
EXEC dbo.sp_RecordAttendance @UserRole='TA', @UserID=3, @StudentID=1, @CourseID=1, @Status=1;
EXEC dbo.sp_RecordAttendance @UserRole='TA', @UserID=3, @StudentID=2, @CourseID=1, @Status=0;
EXEC dbo.sp_RecordAttendance @UserRole='TA', @UserID=3, @StudentID=3, @CourseID=1, @Status=1;
GO

/* =========================
   7) QUICK TESTS
   ========================= */
EXEC dbo.sp_AuthUser @Role='Admin',      @UsernamePlain='ad',    @PasswordPlain='123';
EXEC dbo.sp_AuthUser @Role='Instructor', @UsernamePlain='in',    @PasswordPlain='123';
EXEC dbo.sp_AuthUser @Role='TA',         @UsernamePlain='ta',    @PasswordPlain='123';
EXEC dbo.sp_AuthUser @Role='Student',    @UsernamePlain='ze',    @PasswordPlain='123';
EXEC dbo.sp_AuthUser @Role='Student',    @UsernamePlain='do',    @PasswordPlain='123';
EXEC dbo.sp_AuthUser @Role='Student',    @UsernamePlain='am',    @PasswordPlain='123';
EXEC dbo.sp_AuthUser @Role='Student',    @UsernamePlain='fa',    @PasswordPlain='123';
EXEC dbo.sp_AuthUser @Role='Student',    @UsernamePlain='ma',    @PasswordPlain='123';
EXEC dbo.sp_AuthUser @Role='Guest',      @UsernamePlain='guest', @PasswordPlain='';
GO