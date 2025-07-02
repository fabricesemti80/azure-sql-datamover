<#
.SYNOPSIS
    Definitively tests if a SQL Server can access an Azure Storage Account using either a SAS Token or an Access Key.

.DESCRIPTION
    This script provides definitive, closed-loop proof of SQL Server's ability to access an Azure
    Storage container. It uses an -AuthMethod parameter to switch between SAS Token and Storage Access Key authentication.

    The script performs the following steps:
    1.  Connects to the specified SQL Server from PowerShell and queries for server version, timestamp, and a list of databases.
        It includes special error handling to detect common Azure SQL firewall issues.
    2.  Uploads this rich proof data to a new, unique file in the specified blob container.
    3.  Connects to SQL Server again and creates a temporary credential based on the chosen authentication method.
    4.  Executes a SELECT query from within SQL using OPENROWSET to read the content of the proof file.
    5.  Displays the content read by SQL in the console, providing undeniable proof of access.
    6.  Optionally deletes the proof file if the -RemoveProofFile switch is used.
    7.  Cleans up the temporary SQL credential.

.PARAMETER SqlServer
    The name of the SQL Server instance to connect to.

.PARAMETER Database
    The name of the database to run the connectivity test in.

.PARAMETER Username
    The username for SQL Server authentication.

.PARAMETER Password
    The password for SQL Server authentication. Defaults to loading from 'sqlpassword'.

.PARAMETER StorageAccountName
    The name of the Azure Storage Account.

.PARAMETER StorageContainerName
    The name of the blob container.

.PARAMETER AuthMethod
    The authentication method to use. Valid values are 'SASToken' or 'StorageKey'.

.PARAMETER SASToken
    The Shared Access Signature (SAS) token. If not provided, defaults to loading from a 'sastoken' file.

.PARAMETER StorageAccessKey
    The storage account access key. If not provided, defaults to loading from a 'storageaccesskey' file.

.PARAMETER RemoveProofFile
    A switch parameter. If present, the script will delete the proof file from blob storage after the test.

.EXAMPLE
    # Test using a SAS Token loaded from the default 'sastoken' file
    PS C:\> .\Test-SQLSTorageAccess.ps1 -Database 'MyUserDB' -StorageAccountName 'mystorage' -StorageContainerName 'mycontainer' -AuthMethod SASToken
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SqlServer = "sqlmi-mi-etl01-emp-dev-ne.1b4f626d1cbb.database.windows.net",

    [Parameter(Mandatory = $true)]
    [string]$Database,

    [Parameter(Mandatory = $false)]
    [string]$Username = "sqladmin",

    [Parameter(Mandatory = $false)]
    [string]$Password = (Get-Content -Path "$PSScriptRoot\sqlpassword" -ErrorAction SilentlyContinue),

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$StorageContainerName,

    [Parameter(Mandatory = $true)]
    [ValidateSet('SASToken', 'StorageKey')]
    [string]$AuthMethod,

    [Parameter(Mandatory = $false)]
    [string]$SASToken = (Get-Content -Path "$PSScriptRoot\sastoken" -ErrorAction SilentlyContinue),

    [Parameter(Mandatory = $false)]
    [string]$StorageAccessKey = (Get-Content -Path "$PSScriptRoot\storageaccesskey" -ErrorAction SilentlyContinue),

    [Parameter(Mandatory = $false)]
    [switch]$RemoveProofFile
)

#region Module Checks
try {
    if (-not (Get-Module -ListAvailable -Name SqlServer)) {
        Write-Host "🔧 'SqlServer' module not found. Attempting to install..." -ForegroundColor Yellow
        Install-Module -Name SqlServer -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
    }
    if (-not (Get-Module -ListAvailable -Name Az.Storage)) {
        Write-Host "🔧 'Az.Storage' module not found. Attempting to install..." -ForegroundColor Yellow
        Install-Module -Name Az.Storage -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
    }
    Import-Module SqlServer -ErrorAction Stop
    Import-Module Az.Storage -ErrorAction Stop
    Write-Host "✅ Required PowerShell modules are ready." -ForegroundColor Green
}
catch {
    Write-Host "🔥 Critical Error: Failed to load required PowerShell modules." -ForegroundColor Red
    exit 1
}
#endregion

#region Validate Parameters and Create Storage Context
if ($AuthMethod -eq 'SASToken') {
    if ([string]::IsNullOrEmpty($SASToken)) {
        throw "AuthMethod is 'SASToken' but no SAS Token was provided or found in the 'sastoken' file."
    }
    $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -SasToken $SASToken
    $credentialIdentity = 'SHARED ACCESS SIGNATURE'
    $credentialSecret = $SASToken
}
else { # StorageKey
    if ([string]::IsNullOrEmpty($StorageAccessKey)) {
        throw "AuthMethod is 'StorageKey' but no Storage Access Key was provided or found in the 'storageaccesskey' file."
    }
    $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccessKey
    $credentialIdentity = 'Storage Account Key'
    $credentialSecret = $StorageAccessKey
}
#endregion

# Temporary object names
$credentialName = "https://$StorageAccountName.blob.core.windows.net/$StorageContainerName"
$serverRootName = ($SqlServer.Split('.'))[0]
$proofFileName = "sql-read-proof_$($serverRootName)_$(Get-Date -Format 'yyyyMMddHHmmss').txt"
$localProofFilePath = Join-Path -Path $env:TEMP -ChildPath $proofFileName

# SQL Connection parameters
$sqlParams = @{
    ServerInstance    = $SqlServer
    Username          = $Username
    Password          = $Password
    Database          = $Database
    ConnectionTimeout = 30
}

# Main Header
Write-Host "`n🧪 Starting Definitive SQL Read-Back Test..."
Write-Host "------------------------------------------------------------"
Write-Host "CONFIGURATION"
Write-Host "------------------------------------------------------------"
Write-Host "🎯 SQL Server          : $SqlServer"
Write-Host "💾 Database            : $Database"
Write-Host "👤 User                : $Username"
Write-Host "📦 Storage Account     : $StorageAccountName"
Write-Host "📥 Container           : $StorageContainerName"
Write-Host "🔐 Auth Method         : $AuthMethod"
Write-Host "🗑️ Remove Proof File   : $($RemoveProofFile.IsPresent)"
Write-Host "------------------------------------------------------------"
Write-Host "EXECUTION"
Write-Host "------------------------------------------------------------"

$credentialCreated = $false
$proofFileUploaded = $false

try {
    # 1. Query SQL for the proof payload
    Write-Host "➡️  Querying SQL Server for proof data..." -NoNewline
    $proofQuery = @"
SELECT 1 AS SortKey, '--- SQL Server Proof of Access ---' AS Info
UNION ALL
SELECT 2, 'Timestamp (UTC): ' + CONVERT(varchar, GETUTCDATE(), 120)
UNION ALL
SELECT 3, 'SQL Version: ' + REPLACE(REPLACE(@@VERSION, CHAR(10), ' '), CHAR(13), '')
UNION ALL
SELECT 4, '--- Database List ---'
UNION ALL
SELECT 5, name FROM sys.databases
ORDER BY SortKey, Info;
"@
    try {
        $proofData = Invoke-Sqlcmd @sqlParams -Query $proofQuery
    }
    catch {
        if ($_.Exception.GetBaseException().Message -like "*Connection Timeout Expired*") {
            Write-Host "`n🔥 A connection timeout occurred. This is common with Azure SQL Database." -ForegroundColor Yellow
            Write-Host "   ACTION REQUIRED: In the Azure Portal, go to the Firewall settings for your" -ForegroundColor Yellow
            Write-Host "   SQL Server ('$SqlServer') and ensure 'Allow Azure services and resources to access this server' is ENABLED." -ForegroundColor Yellow
        }
        # Re-throw the original exception to be caught by the main handler
        throw
    }
    $proofPayload = ($proofData.Info | Out-String).Trim()
    $proofPayload | Out-File -FilePath $localProofFilePath -Force
    Write-Host " ✅ Success!"

    # 2. Upload the proof file to the storage container
    Write-Host "➡️  Uploading proof file '$proofFileName'..." -NoNewline
    Set-AzStorageBlobContent -Context $storageContext -Container $StorageContainerName -File $localProofFilePath -Blob $proofFileName -Force | Out-Null
    $proofFileUploaded = $true
    Write-Host " ✅ Success!"

    # 3. Ensure Database Master Key exists
    Write-Host "➡️  Checking for database master key..." -NoNewline
    $checkMasterKeySql = "SELECT COUNT(*) FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##';"
    $masterKeyExists = Invoke-Sqlcmd @sqlParams -Query $checkMasterKeySql
    if ($masterKeyExists.Column1 -eq 0) {
        Write-Host " 🔑 Not found. Creating one..."
        $createMasterKeySql = "CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$(New-Guid)';"
        Invoke-Sqlcmd @sqlParams -Query $createMasterKeySql -ErrorAction Stop
        Write-Host " ✅ Success!"
    } else {
        Write-Host " ✅ Found."
    }

    # 4. Create the Database Scoped Credential
    Write-Host "➡️  Creating credential for '$($credentialName.Split('?')[0])'..." -NoNewline
    $credentialSql = "CREATE DATABASE SCOPED CREDENTIAL [$credentialName] WITH IDENTITY = '$credentialIdentity', SECRET = '$credentialSecret';"
    $fullCredentialSql = "
        IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = '$credentialName')
        BEGIN
            $credentialSql
        END"
    Invoke-Sqlcmd @sqlParams -Query $fullCredentialSql -QueryTimeout 60 -ErrorAction Stop
    $credentialCreated = $true
    Write-Host " ✅ Success!"

    # 5. Actively test the connection by reading the uploaded file from SQL
    Write-Host "➡️  Attempting to read proof file FROM SQL..." -NoNewline
    $fullBlobPath = "https://$StorageAccountName.blob.core.windows.net/$StorageContainerName/$proofFileName"
    $testQuery = "SELECT BulkColumn FROM OPENROWSET(BULK '$fullBlobPath', SINGLE_CLOB) as t;"
    $fileContentFromSql = Invoke-Sqlcmd @sqlParams -Query $testQuery -ErrorAction Stop
    Write-Host " ✅ Read successful!"
    Write-Host ""
    Write-Host "------------------- Proof File Content (Read by SQL) --------------------" -ForegroundColor Cyan
    Write-Host $fileContentFromSql.BulkColumn -ForegroundColor Cyan
    Write-Host "-----------------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "🎉" -ForegroundColor Green
    Write-Host "--------------------------------------------------------------------" -ForegroundColor Green
    Write-Host "✅ DEFINITIVE SUCCESS: SQL Server can authenticate and read from the storage container." -ForegroundColor Green
    Write-Host "--------------------------------------------------------------------" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host "`n ❌ FAILED!" -ForegroundColor Red
    Write-Host "🔥 Error: $($_.Exception.GetBaseException().Message)" -ForegroundColor Red
    exit 1
}
finally {
    # 6. Cleanup
    Write-Host "`n🧹 Starting cleanup..."
    if ($credentialCreated) {
        Write-Host "➡️  Dropping credential..." -NoNewline
        try {
            $dropCredentialSql = "DROP DATABASE SCOPED CREDENTIAL [$credentialName];"
            Invoke-Sqlcmd @sqlParams -Query $dropCredentialSql -QueryTimeout 60 -ErrorAction Stop
            Write-Host " ✅ Dropped!"
        }
        catch {
            Write-Host " ❌ FAILED to drop credential!" -ForegroundColor Red
        }
    }
    if ($proofFileUploaded) {
        if ($RemoveProofFile) {
            Write-Host "➡️  Deleting proof file '$proofFileName' as requested..." -NoNewline
            try {
                Remove-AzStorageBlob -Context $storageContext -Container $StorageContainerName -Blob $proofFileName -Force | Out-Null
                Write-Host " ✅ Deleted!"
            }
            catch {
                Write-Host " ❌ FAILED to delete proof file!" -ForegroundColor Yellow
            }
        } else {
            Write-Host "➡️  Proof file '$proofFileName' was left in the container." -ForegroundColor Cyan
        }
    }
    if (Test-Path -Path $localProofFilePath) {
        Remove-Item -Path $localProofFilePath -Force
    }
    Write-Host "✨ Cleanup complete."
}

Write-Host "🏁 Test finished."
