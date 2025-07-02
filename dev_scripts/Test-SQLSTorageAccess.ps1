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

#region Helper Functions

function Write-Status {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$Type = "Info", # Can be "Info", "Success", "Warning", "Error"
        [Parameter(Mandatory = $false)]
        [switch]$NoNewline
    )
    $color = switch ($Type) {
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        Default { "White" }
    }
    $prefix = switch ($Type) {
        "Success" { "✅" }
        "Warning" { "⚠️" }
        "Error" { "🔥" }
        Default { "➡️" }
    }
    Write-Host "$prefix  $Message" -ForegroundColor $color -NoNewline:$NoNewline
}

function Ensure-Module {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )
    try {
        if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
            Write-Status -Message "'$ModuleName' module not found. Attempting to install..." -Type "Warning"
            Install-Module -Name $ModuleName -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
        }
        Import-Module $ModuleName -ErrorAction Stop
        Write-Status -Message "'$ModuleName' module is ready." -Type "Success"
        return $true
    }
    catch {
        Write-Status -Message "Critical Error: Failed to load required PowerShell module '$ModuleName'. $($_.Exception.Message)" -Type "Error"
        return $false
    }
}

function Invoke-SqlcmdSafe {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$SqlParams,
        [Parameter(Mandatory = $true)]
        [string]$Query,
        [Parameter(Mandatory = $false)]
        [string]$OperationName = "SQL operation",
        [Parameter(Mandatory = $false)]
        [string]$ConnectionTimeoutMessage = "A connection timeout occurred. This is common with Azure SQL Database. ACTION REQUIRED: In the Azure Portal, go to the Firewall settings for your SQL Server ('$($SqlParams.ServerInstance)') and ensure 'Allow Azure services and resources to access this server' is ENABLED."
    )
    try {
        Write-Status -Message "$OperationName : " -NoNewline
        $result = Invoke-Sqlcmd @SqlParams -Query $Query -ErrorAction Stop
        Write-Status -Message " Success!" -Type "Success"
        return $result
    }
    catch {
        if ($_.Exception.GetBaseException().Message -like "*Connection Timeout Expired*") {
            Write-Status -Message "`n$ConnectionTimeoutMessage" -Type "Warning"
        }
        Write-Status -Message "`nError during $OperationName : $($_.Exception.GetBaseException().Message)" -Type "Error"
        throw $_ # Re-throw to be caught by the main handler
    }
}

#endregion

#region Module Checks
if (-not (Ensure-Module -ModuleName SqlServer)) { exit 1 }
if (-not (Ensure-Module -ModuleName Az.Storage)) { exit 1 }
Write-Status -Message "Required PowerShell modules are ready." -Type "Success"
#endregion

#region Validate Parameters and Create Storage Context
$credentialIdentity = ""
$credentialSecret = ""
$pre = ""
$storageContext = $null

switch ($AuthMethod) {
    'SASToken' {
        if ([string]::IsNullOrEmpty($SASToken)) {
            throw "AuthMethod is 'SASToken' but no SAS Token was provided or found in the 'sastoken' file."
        }
        $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -SasToken $SASToken
        $credentialIdentity = 'SHARED ACCESS SIGNATURE'
        $credentialSecret = $SASToken
        $pre = "SAS"
    }
    'StorageKey' {
        if ([string]::IsNullOrEmpty($StorageAccessKey)) {
            throw "AuthMethod is 'StorageKey' but no Storage Access Key was provided or found in the 'storageaccesskey' file."
        }
        $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccessKey
        $credentialIdentity = 'Storage Account Key'
        $credentialSecret = $StorageAccessKey
        $pre = "KEY"
    }
    Default {
        throw "Invalid AuthMethod specified: $AuthMethod"
    }
}
#endregion

# Temporary object names
$credentialName = "https://$StorageAccountName.blob.core.windows.net/$StorageContainerName"
$serverRootName = ($SqlServer.Split('.'))[0]
$proofFileName = "$pre-sql-read-proof_$($serverRootName)_$(Get-Date -Format 'yyyyMMddHHmmss').txt"
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
Write-Host "🎯 SQL Server          : $($SqlServer)"
Write-Host "💾 Database            : $($Database)"
Write-Host "👤 User                : $($Username)"
Write-Host "📦 Storage Account     : $($StorageAccountName)"
Write-Host "📥 Container           : $($StorageContainerName)"
Write-Host "🔐 Auth Method         : $($AuthMethod)"
Write-Host "🗑️ Remove Proof File   : $($RemoveProofFile.IsPresent)"
Write-Host "------------------------------------------------------------"
Write-Host "EXECUTION"
Write-Host "------------------------------------------------------------"

$credentialCreated = $false
$proofFileUploaded = $false

try {
    # 1. Query SQL for the proof payload
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
    $proofData = Invoke-SqlcmdSafe -SqlParams $sqlParams -Query $proofQuery -OperationName "Querying SQL Server for proof data"
    $proofPayload = ($proofData.Info | Out-String).Trim()
    $proofPayload | Out-File -FilePath $localProofFilePath -Force

    # 2. Upload the proof file to the storage container
    try {
        Write-Status -Message ("Uploading proof file '$proofFileName'" + ": ") -NoNewline
        Set-AzStorageBlobContent -Context $storageContext -Container $StorageContainerName -File $localProofFilePath -Blob $proofFileName -Force | Out-Null
        $proofFileUploaded = $true
        Write-Status -Message " Success!" -Type "Success"
    }
    catch {
        $baseException = $_.Exception.GetBaseException()
        if ($baseException.Message -like "*Server failed to authenticate the request*") {
            Write-Status -Message "`nFailed to upload proof file. This indicates an authentication issue with your Azure Storage Account. Please verify the Storage Account Name, Container Name, and ensure the provided SAS Token or Access Key is correct and has the necessary permissions (e.g., 'Write' for SAS Token, or a valid Storage Access Key)." -Type "Error"
        }
        else {
            Write-Status -Message "`nFailed to upload proof file: $($baseException.Message)" -Type "Error"
        }
        throw $_ # Re-throw to be caught by the main handler
    }

    # 3. Ensure Database Master Key exists
    $checkMasterKeySql = "SELECT COUNT(*) FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##';"
    $masterKeyExists = Invoke-SqlcmdSafe -SqlParams $sqlParams -Query $checkMasterKeySql -OperationName "Checking for database master key"
    if ($masterKeyExists.Column1 -eq 0) {
        Write-Status -Message " 🔑 Not found. Creating one..."
        $createMasterKeySql = "CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$(New-Guid)';"
        Invoke-SqlcmdSafe -SqlParams $sqlParams -Query $createMasterKeySql -OperationName "Creating database master key"
    }
    else {
        Write-Status -Message " ✅ Found." -Type "Success"
    }

    # 4. Create the Database Scoped Credential
    $credentialSql = "CREATE DATABASE SCOPED CREDENTIAL [$credentialName] WITH IDENTITY = '$credentialIdentity', SECRET = '$credentialSecret';"
    $fullCredentialSql = "
        IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = '$credentialName')
        BEGIN
            $credentialSql
        END"
    Invoke-SqlcmdSafe -SqlParams $sqlParams -Query $fullCredentialSql -OperationName "Creating credential for '$($credentialName.Split('?')[0])'" -ConnectionTimeoutMessage "A connection timeout occurred. This is common with Azure SQL Database. ACTION REQUIRED: In the Azure Portal, go to the Firewall settings for your SQL Server ('$($SqlParams.ServerInstance)') and ensure 'Allow Azure services and resources to access this server' is ENABLED."
    $credentialCreated = $true

    # 5. Actively test the connection by reading the uploaded file from SQL
    # Only attempt to read from SQL if the file was successfully uploaded
    if ($proofFileUploaded) {
        $fullBlobPath = "https://$StorageAccountName.blob.core.windows.net/$StorageContainerName/$proofFileName"
        $testQuery = "SELECT BulkColumn FROM OPENROWSET(BULK '$fullBlobPath', SINGLE_CLOB) as t;"
        try {
            $fileContentFromSql = Invoke-SqlcmdSafe -SqlParams $sqlParams -Query $testQuery -OperationName "Attempting to read proof file FROM SQL"
            Write-Host ""
            Write-Host "------------------- Proof File Content (Read by SQL) --------------------" -ForegroundColor Cyan
            Write-Host $fileContentFromSql.BulkColumn -ForegroundColor Cyan
            Write-Host "-----------------------------------------------------------------------" -ForegroundColor Cyan
            Write-Host ""
        }
        catch {
            $baseException = $_.Exception.GetBaseException()
            if ($baseException.Message -like "*Cannot find the CREDENTIAL*" -or $baseException.Message -like "*Access denied*") {
                Write-Status -Message "`nFailed to read proof file from SQL. This usually means SQL Server cannot access the storage account, even if the credential was created. Please ensure the SQL Server's managed identity or IP address is allowed access to the storage account, and the credential's secret is correct." -Type "Error"
            }
            else {
                Write-Status -Message "`nFailed to read proof file from SQL: $($baseException.Message)" -Type "Error"
            }
            throw $_ # Re-throw to be caught by the main handler
        }
    }
    else {
        Write-Status -Message "Skipping SQL read-back test because the proof file upload failed." -Type "Warning"
    }

    Write-Host "🎉" -ForegroundColor Green
    Write-Host "--------------------------------------------------------------------" -ForegroundColor Green
    Write-Host "✅ DEFINITIVE SUCCESS: SQL Server can authenticate and read from the storage container." -ForegroundColor Green
    Write-Host "--------------------------------------------------------------------" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Status -Message "FAILED! Error: $($_.Exception.GetBaseException().Message)" -Type "Error"
    exit 1
}
finally {
    # 6. Cleanup
    Write-Host "`n🧹 Starting cleanup..."
    if ($credentialCreated) {
        Write-Status -Message "Dropping credential..." -NoNewline
        try {
            $dropCredentialSql = "DROP DATABASE SCOPED CREDENTIAL [$credentialName];"
            Invoke-Sqlcmd @sqlParams -Query $dropCredentialSql -QueryTimeout 60 -ErrorAction Stop
            Write-Status -Message " Dropped!" -Type "Success"
        }
        catch {
            Write-Status -Message "FAILED to drop credential!" -Type "Error"
        }
    }
    if ($proofFileUploaded) {
        if ($RemoveProofFile) {
            Write-Status -Message "Deleting proof file '$proofFileName' as requested..." -NoNewline
            try {
                Remove-AzStorageBlob -Context $storageContext -Container $StorageContainerName -Blob $proofFileName -Force | Out-Null
                Write-Status -Message " Deleted!" -Type "Success"
            }
            catch {
                Write-Status -Message "FAILED to delete proof file!" -Type "Warning"
            }
        }
        else {
            Write-Status -Message "Proof file '$proofFileName' was left in the container." -Type "Info"
        }
    }
    if (Test-Path -Path $localProofFilePath) {
        Remove-Item -Path $localProofFilePath -Force
    }
    Write-Host "✨ Cleanup complete."
}

Write-Host "🏁 Test finished."
