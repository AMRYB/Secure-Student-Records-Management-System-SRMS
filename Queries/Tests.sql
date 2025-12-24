USE SRMS;
GO

PRINT '==============================';
PRINT 'SRMS FINAL SECURITY TEST SUITE';
PRINT '==============================';
GO


/* ===============================
   0) TEST USERS SETUP
   =============================== */

IF USER_ID('u_student') IS NULL CREATE USER u_student WITHOUT LOGIN;
IF USER_ID('u_ta')      IS NULL CREATE USER u_ta      WITHOUT LOGIN;
IF USER_ID('u_guest')   IS NULL CREATE USER u_guest   WITHOUT LOGIN;
GO

BEGIN TRY ALTER ROLE Student ADD MEMBER u_student; END TRY BEGIN CATCH END CATCH;
BEGIN TRY ALTER ROLE TA      ADD MEMBER u_ta;      END TRY BEGIN CATCH END CATCH;
BEGIN TRY ALTER ROLE Guest   ADD MEMBER u_guest;   END TRY BEGIN CATCH END CATCH;
GO


/* ===============================
   1) ACCESS CONTROL
   =============================== */

-- Test 1 : Direct table access denied
PRINT 'Access Control Test 1';
EXECUTE AS USER = 'u_student';
BEGIN TRY
    SELECT TOP 1 * FROM dbo.STUDENT;
    PRINT 'FAILED';
END TRY
BEGIN CATCH
    PRINT 'PASSED';
END CATCH
REVERT;
GO

-- Test 2 : Stored procedure access allowed
PRINT 'Access Control Test 2';
EXECUTE AS USER = 'u_student';
BEGIN TRY
    EXEC dbo.sp_ViewStudent_Profile
        @UserRole='Student',
        @UserID=4,
        @UserClearance=2,
        @StudentID=NULL;
    PRINT 'PASSED';
END TRY
BEGIN CATCH
    PRINT 'FAILED';
END CATCH
REVERT;
GO


/* ===============================
   2) INFERENCE CONTROL
   =============================== */

-- Test 1 : Aggregate allowed only when count >= 3
PRINT 'Inference Control Test 1';
OPEN SYMMETRIC KEY SRMS_SymKey
DECRYPTION BY CERTIFICATE SRMS_Cert;

SELECT CourseID, AvgGrade, RecordsCount
FROM dbo.vw_AvgGrades_Safe;

CLOSE SYMMETRIC KEY SRMS_SymKey;
GO

-- Test 2 : Aggregate blocked when count < 3
PRINT 'Inference Control Test 2';
DECLARE @C INT;

INSERT INTO dbo.COURSE (CourseName, PublicInfo, InstructorID)
VALUES (N'Inference Test', N'Public', 1);

SET @C = SCOPE_IDENTITY();

EXEC dbo.sp_InsertGrade 'Admin',1,5,1,@C,70;
EXEC dbo.sp_InsertGrade 'Admin',1,5,2,@C,80;

OPEN SYMMETRIC KEY SRMS_SymKey
DECRYPTION BY CERTIFICATE SRMS_Cert;

SELECT * FROM dbo.vw_AvgGrades_Safe WHERE CourseID=@C;

CLOSE SYMMETRIC KEY SRMS_SymKey;
GO


/* ===============================
   3) FLOW CONTROL
   =============================== */

-- Test 1 : No Write Down enforced
PRINT 'Flow Control Test 1';
UPDATE dbo.STUDENT SET ClearanceLevel=4 WHERE StudentID=1;

BEGIN TRY
    EXEC dbo.sp_InsertGrade 'Instructor',2,3,1,1,99;
    PRINT 'FAILED';
END TRY
BEGIN CATCH
    PRINT 'PASSED';
END CATCH
GO

-- Test 2 : High clearance write allowed
PRINT 'Flow Control Test 2';
BEGIN TRY
    EXEC dbo.sp_InsertGrade 'Admin',1,5,1,1,95;
    PRINT 'PASSED';
END TRY
BEGIN CATCH
    PRINT 'FAILED';
END CATCH
GO

UPDATE dbo.STUDENT SET ClearanceLevel=2 WHERE StudentID=1;
GO


/* ===============================
   4) MLS
   =============================== */

-- Test 1 : No Read Up enforced
PRINT 'MLS Test 1';
UPDATE dbo.STUDENT SET ClearanceLevel=4 WHERE StudentID=3;

EXEC dbo.sp_ViewStudent_Profile
    'TA',3,2,3;
GO

-- Test 2 : High clearance read allowed
PRINT 'MLS Test 2';
EXEC dbo.sp_ViewStudent_Profile
    'Admin',1,5,3;
GO

UPDATE dbo.STUDENT SET ClearanceLevel=2 WHERE StudentID=3;
GO


/* ===============================
   5) ENCRYPTION
   =============================== */

-- Test 1 : Data stored encrypted
PRINT 'Encryption Test 1';
SELECT StudentID, StudentIDEncrypted, PhoneEncrypted
FROM dbo.STUDENT;
GO

-- Test 2 : Decryption with key
PRINT 'Encryption Test 2';
OPEN SYMMETRIC KEY SRMS_SymKey
DECRYPTION BY CERTIFICATE SRMS_Cert;

SELECT StudentID, FullName,
       CONVERT(NVARCHAR(50), DecryptByKey(PhoneEncrypted)) AS Phone
FROM dbo.STUDENT;

CLOSE SYMMETRIC KEY SRMS_SymKey;
GO


PRINT '==============================';
PRINT 'SECURITY TESTS COMPLETED';
PRINT '==============================';
GO