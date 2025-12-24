USE SRMS;
GO

/* =========================================================
   FIX #1: Add profile fields for Admin/TA inside USERS
   ========================================================= */

IF COL_LENGTH('dbo.USERS', 'FullName') IS NULL
BEGIN
    ALTER TABLE dbo.USERS ADD FullName NVARCHAR(100) NULL;
END
GO

IF COL_LENGTH('dbo.USERS', 'Email') IS NULL
BEGIN
    ALTER TABLE dbo.USERS ADD Email NVARCHAR(100) NULL;
END
GO


/* =========================================================
   FIX #2: Seed default FullName/Email for existing Admin/TA/Instructor
   (Optional but recommended so /info isn't empty)
   ========================================================= */

-- Admin (username ad)
UPDATE dbo.USERS
SET FullName = ISNULL(FullName, N'Administrator'),
    Email    = ISNULL(Email,    N'admin@uni.edu')
WHERE Role = 'Admin';

-- TA (username ta)
UPDATE dbo.USERS
SET FullName = ISNULL(FullName, N'Teaching Assistant'),
    Email    = ISNULL(Email,    N'ta@uni.edu')
WHERE Role = 'TA';

-- Instructor (we usually store profile in INSTRUCTOR, but keep fallback)
UPDATE dbo.USERS
SET FullName = ISNULL(FullName, N'Instructor'),
    Email    = ISNULL(Email,    N'instructor@uni.edu')
WHERE Role = 'Instructor';
GO


/* =========================================================
   FIX #3: Admin/TA View their own profile from USERS
   ========================================================= */

CREATE OR ALTER PROCEDURE dbo.sp_ViewMyUserProfile
    @UserRole NVARCHAR(50),
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserRole NOT IN ('Admin','TA')
    BEGIN
        RAISERROR('Access Denied.',16,1);
        RETURN;
    END

    SELECT UserID, Role, ClearanceLevel, FullName, Email
    FROM dbo.USERS
    WHERE UserID = @UserID;
END
GO

GRANT EXECUTE ON dbo.sp_ViewMyUserProfile TO Admin;
GRANT EXECUTE ON dbo.sp_ViewMyUserProfile TO TA;
GO


/* =========================================================
   FIX #4: Student/Admin edit student profile (safe)
   ========================================================= */

CREATE OR ALTER PROCEDURE dbo.sp_EditStudent_Profile
    @UserRole NVARCHAR(50),
    @UserID INT,
    @StudentID INT,
    @FullName NVARCHAR(100),
    @Email NVARCHAR(100),
    @Department NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserRole NOT IN ('Admin','Student')
    BEGIN
        RAISERROR('Access Denied.',16,1);
        RETURN;
    END

    -- Student can edit ONLY his own StudentID
    IF @UserRole = 'Student'
    BEGIN
        DECLARE @OwnStudentID INT;
        SELECT @OwnStudentID = StudentID
        FROM dbo.USERS
        WHERE UserID = @UserID AND Role='Student';

        IF @OwnStudentID IS NULL OR @OwnStudentID <> @StudentID
        BEGIN
            RAISERROR('Students can edit only their own profile.',16,1);
            RETURN;
        END
    END

    UPDATE dbo.STUDENT
    SET FullName = @FullName,
        Email = @Email,
        Department = @Department
    WHERE StudentID = @StudentID;

    IF @@ROWCOUNT = 0
        RAISERROR('Student not found.',16,1);
END
GO

GRANT EXECUTE ON dbo.sp_EditStudent_Profile TO Student;
GRANT EXECUTE ON dbo.sp_EditStudent_Profile TO Admin;
GO


/* =========================================================
   FIX #5: Unified edit "My Profile" route for /info
   - Admin/TA edit USERS.FullName/Email
   - Student edits STUDENT (own)
   - Instructor edits INSTRUCTOR (own)
   ========================================================= */

CREATE OR ALTER PROCEDURE dbo.sp_EditMyProfile
    @UserRole NVARCHAR(50),
    @UserID INT,
    @FullName NVARCHAR(100),
    @Email NVARCHAR(100),
    @DOB DATE = NULL,
    @Department NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserRole NOT IN ('Admin','Instructor','TA','Student')
    BEGIN
        RAISERROR('Access Denied: Editing not allowed.',16,1);
        RETURN;
    END

    -- Student edits his STUDENT record
    IF @UserRole = 'Student'
    BEGIN
        DECLARE @SID INT;
        SELECT @SID = StudentID FROM dbo.USERS WHERE UserID=@UserID AND Role='Student';

        IF @SID IS NULL
        BEGIN
            RAISERROR('Student identity not linked.',16,1);
            RETURN;
        END

        UPDATE dbo.STUDENT
        SET FullName = @FullName,
            Email = @Email,
            DOB = @DOB,
            Department = @Department
        WHERE StudentID = @SID;

        RETURN;
    END

    -- Instructor edits INSTRUCTOR record
    IF @UserRole = 'Instructor'
    BEGIN
        DECLARE @IID INT;
        SELECT @IID = InstructorID FROM dbo.USERS WHERE UserID=@UserID AND Role='Instructor';

        IF @IID IS NULL
        BEGIN
            RAISERROR('Instructor identity not linked.',16,1);
            RETURN;
        END

        UPDATE dbo.INSTRUCTOR
        SET FullName = @FullName,
            Email = @Email
        WHERE InstructorID = @IID;

        RETURN;
    END

    -- Admin / TA edit USERS record
    UPDATE dbo.USERS
    SET FullName = @FullName,
        Email = @Email
    WHERE UserID = @UserID;

END
GO

GRANT EXECUTE ON dbo.sp_EditMyProfile TO Admin;
GRANT EXECUTE ON dbo.sp_EditMyProfile TO TA;
GRANT EXECUTE ON dbo.sp_EditMyProfile TO Instructor;
GRANT EXECUTE ON dbo.sp_EditMyProfile TO Student;
GO
