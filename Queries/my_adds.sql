USE SecureSRMS;

-- Fix seeded users password hashes to match sp_Login (NVARCHAR hashing)
UPDATE USERS SET PasswordHash = HASHBYTES('SHA2_256', N'admin123')      WHERE Username='admin';
UPDATE USERS SET PasswordHash = HASHBYTES('SHA2_256', N'inst123')       WHERE Username='instructor1';
UPDATE USERS SET PasswordHash = HASHBYTES('SHA2_256', N'inst456')       WHERE Username='instructor2';
UPDATE USERS SET PasswordHash = HASHBYTES('SHA2_256', N'ta123')         WHERE Username='ta1';
UPDATE USERS SET PasswordHash = HASHBYTES('SHA2_256', N'guest123')      WHERE Username='guest';
UPDATE USERS SET PasswordHash = HASHBYTES('SHA2_256', N'stu123')        WHERE Username='student1';
UPDATE USERS SET PasswordHash = HASHBYTES('SHA2_256', N'stu456')        WHERE Username='student2';
UPDATE USERS SET PasswordHash = HASHBYTES('SHA2_256', N'stu789')        WHERE Username='student3';




USE SecureSRMS;
GO

/* =========================================================
   1) sp_AdminListUsers
   ========================================================= */
CREATE OR ALTER PROCEDURE sp_AdminListUsers
    @AdminUsername NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- RBAC: Admin only
    IF NOT EXISTS (
        SELECT 1 FROM USERS
        WHERE Username = @AdminUsername AND Role = 'Admin'
    )
    BEGIN
        INSERT INTO AuditLog (Username, Action)
        VALUES (@AdminUsername, 'RBAC Violation: Tried to list users (Not Admin)');
        RETURN;
    END

    SELECT Username, Role, ClearanceLevel, Student_PK_ID, InstructorID
    FROM USERS
    ORDER BY Username;

    INSERT INTO AuditLog (Username, Action)
    VALUES (@AdminUsername, 'Admin listed users');
END;
GO


/* =========================================================
   2) sp_AdminCreateUser
   ========================================================= */
CREATE OR ALTER PROCEDURE sp_AdminCreateUser
    @AdminUsername NVARCHAR(50),
    @NewUsername NVARCHAR(50),
    @NewPassword NVARCHAR(100),
    @NewRole NVARCHAR(20),
    @ClearanceLevel INT = NULL,
    @Student_PK_ID INT = NULL,
    @InstructorID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- RBAC: Admin only
    IF NOT EXISTS (
        SELECT 1 FROM USERS
        WHERE Username = @AdminUsername AND Role = 'Admin'
    )
    BEGIN
        INSERT INTO AuditLog (Username, Action)
        VALUES (@AdminUsername, 'RBAC Violation: Tried to create user (Not Admin)');
        RETURN;
    END

    -- Basic validation
    IF @NewUsername IS NULL OR LTRIM(RTRIM(@NewUsername)) = ''
        OR @NewPassword IS NULL OR LTRIM(RTRIM(@NewPassword)) = ''
        OR @NewRole IS NULL OR LTRIM(RTRIM(@NewRole)) = ''
    BEGIN
        INSERT INTO AuditLog (Username, Action)
        VALUES (@AdminUsername, 'Admin create user failed: Missing fields');
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM USERS WHERE Username = @NewUsername)
    BEGIN
        INSERT INTO AuditLog (Username, Action)
        VALUES (@AdminUsername, 'Admin create user failed: Username exists (' + @NewUsername + ')');
        RETURN;
    END

    -- Default clearance mapping if not provided
    IF @ClearanceLevel IS NULL
    BEGIN
        SET @ClearanceLevel =
            CASE @NewRole
                WHEN 'Admin' THEN 3
                WHEN 'Instructor' THEN 3
                WHEN 'TA' THEN 1
                WHEN 'Student' THEN 1
                WHEN 'Guest' THEN 0
                ELSE 0
            END
    END

    -- Role constraints (important)
    IF @NewRole = 'Student' AND @Student_PK_ID IS NULL
    BEGIN
        INSERT INTO AuditLog (Username, Action)
        VALUES (@AdminUsername, 'Admin create user failed: Student requires Student_PK_ID');
        RETURN;
    END

    IF @NewRole = 'Instructor' AND @InstructorID IS NULL
    BEGIN
        INSERT INTO AuditLog (Username, Action)
        VALUES (@AdminUsername, 'Admin create user failed: Instructor requires InstructorID');
        RETURN;
    END

    IF @NewRole IN ('TA','Guest','Admin')
    BEGIN
        -- force these null
        SET @Student_PK_ID = NULL;
        SET @InstructorID = NULL;
    END

    -- Create user (hash exactly like sp_Login expects: NVARCHAR input)
    INSERT INTO USERS (Username, PasswordHash, Role, ClearanceLevel, Student_PK_ID, InstructorID)
    VALUES (@NewUsername, HASHBYTES('SHA2_256', @NewPassword), @NewRole, @ClearanceLevel, @Student_PK_ID, @InstructorID);

    INSERT INTO AuditLog (Username, Action, TableName)
    VALUES (@AdminUsername, 'Admin created user: ' + @NewUsername + ' as ' + @NewRole, 'USERS');
END;
GO


/* =========================================================
   3) sp_AdminUpdateUserRole
   ========================================================= */
CREATE OR ALTER PROCEDURE sp_AdminUpdateUserRole
    @AdminUsername NVARCHAR(50),
    @TargetUsername NVARCHAR(50),
    @NewRole NVARCHAR(20),
    @NewClearance INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- RBAC: Admin only
    IF NOT EXISTS (
        SELECT 1 FROM USERS
        WHERE Username = @AdminUsername AND Role = 'Admin'
    )
    BEGIN
        INSERT INTO AuditLog (Username, Action)
        VALUES (@AdminUsername, 'RBAC Violation: Tried to update user role (Not Admin)');
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM USERS WHERE Username = @TargetUsername)
    BEGIN
        INSERT INTO AuditLog (Username, Action)
        VALUES (@AdminUsername, 'Admin update role failed: User not found (' + @TargetUsername + ')');
        RETURN;
    END

    DECLARE @OldRole NVARCHAR(20);
    SELECT @OldRole = Role FROM USERS WHERE Username = @TargetUsername;

    IF @NewClearance IS NULL
    BEGIN
        SET @NewClearance =
            CASE @NewRole
                WHEN 'Admin' THEN 3
                WHEN 'Instructor' THEN 3
                WHEN 'TA' THEN 1
                WHEN 'Student' THEN 1
                WHEN 'Guest' THEN 0
                ELSE (SELECT ClearanceLevel FROM USERS WHERE Username = @TargetUsername)
            END
    END

    UPDATE USERS
    SET Role = @NewRole,
        ClearanceLevel = @NewClearance
    WHERE Username = @TargetUsername;

    INSERT INTO AuditLog (Username, Action, TableName)
    VALUES (@AdminUsername, 'Admin changed role: ' + @TargetUsername + ' ' + @OldRole + ' -> ' + @NewRole, 'USERS');
END;
GO





--test
USE SecureSRMS;
OPEN SYMMETRIC KEY SRMS_SymmetricKey DECRYPTION BY CERTIFICATE SRMS_Certificate;

SELECT PK_ID, CONVERT(NVARCHAR(20), DECRYPTBYKEY(StudentID)) AS StudentID, FullName
FROM STUDENT
WHERE CONVERT(NVARCHAR(20), DECRYPTBYKEY(StudentID)) = '2001';

CLOSE SYMMETRIC KEY SRMS_SymmetricKey;
