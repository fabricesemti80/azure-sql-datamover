-- ✅ STEP 0: Define parameters
DECLARE @TargetDatabase NVARCHAR(128) = 'WideWorld';  -- 🔁 Replace with your actual target DB name
DECLARE @CredentialName NVARCHAR(512) = 'https://<storage-account>.blob.core.windows.net/<container-name>';
DECLARE @SasToken NVARCHAR(MAX) = '<your-sas-token>';
DECLARE @BackupFileUrl NVARCHAR(MAX) = 'https://<storage-account>.blob.core.windows.net/<container-name>/<backup-file-name>.bak';

-- ✅ STEP 1: Clean up credential name
SET @CredentialName = RTRIM(LTRIM(@CredentialName));

-- ✅ STEP 2: Switch to master database to manage credentials
USE [master];

-- ✅ STEP 3: Drop credential if it exists (in master database)
BEGIN TRY
    IF EXISTS (
        SELECT 1 
        FROM sys.credentials 
        WHERE name = @CredentialName -- exact match, no trimming
    )
    BEGIN
        PRINT 'Dropping credential...';
        DECLARE @DropSql NVARCHAR(MAX) = 'DROP CREDENTIAL [' + @CredentialName + ']';
        EXEC(@DropSql);
    END
    ELSE
    BEGIN
        PRINT 'Credential not found to drop.';
    END
END TRY
BEGIN CATCH
    PRINT 'Error dropping credential: ' + ERROR_MESSAGE();
END CATCH

-- ✅ STEP 4: Create new credential with SAS token (in master database)
DECLARE @EscapedSasToken NVARCHAR(MAX) = REPLACE(@SasToken, '''', '''''');
DECLARE @CreateSql NVARCHAR(MAX) = '
CREATE CREDENTIAL ' + QUOTENAME(@CredentialName) + '
WITH IDENTITY = ''SHARED ACCESS SIGNATURE'',
SECRET = ''' + @EscapedSasToken + ''';';
EXEC(@CreateSql);

-- ✅ STEP 5: Switch to target database
DECLARE @UseSql NVARCHAR(MAX) = 'USE [' + @TargetDatabase + '];';
EXEC(@UseSql);

-- ✅ STEP 6: Test credential via RESTORE HEADERONLY
RESTORE HEADERONLY 
FROM URL = @BackupFileUrl;