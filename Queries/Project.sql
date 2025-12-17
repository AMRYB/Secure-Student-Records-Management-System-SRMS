USE master;
GO

-- 1. DROP DATABASE IF EXISTS AND RECREATE
IF EXISTS (SELECT name FROM sys.databases WHERE name = 'SecureSRMS')
BEGIN
    -- Ensure no active connections block the drop
    ALTER DATABASE SecureSRMS SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SecureSRMS;
END
GO

CREATE DATABASE SecureSRMS;
GO

USE SecureSRMS;
GO
-- A. CREATE ROLES
CREATE ROLE db_Admin;
CREATE ROLE db_Instructor;
CREATE ROLE db_TA;
CREATE ROLE db_Student;
CREATE ROLE db_Guest;
GO
-- B. SCHEMA DEFINITION AND MLS IMPLEMENTATION
CREATE TABLE SecurityLevels (
    LevelID INT PRIMARY KEY,
    LevelName NVARCHAR(50) NOT NULL,
    MinClearance INT NOT NULL
);
GO

INSERT INTO SecurityLevels VALUES
(0, 'Unclassified', 0), (1, 'Confidential', 1), (2, 'Secret', 2), (3, 'TopSecret', 3);
GO

-- STUDENT Table: PK_ID is Surrogate Key, StudentID and Phone are encrypted (Fix 1)
CREATE TABLE STUDENT (
    PK_ID INT IDENTITY(1,1) PRIMARY KEY, 
    StudentID VARBINARY(MAX) NOT NULL, -- Encrypted Actual Student ID 
    FullName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100) NOT NULL,
    Phone VARBINARY(MAX), -- Encrypted
    DOB DATE NOT NULL,
    Department NVARCHAR(50) NOT NULL,
    Classification INT DEFAULT 1, 
    
    CONSTRAINT FK_Student_Classification FOREIGN KEY (Classification) 
        REFERENCES SecurityLevels(LevelID)
);
GO

CREATE TABLE INSTRUCTOR (
    InstructorID INT PRIMARY KEY,
    FullName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100) NOT NULL,
    ClearanceLevel INT DEFAULT 3,
    
    CONSTRAINT FK_Instructor_Clearance FOREIGN KEY (ClearanceLevel) 
        REFERENCES SecurityLevels(LevelID)
);
GO

CREATE TABLE COURSE (
    CourseID INT PRIMARY KEY,
    CourseName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX),
    PublicInfo NVARCHAR(MAX),
    Classification INT DEFAULT 0,
    
    CONSTRAINT FK_Course_Classification FOREIGN KEY (Classification) 
        REFERENCES SecurityLevels(LevelID)
);
GO

CREATE TABLE GRADES (
    GradeID INT IDENTITY(1,1) PRIMARY KEY,
    Student_PK_ID INT NOT NULL, 
    CourseID INT NOT NULL,
    GradeValue VARBINARY(MAX), -- Encrypted
    DateEntered DATETIME DEFAULT GETDATE(),
    Classification INT DEFAULT 2, 
    
    CONSTRAINT FK_GRADES_STUDENT FOREIGN KEY (Student_PK_ID) 
        REFERENCES STUDENT(PK_ID),
    CONSTRAINT FK_GRADES_COURSE FOREIGN KEY (CourseID) 
        REFERENCES COURSE(CourseID),
    CONSTRAINT FK_GRADES_Classification FOREIGN KEY (Classification) 
        REFERENCES SecurityLevels(LevelID)
);
GO

CREATE TABLE ATTENDANCE (
    AttendanceID INT IDENTITY(1,1) PRIMARY KEY,
    Student_PK_ID INT NOT NULL, 
    CourseID INT NOT NULL,
    Status BIT DEFAULT 1,
    DateRecorded DATETIME DEFAULT GETDATE(),
    Classification INT DEFAULT 1, 
    
    CONSTRAINT FK_ATTENDANCE_STUDENT FOREIGN KEY (Student_PK_ID) 
        REFERENCES STUDENT(PK_ID),
    CONSTRAINT FK_ATTENDANCE_COURSE FOREIGN KEY (CourseID) 
        REFERENCES COURSE(CourseID),
    CONSTRAINT FK_ATTENDANCE_Classification FOREIGN KEY (Classification) 
        REFERENCES SecurityLevels(LevelID)
);
GO

CREATE TABLE USERS (
    Username NVARCHAR(50) PRIMARY KEY,
    PasswordHash VARBINARY(64) NOT NULL, -- Hashing (Fix 2)
    Role NVARCHAR(20) NOT NULL CHECK (Role IN ('Admin', 'Instructor', 'TA', 'Student', 'Guest')),
    ClearanceLevel INT NOT NULL DEFAULT 0,
    Student_PK_ID INT NULL, 
    InstructorID INT NULL,
    
    CONSTRAINT FK_USERS_STUDENT FOREIGN KEY (Student_PK_ID) 
        REFERENCES STUDENT(PK_ID),
    CONSTRAINT FK_USERS_INSTRUCTOR FOREIGN KEY (InstructorID) 
        REFERENCES INSTRUCTOR(InstructorID),
    CONSTRAINT FK_USERS_Clearance FOREIGN KEY (ClearanceLevel) 
        REFERENCES SecurityLevels(LevelID)
);
GO

CREATE TABLE TA_COURSES (
    TAUsername NVARCHAR(50),
    CourseID INT,
    CONSTRAINT FK_TA_COURSES_User FOREIGN KEY (TAUsername) 
        REFERENCES USERS(Username),
    CONSTRAINT FK_TA_COURSES_Course FOREIGN KEY (CourseID) 
        REFERENCES COURSE(CourseID),
    PRIMARY KEY (TAUsername, CourseID)
);
GO

CREATE TABLE AuditLog (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    Username NVARCHAR(50),
    Action NVARCHAR(100),
    TableName NVARCHAR(50),
    RecordID INT,
    Timestamp DATETIME DEFAULT GETDATE()
);
GO

CREATE TABLE RoleRequests (
    RequestID INT IDENTITY(1,1) PRIMARY KEY,
    Username NVARCHAR(50) NOT NULL,
    CurrentRole NVARCHAR(20) NOT NULL,
    RequestedRole NVARCHAR(20) NOT NULL,
    Reason NVARCHAR(500),
    Status NVARCHAR(20) DEFAULT 'Pending',
    SubmittedDate DATETIME DEFAULT GETDATE(),
    ReviewedDate DATETIME NULL,
    ReviewedBy NVARCHAR(50) NULL,
    Comments NVARCHAR(500) NULL,
    
    CONSTRAINT FK_RoleRequests_Users FOREIGN KEY (Username) 
        REFERENCES USERS(Username),
    CONSTRAINT CHK_RoleRequests_Status CHECK (Status IN ('Pending', 'Approved', 'Denied')),
    CONSTRAINT CHK_RoleRequests_Roles CHECK (
        (CurrentRole = 'Student' AND RequestedRole IN ('TA','Instructor')) OR
        (CurrentRole = 'TA' AND RequestedRole = 'Instructor')
    )
);
GO
-- C. ENCRYPTION KEYS SETUP
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'SecureSRMS@MasterKey2024!';
GO

CREATE CERTIFICATE SRMS_Certificate 
WITH SUBJECT = 'SRMS Data Encryption Certificate';
GO

CREATE SYMMETRIC KEY SRMS_SymmetricKey 
WITH ALGORITHM = AES_256 
ENCRYPTION BY CERTIFICATE SRMS_Certificate;
GO
-- D. SECURITY TRIGGERS (Flow Control: No Write Down & Comprehensive Auditing)
-- Flow Control: No Write Down 
CREATE TRIGGER trg_PreventWriteDown
ON STUDENT
AFTER UPDATE
AS
BEGIN
    IF UPDATE(Classification) AND EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON i.PK_ID = d.PK_ID
        WHERE i.Classification < d.Classification
    )
    BEGIN
        ROLLBACK;
        RAISERROR ('No Write Down Violation: Cannot downgrade data classification.', 16, 1);
    END
END;
GO

-- Comprehensive Audit Trigger on Student (Fix 8)
CREATE TRIGGER trg_AuditStudentChanges
ON STUDENT
AFTER UPDATE, DELETE
AS
BEGIN
    DECLARE @Username NVARCHAR(50) = CAST(SESSION_CONTEXT(N'Username') AS NVARCHAR(50));
    IF @Username IS NULL SET @Username = SUSER_NAME(); -- Fallback

    IF EXISTS (SELECT 1 FROM deleted) AND NOT EXISTS (SELECT 1 FROM inserted) -- DELETE
    BEGIN
        INSERT INTO AuditLog (Username, Action, TableName, RecordID)
        SELECT @Username, 'DELETE', 'STUDENT', d.PK_ID
        FROM deleted d;
    END
    ELSE IF EXISTS (SELECT 1 FROM deleted) AND EXISTS (SELECT 1 FROM inserted) -- UPDATE
    BEGIN
        INSERT INTO AuditLog (Username, Action, TableName, RecordID)
        SELECT @Username, 'UPDATE', 'STUDENT', i.PK_ID
        FROM inserted i
        JOIN deleted d ON i.PK_ID = d.PK_ID
        WHERE d.FullName != i.FullName 
        OR d.Email != i.Email 
        OR d.Classification != i.Classification
    END
END;
GO
-- E. STORED PROCEDURES (Hashing, Session Context, Workflow, Attendance)
-- Login Procedure 
CREATE PROCEDURE sp_Login
    @Username NVARCHAR(50),
    @Password NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Clearance INT, @Role NVARCHAR(20), @PK_ID INT;
    
    SELECT 
        @Clearance = ClearanceLevel, 
        @Role = Role, 
        @PK_ID = Student_PK_ID 
    FROM USERS
    WHERE Username = @Username 
    AND PasswordHash = HASHBYTES('SHA2_256', @Password); 
    
    EXEC sys.sp_set_session_context @key = N'Username', @value = NULL;
    EXEC sys.sp_set_session_context @key = N'Clearance', @value = 0;
    EXEC sys.sp_set_session_context @key = N'Student_PK_ID', @value = NULL;
    
    IF @Clearance IS NOT NULL
    BEGIN
        EXEC sys.sp_set_session_context @key = N'Username', @value = @Username;
        EXEC sys.sp_set_session_context @key = N'Clearance', @value = @Clearance;
        EXEC sys.sp_set_session_context @key = N'Student_PK_ID', @value = @PK_ID;

        INSERT INTO AuditLog (Username, Action) 
        VALUES (@Username, 'Login Successful');
        
        SELECT Username, Role, ClearanceLevel, Student_PK_ID, InstructorID
        FROM USERS
        WHERE Username = @Username;
    END
    ELSE
    BEGIN
        INSERT INTO AuditLog (Username, Action) 
        VALUES (@Username, 'Login Failed');
    END
END;
GO

-- Add Student (Handles StudentID Encryption and PK Insertion)
CREATE PROCEDURE sp_AddStudent
    @StudentID_Input NVARCHAR(20), 
    @FullName NVARCHAR(100),
    @Email NVARCHAR(100),
    @Phone NVARCHAR(20),
    @DOB DATE,
    @Department NVARCHAR(50),
    @Classification INT = 1,
    @RequesterUsername NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @RequesterRole NVARCHAR(20);
    DECLARE @RequesterClearance INT;
    DECLARE @NewPKID INT;

    SELECT @RequesterRole = Role, @RequesterClearance = ClearanceLevel 
    FROM USERS WHERE Username = @RequesterUsername;
    
    IF @RequesterRole NOT IN ('Admin', 'Instructor') OR @RequesterClearance < @Classification
    BEGIN
        INSERT INTO AuditLog (Username, Action) VALUES (@RequesterUsername, 'Add Student - Access/MLS Denied');
        RETURN;
    END
    
    OPEN SYMMETRIC KEY SRMS_SymmetricKey 
    DECRYPTION BY CERTIFICATE SRMS_Certificate;
    
    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO STUDENT (StudentID, FullName, Email, Phone, DOB, Department, Classification) 
        VALUES (
            ENCRYPTBYKEY(KEY_GUID('SRMS_SymmetricKey'), @StudentID_Input), 
            @FullName, @Email,
            ENCRYPTBYKEY(KEY_GUID('SRMS_SymmetricKey'), @Phone),
            @DOB, @Department, @Classification
        );
        
        SET @NewPKID = SCOPE_IDENTITY(); 

        INSERT INTO AuditLog (Username, Action, TableName, RecordID)
        VALUES (@RequesterUsername, 'Add Student', 'STUDENT', @NewPKID);
        
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
    
    CLOSE SYMMETRIC KEY SRMS_SymmetricKey;
END;
GO

-- Add Grade 
CREATE PROCEDURE sp_AddGrade
    @Student_PK_ID INT,
    @CourseID INT,
    @GradeValue DECIMAL(5,2),
    @InstructorUsername NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @InstructorRole NVARCHAR(20), @InstructorClearance INT;
    SELECT @InstructorRole = Role, @InstructorClearance = ClearanceLevel FROM USERS WHERE Username = @InstructorUsername;
    
    IF @InstructorRole != 'Instructor' RETURN;

    DECLARE @GradeClassification INT = 2; 
    
    IF @InstructorClearance < @GradeClassification RETURN;
    
    OPEN SYMMETRIC KEY SRMS_SymmetricKey 
    DECRYPTION BY CERTIFICATE SRMS_Certificate;

    BEGIN TRY
        BEGIN TRANSACTION;
        
        INSERT INTO GRADES (Student_PK_ID, CourseID, GradeValue, Classification)
        VALUES (
            @Student_PK_ID,
            @CourseID,
            ENCRYPTBYKEY(KEY_GUID('SRMS_SymmetricKey'), CAST(@GradeValue AS NVARCHAR(20))),
            @GradeClassification
        );
        
        INSERT INTO AuditLog (Username, Action, TableName)
        VALUES (@InstructorUsername, 'Add Grade', 'GRADES');
        
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    END CATCH
    
    CLOSE SYMMETRIC KEY SRMS_SymmetricKey;
END;
GO

-- Get Grades Procedure (MLS NRU, Inference Control: Query Set Size)
CREATE PROCEDURE sp_GetGrades
    @CourseID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @RequesterUsername NVARCHAR(50) = CAST(SESSION_CONTEXT(N'Username') AS NVARCHAR(50));
    DECLARE @RequesterClearance INT = CAST(SESSION_CONTEXT(N'Clearance') AS INT);
    
    IF @RequesterClearance IS NULL OR @RequesterClearance = 0 
    BEGIN
        INSERT INTO AuditLog (Username, Action) VALUES (@RequesterUsername, 'View Grades - Clearance Unknown/Too Low');
        RETURN;
    END

    -- Inference Control: Query Set Size Control (minimum group size = 3)
    DECLARE @RecordCount INT;
    
    SELECT @RecordCount = COUNT(g.GradeID)
    FROM GRADES g
    WHERE g.CourseID = @CourseID AND g.Classification <= @RequesterClearance; 
    
    IF @RecordCount < 3
    BEGIN
        INSERT INTO AuditLog (Username, Action) 
        VALUES (@RequesterUsername, 'View Grades - Inference Control Blocked (Count: ' + CAST(@RecordCount AS NVARCHAR) + ')');
        RETURN;
    END
    
    OPEN SYMMETRIC KEY SRMS_SymmetricKey DECRYPTION BY CERTIFICATE SRMS_Certificate;
    
    SELECT 
        g.GradeID, CONVERT(NVARCHAR(20), DECRYPTBYKEY(s.StudentID)) AS StudentID, s.FullName, c.CourseName,
        CONVERT(DECIMAL(5,2), CONVERT(NVARCHAR(20), DECRYPTBYKEY(g.GradeValue))) AS Grade, 
        g.DateEntered, sl.LevelName AS SecurityLevel
    FROM GRADES g INNER JOIN STUDENT s ON g.Student_PK_ID = s.PK_ID
    INNER JOIN COURSE c ON g.CourseID = c.CourseID
    INNER JOIN SecurityLevels sl ON g.Classification = sl.LevelID
    WHERE g.CourseID = @CourseID AND g.Classification <= @RequesterClearance 
    ORDER BY s.FullName;
    
    INSERT INTO AuditLog (Username, Action, TableName) VALUES (@RequesterUsername, 'View Grades', 'GRADES');
    
    CLOSE SYMMETRIC KEY SRMS_SymmetricKey;
END;
GO

-- Get Aggregate Grades Procedure (Inference Control - Fix 3: Aggregates Check)
CREATE PROCEDURE sp_GetAggregateGrades
    @CourseID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @RequesterUsername NVARCHAR(50) = CAST(SESSION_CONTEXT(N'Username') AS NVARCHAR(50));
    DECLARE @RequesterClearance INT = CAST(SESSION_CONTEXT(N'Clearance') AS INT);

    IF @RequesterClearance IS NULL OR @RequesterClearance = 0 RETURN;

    DECLARE @RecordCount INT;
    SELECT @RecordCount = COUNT(g.GradeID)
    FROM GRADES g WHERE g.CourseID = @CourseID AND g.Classification <= @RequesterClearance; 

    IF @RecordCount < 3
    BEGIN
        INSERT INTO AuditLog (Username, Action) 
        VALUES (@RequesterUsername, 'View Aggregates - Inference Control Blocked (Count: ' + CAST(@RecordCount AS NVARCHAR) + ')');
        RETURN;
    END
    
    OPEN SYMMETRIC KEY SRMS_SymmetricKey DECRYPTION BY CERTIFICATE SRMS_Certificate;

    SELECT
        c.CourseName, COUNT(g.GradeID) AS TotalGrades,
        AVG(CONVERT(DECIMAL(5,2), CONVERT(NVARCHAR(20), DECRYPTBYKEY(g.GradeValue)))) AS AverageGrade,
        MIN(CONVERT(DECIMAL(5,2), CONVERT(NVARCHAR(20), DECRYPTBYKEY(g.GradeValue)))) AS MinimumGrade,
        MAX(CONVERT(DECIMAL(5,2), CONVERT(NVARCHAR(20), DECRYPTBYKEY(g.GradeValue)))) AS MaximumGrade
    FROM GRADES g INNER JOIN COURSE c ON g.CourseID = c.CourseID
    WHERE g.CourseID = @CourseID AND g.Classification <= @RequesterClearance
    GROUP BY c.CourseName;

    CLOSE SYMMETRIC KEY SRMS_SymmetricKey;
    INSERT INTO AuditLog (Username, Action, TableName) VALUES (@RequesterUsername, 'View Aggregate Grades', 'GRADES');
END;
GO

-- Get Student Profile (Phone and StudentID Decryption)
CREATE PROCEDURE sp_GetStudentProfile
    @Username NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @PK_ID INT = CAST(SESSION_CONTEXT(N'Student_PK_ID') AS INT);
    DECLARE @Clearance INT = CAST(SESSION_CONTEXT(N'Clearance') AS INT);
    
    IF @PK_ID IS NULL RETURN;
    
    OPEN SYMMETRIC KEY SRMS_SymmetricKey DECRYPTION BY CERTIFICATE SRMS_Certificate;
    
    SELECT 
        s.PK_ID, CONVERT(NVARCHAR(20), DECRYPTBYKEY(s.StudentID)) AS StudentID, s.FullName, s.Email,
        CONVERT(NVARCHAR(20), DECRYPTBYKEY(s.Phone)) AS Phone, 
        s.DOB, s.Department, sl.LevelName AS SecurityLevel
    FROM STUDENT s INNER JOIN SecurityLevels sl ON s.Classification = sl.LevelID
    WHERE s.PK_ID = @PK_ID AND s.Classification <= @Clearance;
    
    CLOSE SYMMETRIC KEY SRMS_SymmetricKey;
END;
GO

-- NEW: Update Attendance Procedure (RBAC Scope, MLS Check)
CREATE PROCEDURE sp_UpdateAttendance
    @AttendanceID INT,
    @NewStatus BIT,
    @TAUsername NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TARole NVARCHAR(20), @TAClearance INT;
    DECLARE @CourseID INT, @RecordClassification INT;

    SELECT @TARole = Role, @TAClearance = ClearanceLevel FROM USERS WHERE Username = @TAUsername;
    
    -- RBAC Check: Must be a TA
    IF @TARole != 'TA' 
    BEGIN
        INSERT INTO AuditLog (Username, Action) VALUES (@TAUsername, 'RBAC Violation: Tried to update attendance (Not TA)');
        RETURN;
    END

    -- Get record details for RBAC Scope and MLS Check
    SELECT 
        @CourseID = a.CourseID,
        @RecordClassification = a.Classification
    FROM ATTENDANCE a
    WHERE a.AttendanceID = @AttendanceID;

    -- RBAC Scope Check: TA must be assigned to the course
    IF NOT EXISTS (SELECT 1 FROM TA_COURSES WHERE TAUsername = @TAUsername AND CourseID = @CourseID)
    BEGIN
        INSERT INTO AuditLog (Username, Action) VALUES (@TAUsername, 'RBAC Scope Violation: Tried to update unassigned course attendance');
        RETURN;
    END

    -- MLS Write Check: TA must have clearance >= record classification
    IF @TAClearance < @RecordClassification
    BEGIN
        INSERT INTO AuditLog (Username, Action) VALUES (@TAUsername, 'MLS Write Violation: Tried to update higher classified attendance');
        RETURN;
    END

    -- Update Attendance
    UPDATE ATTENDANCE 
    SET Status = @NewStatus, 
        DateRecorded = GETDATE()
    WHERE AttendanceID = @AttendanceID;

    INSERT INTO AuditLog (Username, Action, TableName, RecordID)
    VALUES (@TAUsername, 'Updated Attendance', 'ATTENDANCE', @AttendanceID);
END;
GO

-- Role Request Workflow SPs 
CREATE PROCEDURE sp_SubmitRoleRequest
    @Username NVARCHAR(50),
    @RequestedRole NVARCHAR(20),
    @Reason NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CurrentRole NVARCHAR(20);
    SELECT @CurrentRole = Role FROM USERS WHERE Username = @Username;

    IF @CurrentRole IS NULL OR @CurrentRole = 'Admin' OR @CurrentRole = 'Guest' RETURN;
    
    INSERT INTO RoleRequests (Username, CurrentRole, RequestedRole, Reason)
    VALUES (@Username, @CurrentRole, @RequestedRole, @Reason);

    INSERT INTO AuditLog (Username, Action) VALUES (@Username, 'Submitted Role Request for ' + @RequestedRole);
END;
GO

CREATE PROCEDURE sp_GetPendingRequests
    @AdminUsername NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AdminRole NVARCHAR(20);
    SELECT @AdminRole = Role FROM USERS WHERE Username = @AdminUsername;
    
    IF @AdminRole != 'Admin' 
    BEGIN
        INSERT INTO AuditLog (Username, Action) VALUES (@AdminUsername, 'RBAC Violation: Tried to view role requests (Not Admin)');
        RETURN;
    END
    
    SELECT * FROM RoleRequests WHERE Status = 'Pending' ORDER BY SubmittedDate;

    INSERT INTO AuditLog (Username, Action) VALUES (@AdminUsername, 'Viewed Pending Role Requests');
END;
GO

CREATE PROCEDURE sp_ApproveRequest
    @RequestID INT,
    @AdminUsername NVARCHAR(50),
    @Comments NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AdminRole NVARCHAR(20), @TargetUsername NVARCHAR(50), @NewRole NVARCHAR(20), @NewClearance INT;
    SELECT @AdminRole = Role FROM USERS WHERE Username = @AdminUsername;
    
    IF @AdminRole != 'Admin' RETURN;
    
    SELECT @TargetUsername = Username, @NewRole = RequestedRole
    FROM RoleRequests WHERE RequestID = @RequestID AND Status = 'Pending';
    
    IF @TargetUsername IS NULL RETURN;

    -- Determine new clearance level based on the role
    SET @NewClearance = CASE @NewRole WHEN 'TA' THEN 1 WHEN 'Instructor' THEN 2 ELSE (SELECT ClearanceLevel FROM USERS WHERE Username = @TargetUsername) END;

    BEGIN TRANSACTION;
    
    -- 1. Update the USERS role and clearance 
    UPDATE USERS 
    SET Role = @NewRole, 
        ClearanceLevel = @NewClearance
    WHERE Username = @TargetUsername;

    -- 2. Update the request status
    UPDATE RoleRequests SET 
        Status = 'Approved', 
        ReviewedBy = @AdminUsername, 
        ReviewedDate = GETDATE(),
        Comments = @Comments
    WHERE RequestID = @RequestID;

    INSERT INTO AuditLog (Username, Action) VALUES (@AdminUsername, 'Approved Role Request for ' + @TargetUsername + ' to ' + @NewRole);
    
    COMMIT TRANSACTION;
END;
GO

CREATE PROCEDURE sp_DenyRequest
    @RequestID INT,
    @AdminUsername NVARCHAR(50),
    @Comments NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AdminRole NVARCHAR(20);
    SELECT @AdminRole = Role FROM USERS WHERE Username = @AdminUsername;
    
    IF @AdminRole != 'Admin' RETURN;
    
    -- Update the request status only (No change to USERS table)
    UPDATE RoleRequests SET 
        Status = 'Denied', 
        ReviewedBy = @AdminUsername, 
        ReviewedDate = GETDATE(),
        Comments = @Comments
    WHERE RequestID = @RequestID AND Status = 'Pending';

    INSERT INTO AuditLog (Username, Action) VALUES (@AdminUsername, 'Denied Role Request ID: ' + CAST(@RequestID AS NVARCHAR));
END;
GO
-- F. VIEWS DEFINITION 
CREATE VIEW vw_Public_Courses AS
SELECT CourseID, CourseName, PublicInfo FROM COURSE WHERE Classification = 0;
GO

CREATE VIEW vw_Student_OwnData AS
SELECT 
    s.PK_ID, CONVERT(NVARCHAR(20), DECRYPTBYKEY(s.StudentID)) AS StudentID, 
    s.FullName, s.Email, s.DOB, s.Department, sl.LevelName AS SecurityLevel
FROM STUDENT s INNER JOIN SecurityLevels sl ON s.Classification = sl.LevelID
WHERE s.PK_ID = CAST(SESSION_CONTEXT(N'Student_PK_ID') AS INT)
AND s.Classification <= CAST(SESSION_CONTEXT(N'Clearance') AS INT)
GO

CREATE VIEW vw_Instructor_Students AS
SELECT 
    s.PK_ID, s.FullName, s.Email, s.Department, sl.LevelName AS SecurityLevel
FROM STUDENT s INNER JOIN SecurityLevels sl ON s.Classification = sl.LevelID
WHERE s.Classification <= CAST(SESSION_CONTEXT(N'Clearance') AS INT)
GO

CREATE VIEW vw_TA_AssignedStudents AS
SELECT DISTINCT
    s.PK_ID, s.FullName, s.Email, s.Department, c.CourseName, sl.LevelName AS SecurityLevel
FROM STUDENT s
INNER JOIN GRADES g ON s.PK_ID = g.Student_PK_ID
INNER JOIN TA_COURSES tc ON g.CourseID = tc.CourseID
INNER JOIN COURSE c ON g.CourseID = c.CourseID
INNER JOIN SecurityLevels sl ON s.Classification = sl.LevelID
WHERE tc.TAUsername = CAST(SESSION_CONTEXT(N'Username') AS NVARCHAR(50))
AND s.Classification <= CAST(SESSION_CONTEXT(N'Clearance') AS INT)
GO

-- G. SQL ROLES AND PERMISSIONS (RBAC) 
-- Admin Permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON STUDENT TO db_Admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON INSTRUCTOR TO db_Admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON COURSE TO db_Admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON GRADES TO db_Admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ATTENDANCE TO db_Admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON USERS TO db_Admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON AuditLog TO db_Admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON TA_COURSES TO db_Admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON RoleRequests TO db_Admin;
GRANT SELECT ON SecurityLevels TO db_Admin;
GRANT EXECUTE TO db_Admin;

-- Instructor Permissions
GRANT SELECT ON STUDENT TO db_Instructor;
GRANT SELECT ON COURSE TO db_Instructor;
GRANT SELECT, INSERT, UPDATE ON GRADES TO db_Instructor;
GRANT SELECT ON ATTENDANCE TO db_Instructor;
GRANT EXECUTE ON sp_AddStudent TO db_Instructor;
GRANT EXECUTE ON sp_AddGrade TO db_Instructor;
GRANT EXECUTE ON sp_GetGrades TO db_Instructor;
GRANT EXECUTE ON sp_GetAggregateGrades TO db_Instructor;
GRANT EXECUTE ON sp_SubmitRoleRequest TO db_Instructor;
GRANT SELECT ON vw_Instructor_Students TO db_Instructor;
GRANT SELECT ON vw_Public_Courses TO db_Instructor;
GO

-- TA Permissions
GRANT SELECT ON STUDENT TO db_TA;
GRANT SELECT ON COURSE TO db_TA;
GRANT SELECT, INSERT, UPDATE ON ATTENDANCE TO db_TA;
GRANT EXECUTE ON sp_UpdateAttendance TO db_TA;
GRANT EXECUTE ON sp_SubmitRoleRequest TO db_TA;
GRANT SELECT ON vw_TA_AssignedStudents TO db_TA;
GO

-- Student Permissions
GRANT EXECUTE ON sp_GetStudentProfile TO db_Student;
GRANT EXECUTE ON sp_SubmitRoleRequest TO db_Student;
GRANT SELECT ON vw_Student_OwnData TO db_Student;
GRANT SELECT ON vw_Public_Courses TO db_Student;
GO

-- Guest Permissions (View-Only Isolation)
GRANT SELECT ON SecurityLevels TO db_Guest;
GRANT SELECT ON COURSE TO db_Guest;
GRANT SELECT ON vw_Public_Courses TO db_Guest;
-- NO EXECUTE or DML granted.
GO

-- General Permissions
GRANT EXECUTE ON sp_Login TO PUBLIC; 
GRANT EXECUTE ON sp_SubmitRoleRequest TO PUBLIC; 
GO
-- H. INITIAL DATA SEEDING (FIXED BATCH SCOPE)
INSERT INTO COURSE (CourseID, CourseName, Description, PublicInfo, Classification) VALUES
(101, 'Database Security', 'Advanced database protection techniques', 'Learn how to secure databases', 0),
(102, 'Network Security', 'Network protection and firewalls', 'Network defense fundamentals', 0),
(103, 'Cryptography', 'Encryption algorithms and protocols', 'Study encryption methods', 0),
(104, 'Advanced Security', 'Top secret security topics', 'Classified course content', 2);
GO

INSERT INTO INSTRUCTOR (InstructorID, FullName, Email, ClearanceLevel) VALUES
(5001, 'Dr. Ahmed Zaki', 'ahmed.zaki@university.edu', 3),
(5002, 'Dr. Mona Ali', 'mona.ali@university.edu', 3),
(5003, 'Prof. Samir Mohamed', 'samir@university.edu', 3);
GO

-- Add Students 
EXEC sp_AddStudent '1001', 'Ali Hassan Mohamed', 'ali.hassan@student.edu', '01012345678', '2000-05-15', 'Computer Science', 1, 'admin';
EXEC sp_AddStudent '1002', 'Sara Ahmed Ali', 'sara.ahmed@student.edu', '01023456789', '2001-03-20', 'Computer Science', 1, 'admin';
EXEC sp_AddStudent '1003', 'Omar Mahmoud Hassan', 'omar.mahmoud@student.edu', '01034567890', '1999-11-10', 'Information Technology', 1, 'admin';
EXEC sp_AddStudent '1004', 'Fatima Khaled Ibrahim', 'fatima.khaled@student.edu', '01045678901', '2000-07-30', 'Computer Science', 1, 'admin';
EXEC sp_AddStudent '1005', 'Khaled Samir Farouk', 'khaled.samir@student.edu', '01056789012', '2001-01-25', 'Information Technology', 1, 'admin';
GO

-- START OF CONSOLIDATED BATCH
-- Get PK_IDs (Defined here)
OPEN SYMMETRIC KEY SRMS_SymmetricKey DECRYPTION BY CERTIFICATE SRMS_Certificate;
DECLARE @PK1 INT = (SELECT PK_ID FROM STUDENT WHERE CONVERT(NVARCHAR(20), DECRYPTBYKEY(StudentID)) = '1001');
DECLARE @PK2 INT = (SELECT PK_ID FROM STUDENT WHERE CONVERT(NVARCHAR(20), DECRYPTBYKEY(StudentID)) = '1002');
DECLARE @PK3 INT = (SELECT PK_ID FROM STUDENT WHERE CONVERT(NVARCHAR(20), DECRYPTBYKEY(StudentID)) = '1003');
DECLARE @PK4 INT = (SELECT PK_ID FROM STUDENT WHERE CONVERT(NVARCHAR(20), DECRYPTBYKEY(StudentID)) = '1004');
DECLARE @PK5 INT = (SELECT PK_ID FROM STUDENT WHERE CONVERT(NVARCHAR(20), DECRYPTBYKEY(StudentID)) = '1005');
CLOSE SYMMETRIC KEY SRMS_SymmetricKey;


-- Insert USERS (Uses @PK1, @PK2, @PK3)
INSERT INTO USERS (Username, PasswordHash, Role, ClearanceLevel, Student_PK_ID, InstructorID) VALUES
('admin', HASHBYTES('SHA2_256', 'admin123'), 'Admin', 3, NULL, NULL),
('instructor1', HASHBYTES('SHA2_256', 'inst123'), 'Instructor', 3, NULL, 5001),
('instructor2', HASHBYTES('SHA2_256', 'inst456'), 'Instructor', 3, NULL, 5002),
('ta1', HASHBYTES('SHA2_256', 'ta123'), 'TA', 1, NULL, NULL),
('guest', HASHBYTES('SHA2_256', 'guest123'), 'Guest', 0, NULL, NULL),
('student1', HASHBYTES('SHA2_256', 'stu123'), 'Student', 1, @PK1, NULL),
('student2', HASHBYTES('SHA2_256', 'stu456'), 'Student', 1, @PK2, NULL),
('student3', HASHBYTES('SHA2_256', 'stu789'), 'Student', 1, @PK3, NULL);

-- TA Course Assignment
INSERT INTO TA_COURSES (TAUsername, CourseID) VALUES ('ta1', 101), ('ta1', 102);

-- Add Grades (Uses @PK1 to @PK5)
EXEC sp_AddGrade @PK1, 101, 95.5, 'instructor1';
EXEC sp_AddGrade @PK2, 101, 88.0, 'instructor1';
EXEC sp_AddGrade @PK3, 101, 92.5, 'instructor1';
EXEC sp_AddGrade @PK4, 101, 85.0, 'instructor1';
EXEC sp_AddGrade @PK5, 101, 78.5, 'instructor1'; -- 5 grades for inference check success
EXEC sp_AddGrade @PK1, 102, 91.0, 'instructor2'; 
EXEC sp_AddGrade @PK2, 102, 84.5, 'instructor2'; -- 2 grades for inference check failure

-- Insert Attendance (Uses @PK1 to @PK5)
INSERT INTO ATTENDANCE (Student_PK_ID, CourseID, Status, Classification) VALUES
(@PK1, 101, 1, 1), -- AttendanceID=1
(@PK2, 101, 1, 1), -- AttendanceID=2
(@PK3, 101, 0, 1), -- AttendanceID=3
(@PK4, 101, 1, 1),
(@PK1, 102, 1, 1), -- AttendanceID=5 (Course 102 - assigned to ta1)
(@PK5, 103, 1, 1); -- AttendanceID=6 (Course 103 - NOT assigned to ta1, for RBAC scope check)

-- Initial Role Requests 
EXEC sp_SubmitRoleRequest 'student1', 'TA', 'I want to assist with course management'; -- RequestID=1
EXEC sp_SubmitRoleRequest 'ta1', 'Instructor', 'Ready to teach after 2 years as TA'; -- RequestID=2
GO 
-- END OF CONSOLIDATED BATCH
--Testing 
EXEC sp_Login 'admin', 'admin123';
-- OUTPUT: Login Successful. Session Context set: Username=admin, Clearance=3.
SELECT * FROM RoleRequests WHERE Username = 'student1';
-- OUTPUT: RequestID=1, Username=student1, CurrentRole=Student, RequestedRole=TA, Status=Pending.
SELECT Role, ClearanceLevel FROM USERS WHERE Username = 'student1';
-- OUTPUT: Role=Student, ClearanceLevel=1.
EXEC sp_ApproveRequest 1, 'admin', 'Approved based on high GPA.';

SELECT * FROM RoleRequests WHERE RequestID = 1;
-- OUTPUT: Status=Approved, ReviewedBy=admin.
SELECT Role, ClearanceLevel FROM USERS WHERE Username = 'student1';
-- OUTPUT: Role=TA, ClearanceLevel=1. 
EXEC sp_Login 'instructor2', 'inst456'; 
EXEC sp_GetGrades 102; 

