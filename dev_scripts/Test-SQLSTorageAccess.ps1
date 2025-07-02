<#
.SYNOPSIS
    Definitively tests if a SQL Server can read from an Azure Storage Account.

.DESCRIPTION
    This script provides definitive, closed-loop proof of SQL Server's ability to access an Azure
    Storage container with a given SAS token. It performs the following steps:

    1.  Connects to the specified SQL Server from PowerShell and queries for a list of databases.
    2.  Uploads this database list to a new, unique file in the specified blob container.
    3.  Connects to SQL Server again and creates a temporary credential.
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
    The password for SQL Server authentication.

.PARAMETER StorageAccountName
    The name of the Azure Storage Account.

.PARAMETER StorageContainerName
    The name of the blob container.

.PARAMETER SASToken
    The Shared Access Signature (SAS) token. Must have Read, Write, and Delete permissions.

.PARAMETER RemoveProofFile
    A switch parameter. If present, the script will delete the proof file from blob storage after the test.

.EXAMPLE
    PS C:\> .\Test-SQLSTorageAccess.ps1 -Database 'MyUserDB' -StorageAccountName 'mystorage' -StorageContainerName 'mycontainer' -SASToken '?sv=...' -RemoveProofFile
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "SQL Server instance name.")]
    [string]$SqlServer = "sqlmi-mi-etl01-emp-dev-ne.1b4f626d1cbb.database.windows.net",

    [Parameter(Mandatory = $true, HelpMessage = "The database to run the test in. Cannot be 'master'.")]
    [string]$Database,

    [Parameter(Mandatory = $false, HelpMessage = "SQL Server username.")]
    [string]$Username = "sqladmin",

    [Parameter(Mandatory = $false, HelpMessage = "SQL Server password.")]
    [string]$Password = (Get-Content -Path $PSScriptRoot\sqlpassword),

    [Parameter(Mandatory = $true, HelpMessage = "Azure Storage Account name.")]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $true, HelpMessage = "Azure Blob Container name.")]
    [string]$StorageContainerName,

    [Parameter(Mandatory = $true, HelpMessage = "Storage Account SAS Token with Read, Write, Delete permissions.")]
    [string]$SASToken,

    [Parameter(Mandatory = $false, HelpMessage = "If specified, the proof file will be deleted after the test.")]
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

# Temporary object names
$credentialName = "https://$StorageAccountName.blob.core.windows.net/$StorageContainerName"
$proofFileName = "sql-read-proof-$(Get-Date -Format 'yyyyMMddHHmmss').txt"
$localProofFilePath = Join-Path -Path $env:TEMP -ChildPath $proofFileName

# PowerShell Storage Context
$storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -SasToken $SASToken

# SQL Connection parameters
$sqlParams = @{
    ServerInstance    = $SqlServer
    Username          = $Username
    Password          = $Password
    Database          = $Database
    ConnectionTimeout = 30
}

Write-Host "🧪 Starting Definitive SQL Read-Back Test..."
Write-Host "----------------------------------------"
Write-Host "🎯 SQL Server          : $SqlServer"
Write-Host "💾 Database            : $Database"
Write-Host "👤 User                : $Username"
Write-Host "📦 Storage Account     : $StorageAccountName"
Write-Host "📥 Container           : $StorageContainerName"
Write-Host "----------------------------------------"

$credentialCreated = $false
$proofFileUploaded = $false

try {
    # 1. Query SQL for the database list to use as a payload
    Write-Host "➡️  Querying SQL Server for database list..." -NoNewline
    $dbListQuery = "SELECT name FROM sys.databases;"
    $dbList = Invoke-Sqlcmd @sqlParams -Query $dbListQuery
    $proofPayload = ($dbList.name | Out-String).Trim()
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
    $credentialSql = "
        IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = '$credentialName')
        BEGIN
            CREATE DATABASE SCOPED CREDENTIAL [$credentialName] WITH IDENTITY = 'SHARED ACCESS SIGNATURE', SECRET = '$SASToken';
        END"
    Invoke-Sqlcmd @sqlParams -Query $credentialSql -QueryTimeout 60 -ErrorAction Stop
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
    Write-Host " ❌ FAILED!" -ForegroundColor Red
    Write-Host "🔥 Error: $($_.Exception.GetBaseException().Message)" -ForegroundColor Red
    exit 1
}
finally {
    # 6. Cleanup
    Write-Host "🧹 Starting cleanup..."
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
