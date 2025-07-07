$Global:DeploymentHandlers = @{
    'AzurePaaS' = @{
        'SupportedExtensions' = @('.bacpac')
        'ImportFunction'      = ${function:Import-BacpacToSqlDatabase}
        'RequiresStorage'     = $true
    }
    'AzureMI'   = @{
        'SupportedExtensions' = @('.bacpac', '.bak')
        'ImportFunction'      = ${function:Import-BacpacToSqlManagedInstance}  # Changed this line
        'RequiresStorage'     = $true
    }
    'AzureIaaS' = @{
        'SupportedExtensions' = @('.bacpac', '.bak')
        'ImportFunction'      = ${function:Import-BakToSqlDatabase}
        'RequiresStorage'     = $false
    }
}

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #
#                                                                                           Helper functions                                                                                           #
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #

function Write-StatusMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Action', 'Header')]
        [string]$Type = 'Info',
        
        [Parameter(Mandatory = $false)]
        [int]$Indent = 0
    )
    
    $colors = @{
        'Info'    = 'Cyan'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
        'Action'  = 'White'
        'Header'  = 'Magenta'
    }
    
    $emojis = @{
        'Info'    = "ℹ️ "
        'Success' = "✅ "
        'Warning' = "⚠️ "
        'Error'   = "❌ "
        'Action'  = "🔄 "
        'Header'  = "📋 "
    }
    
    $indentation = if ($Indent -gt 0) { "  " * $Indent } else { "" }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = $emojis[$Type]
    
    Write-Host "$timestamp $indentation$prefix $Message" -ForegroundColor $colors[$Type]
}

function Initialize-Logging {
    [CmdletBinding()]
    param(
        [string]$LogsFolder
    )
    
    try {
        # Create logs folder if it doesn't exist
        if (-not (Test-Path $LogsFolder)) {
            New-Item -Path $LogsFolder -ItemType Directory -Force | Out-Null
            Write-StatusMessage "Created logs folder: $LogsFolder" -Type Info
        }
        
        # Create session log file
        $sessionLogFile = Join-Path -Path $LogsFolder -ChildPath "session_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        
        # Write session start
        $sessionStart = @"
================================================================================
SQL MOVE SESSION START
================================================================================
Session Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
PowerShell Version: $($PSVersionTable.PSVersion)
User: $($env:USERNAME)
Computer: $($env:COMPUTERNAME)
================================================================================

"@
        
        Add-Content -Path $sessionLogFile -Value $sessionStart -Encoding UTF8
        Write-StatusMessage "Session log initialized: $sessionLogFile" -Type Success
        
        return $sessionLogFile
    }
    catch {
        Write-StatusMessage "Error initializing logging: $($_.Exception.Message)" -Type Error
        return $null
    }
}

function Initialize-OperationLogging {
    [CmdletBinding()]
    param(
        [string]$OperationId,
        [string]$DatabaseName,
        [datetime]$StartTime,
        [string]$LogsFolder
    )
    
    try {
        # Create operation-specific log file name
        $timestamp = $StartTime.ToString('yyyyMMdd_HHmmss')
        $sanitizedDbName = $DatabaseName -replace '[^\w\-_]', '_'
        $logFileName = "${OperationId}_${sanitizedDbName}_${timestamp}.log"
        $logFile = Join-Path -Path $LogsFolder -ChildPath $logFileName
        
        # Create the log file with header
        $logHeader = @"
================================================================================
SQL MOVE OPERATION LOG
================================================================================
Operation ID: $OperationId
Database Name: $DatabaseName
Start Time: $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))
Log File: $logFileName
================================================================================

"@
        
        Add-Content -Path $logFile -Value $logHeader -Encoding UTF8
        
        return $logFile
    }
    catch {
        Write-StatusMessage "Error initializing operation logging: $($_.Exception.Message)" -Type Error
        return $null
    }
}

function Write-LogMessage {
    [CmdletBinding()]
    param(
        [string]$LogFile,
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Action', 'Header')]
        [string]$Type = 'Info'
    )
    
    if (-not $LogFile -or -not (Test-Path (Split-Path -Path $LogFile -Parent))) {
        return
    }
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "$timestamp [$Type] $Message"
        
        Add-Content -Path $LogFile -Value $logEntry -Encoding UTF8
    }
    catch {
        # Silently fail if logging fails to avoid disrupting main operations
    }
}

function Get-ServerFQDN {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $false)]
        [string]$DeploymentType = "AzurePaaS" # Default to AzurePaaS for backward compatibility
    )
    
    # For AzureIaaS, return the server name as-is
    if ($DeploymentType -eq "AzureIaaS") {
        return $ServerName
    }

    # If already ends with .database.windows.net, return as-is
    if ($ServerName.EndsWith(".database.windows.net", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $ServerName
    }
    
    # Otherwise, append .database.windows.net
    # This works for both:
    # - Regular Azure SQL: "myserver" -> "myserver.database.windows.net"
    # - Managed Instance: "sqlmi-name.guid" -> "sqlmi-name.guid.database.windows.net"
    return "$ServerName.database.windows.net"
}

function Test-Prerequisites {
    [CmdletBinding()]
    param(
        [string]$SqlPackagePath,
        [string]$CsvPath
    )

    $success = $true

    # Check Azure PowerShell modules
    $requiredModules = @('Az.Storage')
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-StatusMessage "The $module PowerShell module is not installed. Please install it using: Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force" -Type Error
            $success = $false
        }
        else {
            Write-StatusMessage "$module module is available" -Type Success
        }
    }

    # Check sqlpackage.exe
    try {
        $null = Get-Command $SqlPackagePath -ErrorAction Stop
        Write-StatusMessage "SqlPackage.exe found at: $SqlPackagePath" -Type Success
    }
    catch {
        Write-StatusMessage "sqlpackage.exe not found at path: $SqlPackagePath. Please ensure SQL Server Data Tools (SSDT) is installed or specify the correct path." -Type Error
        $success = $false
    }

    # Check CSV file
    if (-not (Test-Path $CsvPath)) {
        Write-StatusMessage "CSV file not found at path: $CsvPath" -Type Error
        $success = $false
    }
    else {
        Write-StatusMessage "CSV file found at: $CsvPath" -Type Success
    }

    return $success
}

function Test-RequiredFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Row,
        
        [Parameter(Mandatory = $true)]
        [bool]$ExportAction,
        
        [Parameter(Mandatory = $true)]
        [bool]$ImportAction,
        
        [Parameter(Mandatory = $false)]
        [string]$LogFile
    )

    $missingFields = @()
    
    # Common required fields
    $commonFields = @('Operation_ID', 'Database_Name', 'Storage_Account', 'Storage_Container', 'Storage_Access_Key')
    
    foreach ($field in $commonFields) {
        if ([string]::IsNullOrEmpty($Row.$field)) {
            $missingFields += $field
        }
    }
    
    # Export-specific required fields
    if ($ExportAction) {
        $exportFields = @('SRC_server', 'SRC_SQL_Admin', 'SRC_SQL_Password')
        if ($Row.Type -eq 'AzureIaaS') {
            $exportFields += @('PS_User', 'PS_Password')
        }

        foreach ($field in $exportFields) {
            if ([string]::IsNullOrEmpty($Row.$field)) {
                $missingFields += $field
            }
        }
    }
    
    # Import-specific required fields
    if ($ImportAction) {
        $importFields = @('DST_server', 'DST_SQL_Admin', 'DST_SQL_Password')
        if ($Row.Type -eq 'AzureIaaS') {
            $importFields += @('PS_User', 'PS_Password')
        }

        foreach ($field in $importFields) {
            if ([string]::IsNullOrEmpty($Row.$field)) {
                $missingFields += $field
            }
        }
    }
    
    if ($missingFields.Count -gt 0) {
        $message = "Missing required fields: $($missingFields -join ', ')"
        Write-StatusMessage $message -Type Error
        Write-LogMessage -LogFile $LogFile -Message $message -Type Error
        return $false
    }
    
    Write-LogMessage -LogFile $LogFile -Message "Required field validation passed" -Type Success
    return $true
}

function Test-DiskSpace {
    [CmdletBinding()]
    param(
        [string]$Path,
        [long]$RequiredSpaceGB,
        [string]$LogFile
    )
    
    try {
        # Ensure directory exists
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            $message = "Created directory: $Path"
            Write-StatusMessage $message -Type Info -Indent 2
            Write-LogMessage -LogFile $LogFile -Message $message -Type Info
        }
        
        $drive = Split-Path -Path $Path -Qualifier
        if (-not $drive) {
            $drive = (Get-Location).Drive.Name + ":"
        }
        
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$drive'"
        $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        
        $message = "Available space on $drive $freeSpaceGB GB, Required: $RequiredSpaceGB GB"
        Write-StatusMessage $message -Type Info -Indent 2
        Write-LogMessage -LogFile $LogFile -Message $message -Type Info
        
        if ($freeSpaceGB -lt $RequiredSpaceGB) {
            $errorMessage = "Insufficient disk space. Available: $freeSpaceGB GB, Required: $RequiredSpaceGB GB"
            Write-StatusMessage $errorMessage -Type Error
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            return $false
        }
        
        Write-LogMessage -LogFile $LogFile -Message "Disk space check passed" -Type Success
        return $true
    }
    catch {
        $errorMessage = "Error checking disk space: $_"
        Write-StatusMessage $errorMessage -Type Warning
        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Warning
        return $true # Continue if we can't check
    }
}

function Test-RemoteSqlServerDiskSpace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerFQDN,
        
        [Parameter(Mandatory = $true)]
        [string]$Username,
        
        [Parameter(Mandatory = $true)]
        [string]$Password,
        
        [Parameter(Mandatory = $true)]
        [long]$RequiredSpaceGB,
        
        [Parameter(Mandatory = $true)]
        [string]$LocalFolder,
        
        [Parameter(Mandatory = $false)]
        [string]$LogFile
    )
    
    # Extract drive letter from Local_Folder path
    $driveLetter = Split-Path -Path $LocalFolder -Qualifier
    if ($driveLetter) {
        $driveLetter = $driveLetter.Replace(":", "")  # Remove colon for xp_fixeddrives
    }
    else {
        $driveLetter = "C"  # Default to C drive if can't determine
    }
    
    Write-StatusMessage "Testing disk space on drive '$driveLetter' of remote server '$ServerFQDN'..." -Type Info -Indent 2
    Write-LogMessage -LogFile $LogFile -Message "Testing disk space on drive '$driveLetter' of remote server '$ServerFQDN' for path '$LocalFolder'" -Type Info
    
    try {
        $connection = New-SqlConnection -ServerFQDN $ServerFQDN -Database "master" -Username $Username -Password $Password -TrustServerCertificate $true
        $connection.Open()
        
        $command = $connection.CreateCommand()
        $command.CommandText = "EXEC xp_fixeddrives"
        $reader = $command.ExecuteReader()
        
        $targetDriveFreeSpaceMB = $null
        while ($reader.Read()) {
            $currentDrive = $reader.GetString(0)
            $freeSpaceMB = $reader.GetInt32(1)
            
            if ($currentDrive -eq $driveLetter) {
                $targetDriveFreeSpaceMB = $freeSpaceMB
                break
            }
        }
        $reader.Close()
        $connection.Close()
        
        if ($targetDriveFreeSpaceMB -eq $null) {
            $errorMessage = "Drive '$driveLetter' not found on remote server '$ServerFQDN'"
            Write-StatusMessage $errorMessage -Type Error -Indent 3
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            return $false
        }
        
        $freeSpaceGB = [math]::Round($targetDriveFreeSpaceMB / 1024, 2)
        $message = "Available space on drive '$driveLetter': $freeSpaceGB GB, Required: $RequiredSpaceGB GB"
        Write-StatusMessage $message -Type Info -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $message -Type Info
        
        if ($freeSpaceGB -lt $RequiredSpaceGB) {
            $errorMessage = "Insufficient disk space on drive '$driveLetter' of server '$ServerFQDN'. Available: $freeSpaceGB GB, Required: $RequiredSpaceGB GB"
            Write-StatusMessage $errorMessage -Type Error -Indent 3
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            return $false
        }
        
        Write-StatusMessage "Remote disk space check passed on drive '$driveLetter' of '$ServerFQDN'" -Type Success -Indent 3
        Write-LogMessage -LogFile $LogFile -Message "Remote disk space check passed on drive '$driveLetter' of '$ServerFQDN'" -Type Success
        return $true
    }
    catch {
        $errorMessage = "Error checking remote disk space on '$ServerFQDN': $($_.Exception.Message)"
        Write-StatusMessage $errorMessage -Type Error -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
        return $false
    }
}

function Copy-FileToRemote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerFQDN,
        [Parameter(Mandatory = $true)]
        [string]$LocalPath,
        [Parameter(Mandatory = $true)]
        [string]$RemotePath,
        [Parameter(Mandatory = $true)]
        [string]$Username,
        [Parameter(Mandatory = $true)]
        [string]$Password,
        [Parameter(Mandatory = $false)]
        [string]$LogFile
    )

    try {
        Write-OperationStatus "Copying file to remote server..." -Type Action -Indent 2 -LogFile $LogFile
        Write-OperationStatus "Source: $LocalPath" -Type Info -Indent 3 -LogFile $LogFile
        Write-OperationStatus "Destination: $RemotePath on $ServerFQDN" -Type Info -Indent 3 -LogFile $LogFile

        $credential = New-Object System.Management.Automation.PSCredential($Username, (ConvertTo-SecureString $Password -AsPlainText -Force))
        $psSession = New-PSSession -ComputerName $ServerFQDN -Credential $credential

        # Ensure the remote directory exists
        $remoteDir = Split-Path -Path $RemotePath -Parent
        Invoke-Command -Session $psSession -ScriptBlock {
            param($Path)
            if (-not (Test-Path $Path)) {
                New-Item -Path $Path -ItemType Directory -Force | Out-Null
            }
        } -ArgumentList $remoteDir

        Copy-Item -ToSession $psSession -Path $LocalPath -Destination $RemotePath -Force

        # Verify the copy
        $remoteFileExists = Invoke-Command -Session $psSession -ScriptBlock { param($Path) Test-Path $Path } -ArgumentList $RemotePath
        
        if ($remoteFileExists) {
            Write-OperationStatus "File copied to remote server successfully." -Type Success -Indent 2 -LogFile $LogFile
            return $true
        }
        else {
            Write-OperationStatus "File copy to remote server failed. File not found after copy." -Type Error -Indent 2 -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-OperationStatus "Error copying file to remote: $($_.Exception.Message)" -Type Error -Indent 2 -LogFile $LogFile
        return $false
    }
    finally {
        if ($psSession) {
            Remove-PSSession $psSession
        }
    }
}

function Test-StorageAccess {
    [CmdletBinding()]
    param(
        [string]$StorageAccount,
        [string]$StorageContainer,
        [string]$StorageKey,
        [string]$LogFile
    )
    
    try {
        $message = "Testing storage account access: $StorageAccount"
        Write-StatusMessage $message -Type Info -Indent 2
        Write-LogMessage -LogFile $LogFile -Message $message -Type Info
        
        $storageContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $StorageKey -ErrorAction Stop
        
        # Test container access
        $container = Get-AzStorageContainer -Name $StorageContainer -Context $storageContext -ErrorAction Stop
        
        $successMessage = "Storage container '$StorageContainer' is accessible"
        Write-StatusMessage $successMessage -Type Success -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $successMessage -Type Success
        
        return $true
    }
    catch {
        $errorMessage = "Cannot access storage account/container: $($_.Exception.Message)"
        Write-StatusMessage $errorMessage -Type Error -Indent 2
        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
        return $false
    }
}

function Get-OperationBackupPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OriginalPath,
        
        [Parameter(Mandatory = $true)]
        [string]$OperationId
    )
    
    $directory = Split-Path -Path $OriginalPath -Parent
    $originalFileName = Split-Path -Path $OriginalPath -Leaf
    $extension = [System.IO.Path]::GetExtension($originalFileName)
    $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($originalFileName)
    
    # Create new filename with Operation ID at the front
    $newFileName = "${OperationId}_$fileNameWithoutExt$extension"
    return Join-Path -Path $directory -ChildPath $newFileName
}

function New-SqlConnection {
    param(
        [string]$ServerFQDN,
        [string]$Database = "master",
        [string]$Username,
        [string]$Password,
        [int]$Timeout = 30,
        [bool]$TrustServerCertificate = $false # New parameter for trusting certificate
    )
    
    $connectionString = "Server=$ServerFQDN;Database=$Database;User Id=$Username;Password=$Password;Connection Timeout=$Timeout;Encrypt=True;TrustServerCertificate=$TrustServerCertificate;"
    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    return $connection
}

function Show-OperationProgress {
    param(
        [string]$Operation,
        [System.Diagnostics.Stopwatch]$Stopwatch,
        [string]$LogFile,
        [scriptblock]$ProgressCheck
    )
    
    $spinChars = '|', '/', '-', '\'
    $spinIndex = 0
    $lastProgressTime = [DateTime]::Now
    $progressInterval = [TimeSpan]::FromSeconds(10)
    
    while (-not $ProgressCheck.Invoke()) {
        $spinChar = $spinChars[$spinIndex]
        $spinIndex = ($spinIndex + 1) % $spinChars.Length
        $elapsedTime = $Stopwatch.Elapsed
        $elapsedFormatted = "{0:hh\:mm\:ss}" -f $elapsedTime
        
        if (([DateTime]::Now - $lastProgressTime) -ge $progressInterval) {
            Write-LogMessage -LogFile $LogFile -Message "$Operation in progress... Elapsed: $elapsedFormatted" -Type Info
            $lastProgressTime = [DateTime]::Now
        }
        
        Write-Host "`r      $spinChar $Operation... Time elapsed: $elapsedFormatted" -NoNewline
        Start-Sleep -Milliseconds 250
    }
    Write-Host "`r                                                                    " -NoNewline
}

function Write-OperationStatus {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Action', 'Header')]
        [string]$Type = 'Info',
        [int]$Indent = 0,
        [string]$LogFile
    )
    
    Write-StatusMessage -Message $Message -Type $Type -Indent $Indent
    Write-LogMessage -LogFile $LogFile -Message $Message -Type $Type
}

function Test-OperationRequirements {
    param(
        [PSCustomObject]$Row,
        [bool]$ExportAction,
        [bool]$ImportAction,
        [string]$LogFile
    )
    
    $requirements = @{
        'Common' = @('Operation_ID', 'Database_Name', 'Storage_Account', 'Storage_Container', 'Storage_Access_Key')
        'Export' = @('SRC_server', 'SRC_SQL_Admin', 'SRC_SQL_Password')
        'Import' = @('DST_server', 'DST_SQL_Admin', 'DST_SQL_Password')
    }
    
    $missingFields = @()
    
    # Check common fields
    $missingFields += $requirements.Common.Where({ [string]::IsNullOrEmpty($Row.$_) })
    
    # Check action-specific fields
    if ($ExportAction) {
        $missingFields += $requirements.Export.Where({ [string]::IsNullOrEmpty($Row.$_) })
    }
    if ($ImportAction) {
        $missingFields += $requirements.Import.Where({ [string]::IsNullOrEmpty($Row.$_) })
    }
    
    # Check deployment type
    $deploymentType = if ([string]::IsNullOrEmpty($Row.Type)) { "AzurePaaS" } else { $Row.Type }
    if (-not $Global:DeploymentHandlers.ContainsKey($deploymentType)) {
        Write-OperationStatus "Invalid deployment type: $deploymentType" -Type Error -LogFile $LogFile
        return $false
    }
    
    if ($missingFields.Count -gt 0) {
        Write-OperationStatus "Missing required fields: $($missingFields -join ', ')" -Type Error -LogFile $LogFile
        return $false
    }
    
    return $true
}

function Write-ImportSuccess {
    param(
        [string]$DatabaseName,
        [string]$ServerFQDN,
        [string]$Username,
        [datetime]$StartTime, # Start time must be provided
        [timespan]$Duration = [timespan]::Zero, # Default to zero if not provided
        [string]$LogFile
    )
    
    $endTime = Get-Date
    $actualDuration = New-TimeSpan -Start $StartTime -End $endTime
    $actualDurationFormatted = "{0:hh\:mm\:ss}" -f $actualDuration
    
    $successInfo = @(
        "Import completed successfully! 🎉"
        "Database: $DatabaseName"
        "Server: $ServerFQDN"
        "User: $Username"
        "Total time: $actualDurationFormatted"
        "Started: $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
        "Completed: $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    )
    
    foreach ($line in $successInfo) {
        Write-OperationStatus $line -Type Success -Indent 4 -LogFile $LogFile
    }
}

function Remove-BackupFile {
    param(
        [string]$Path,
        [string]$LogFile
    )
    
    try {
        Remove-Item -Path $Path -Force
        Write-OperationStatus "Cleaned up local file" -Type Info -Indent 2 -LogFile $LogFile
        return $true
    }
    catch {
        Write-OperationStatus "Warning: Could not clean up local file: $_" -Type Warning -Indent 2 -LogFile $LogFile
        return $false
    }
}

function Test-SqlServerAccess {
    [CmdletBinding()]
    param(
        [string]$ServerFQDN,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password,
        [string]$Operation,
        [string]$LogFile,
        [string]$DeploymentType # Added DeploymentType
    )
    
    Write-OperationStatus "Testing $Operation SQL Server access: $ServerFQDN" -Type Info -Indent 2 -LogFile $LogFile
    
    try {
        $trustCert = ($DeploymentType -eq "AzureIaaS")
        
        $connection = New-SqlConnection -ServerFQDN $ServerFQDN -Username $Username -Password $Password -TrustServerCertificate $trustCert
        $connection.Open()
        
        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT name FROM sys.databases WHERE name = @dbname"
        $command.Parameters.AddWithValue("@dbname", $DatabaseName)
        $result = $command.ExecuteScalar()
        
        $connection.Close()
        
        Write-OperationStatus "$Operation server '$ServerFQDN' is accessible" -Type Success -Indent 3 -LogFile $LogFile
        return $true
    }
    catch {
        Write-OperationStatus "Cannot connect to $Operation server '$ServerFQDN': $($_.Exception.Message)" -Type Error -Indent 3 -LogFile $LogFile
        return $false
    }
}

function Copy-FileFromRemote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerFQDN,
        [Parameter(Mandatory = $true)]
        [string]$RemotePath,
        [Parameter(Mandatory = $true)]
        [string]$LocalPath,
        [Parameter(Mandatory = $true)]
        [string]$Username,
        [Parameter(Mandatory = $true)]
        [string]$Password,
        [Parameter(Mandatory = $false)]
        [string]$LogFile
    )

    try {
        Write-OperationStatus "Copying file from remote server..." -Type Action -Indent 2 -LogFile $LogFile
        Write-OperationStatus "Source: $RemotePath" -Type Info -Indent 3 -LogFile $LogFile
        Write-OperationStatus "Destination: $LocalPath" -Type Info -Indent 3 -LogFile $LogFile

        $credential = New-Object System.Management.Automation.PSCredential($Username, (ConvertTo-SecureString $Password -AsPlainText -Force))
        $psSession = New-PSSession -ComputerName $ServerFQDN -Credential $credential

        Copy-Item -FromSession $psSession -Path $RemotePath -Destination $LocalPath -Force

        if (Test-Path $LocalPath) {
            Write-OperationStatus "File copied successfully." -Type Success -Indent 2 -LogFile $LogFile
            return $true
        }
        else {
            Write-OperationStatus "File copy failed. Local file not found after copy." -Type Error -Indent 2 -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-OperationStatus "Error copying file from remote: $($_.Exception.Message)" -Type Error -Indent 2 -LogFile $LogFile
        return $false
    }
    finally {
        if ($psSession) {
            Remove-PSSession $psSession
        }
    }
}

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #
#                                                                                           Azure Storage functions                                                                                    #
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #
function Upload-BacpacToStorage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string]$StorageAccount,
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,
        [Parameter(Mandatory = $true)]
        [string]$StorageKey,
        [Parameter(Mandatory = $true)]
        [string]$BlobName,
        [Parameter(Mandatory = $false)]
        [string]$LogFile
    )
    
    try {
        Write-StatusMessage "Uploading BACPAC to storage..." -Type Action -Indent 3
        Write-LogMessage -LogFile $LogFile -Message "Uploading BACPAC to storage..." -Type Action
        
        # Validate parameters
        if ([string]::IsNullOrWhiteSpace($StorageAccount)) {
            throw "Storage Account Name cannot be empty"
        }
        if ([string]::IsNullOrWhiteSpace($StorageKey)) {
            throw "Storage Key cannot be empty"
        }
        if ([string]::IsNullOrWhiteSpace($ContainerName)) {
            throw "Container Name cannot be empty"
        }
        if (-not (Test-Path $FilePath)) {
            throw "File not found: $FilePath"
        }

        # Create storage context
        $storageContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $StorageKey
        
        # Get file info for logging
        $fileInfo = Get-Item $FilePath
        $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        
        Write-StatusMessage "Uploading file: $BlobName (Size: $fileSizeMB MB)" -Type Info -Indent 4
        Write-LogMessage -LogFile $LogFile -Message "Uploading file: $BlobName (Size: $fileSizeMB MB)" -Type Info
        
        # Upload file
        $result = Set-AzStorageBlobContent -File $FilePath -Container $ContainerName -Blob $BlobName -Context $storageContext -Force
        
        if ($result) {
            Write-StatusMessage "Upload completed successfully" -Type Success -Indent 4
            Write-LogMessage -LogFile $LogFile -Message "Upload completed successfully" -Type Success
            
            Write-StatusMessage "Blob URL: $($result.ICloudBlob.Uri.AbsoluteUri)" -Type Success -Indent 4
            Write-LogMessage -LogFile $LogFile -Message "Blob URL: $($result.ICloudBlob.Uri.AbsoluteUri)" -Type Success
            return $true
        }
        
        throw "Upload failed - no result returned"
    }
    catch {
        Write-StatusMessage "Error uploading to storage: $($_.Exception.Message)" -Type Error -Indent 3
        Write-LogMessage -LogFile $LogFile -Message "Error uploading to storage: $($_.Exception.Message)" -Type Error
        return $false
    }
}

function Upload-BakToStorage {
    [CmdletBinding()]
    param(
        [string]$FilePath,
        [string]$StorageAccount,
        [string]$ContainerName,
        [string]$StorageKey,
        [string]$BlobName,
        [string]$LogFile
    )
    
    try {
        $message = "Uploading BAK file to storage for Managed Instance restore..."
        Write-StatusMessage $message -Type Action -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $message -Type Action
        
        $storageContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $StorageKey
        
        $fileInfo = Get-Item $FilePath
        $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        
        $uploadMessage = "Uploading BAK file: $BlobName (Size: $fileSizeMB MB)"
        Write-StatusMessage $uploadMessage -Type Info -Indent 4
        Write-LogMessage -LogFile $LogFile -Message $uploadMessage -Type Info
        
        $result = Set-AzStorageBlobContent -File $FilePath -Container $ContainerName -Blob $BlobName -Context $storageContext -Force
        
        if ($result) {
            $successMessage = "BAK upload completed successfully"
            Write-StatusMessage $successMessage -Type Success -Indent 4
            Write-LogMessage -LogFile $LogFile -Message $successMessage -Type Success
            
            $urlMessage = "Blob URL: $($result.ICloudBlob.Uri.AbsoluteUri)"
            Write-StatusMessage $urlMessage -Type Success -Indent 4
            Write-LogMessage -LogFile $LogFile -Message $urlMessage -Type Success
            
            # Return the blob URL for use in RESTORE FROM URL
            return $result.ICloudBlob.Uri.AbsoluteUri
        }
        else {
            $errorMessage = "BAK upload failed"
            Write-StatusMessage $errorMessage -Type Error -Indent 4
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            return $null
        }
    }
    catch {
        $errorMessage = "Error uploading BAK to storage: $($_.Exception.Message)"
        Write-StatusMessage $errorMessage -Type Error -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
        return $null
    }
}

function Download-BackupFromStorage {
    [CmdletBinding()]
    param(
        [string]$StorageAccount,
        [string]$ContainerName,
        [string]$StorageKey,
        [string]$BlobName,
        [string]$LocalPath,
        [string]$LogFile
    )
    
    try {
        $fileExtension = [System.IO.Path]::GetExtension($BlobName).ToUpper()
        $message = "Downloading $fileExtension file from storage..."
        Write-StatusMessage $message -Type Action -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $message -Type Action
        
        $storageContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $StorageKey
        
        # Check if blob exists
        $blob = Get-AzStorageBlob -Container $ContainerName -Blob $BlobName -Context $storageContext -ErrorAction Stop
        $blobSizeMB = [math]::Round($blob.Length / 1MB, 2)
        
        $downloadMessage = "Downloading blob: $BlobName (Size: $blobSizeMB MB)"
        Write-StatusMessage $downloadMessage -Type Info -Indent 4
        Write-LogMessage -LogFile $LogFile -Message $downloadMessage -Type Info
        
        # Ensure local directory exists
        $localDir = Split-Path -Path $LocalPath -Parent
        if (-not (Test-Path $localDir)) {
            New-Item -Path $localDir -ItemType Directory -Force | Out-Null
            $dirMessage = "Created local directory: $localDir"
            Write-LogMessage -LogFile $LogFile -Message $dirMessage -Type Info
        }
        
        Get-AzStorageBlobContent -Container $ContainerName -Blob $BlobName -Destination $LocalPath -Context $storageContext -Force | Out-Null
        
        if (Test-Path $LocalPath) {
            $successMessage = "Download completed successfully"
            Write-StatusMessage $successMessage -Type Success -Indent 4
            Write-LogMessage -LogFile $LogFile -Message $successMessage -Type Success
            Write-LogMessage -LogFile $LogFile -Message "Downloaded to: $LocalPath" -Type Success
            return $true
        }
        else {
            $errorMessage = "Download failed - file not found after download"
            Write-StatusMessage $errorMessage -Type Error -Indent 4
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            return $false
        }
    }
    catch {
        $errorMessage = "Error downloading from storage: $($_.Exception.Message)"
        Write-StatusMessage $errorMessage -Type Error -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
        return $false
    }
}

# Keep the original function for backward compatibility
function Download-BacpacFromStorage {
    [CmdletBinding()]
    param(
        [string]$StorageAccount,
        [string]$ContainerName,
        [string]$StorageKey,
        [string]$BlobName,
        [string]$LocalPath,
        [string]$LogFile
    )
    
    return Download-BackupFromStorage -StorageAccount $StorageAccount -ContainerName $ContainerName -StorageKey $StorageKey -BlobName $BlobName -LocalPath $LocalPath -LogFile $LogFile
}

# Keep the original function for backward compatibility but make it call the new generic one
function Find-LatestBacpacBlob {
    [CmdletBinding()]
    param(
        [string]$StorageAccount,
        [string]$ContainerName,
        [string]$StorageKey,
        [string]$DatabaseName,
        [string]$LogFile,
        [string]$OperationId = $null
    )
    
    return Find-LatestBackupBlob -StorageAccount $StorageAccount -ContainerName $ContainerName -StorageKey $StorageKey -DatabaseName $DatabaseName -LogFile $LogFile -OperationId $OperationId -FileExtensions @("bacpac")
}

function Find-LatestBackupBlob {
    [CmdletBinding()]
    param(
        [string]$StorageAccount,
        [string]$ContainerName,
        [string]$StorageKey,
        [string]$DatabaseName,
        [string]$LogFile,
        [string]$OperationId = $null,
        [string[]]$FileExtensions = @("bacpac", "bak")
    )
    
    try {
        $message = "Searching for latest backup file for database: $DatabaseName"
        Write-StatusMessage $message -Type Info -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $message -Type Info
        
        $storageContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $StorageKey
        
        # Get all blobs that match the database name pattern for specified file extensions
        $searchPatterns = @()
        
        foreach ($extension in $FileExtensions) {
            # If OperationId is provided, search for that specific pattern first
            if ($OperationId) {
                $searchPatterns += "${OperationId}_${DatabaseName}*.$extension"
            }
            
            # Also search for database name with any prefix (covers Operation ID prefixed files)
            $searchPatterns += "*${DatabaseName}*.$extension"
            
            # And search for files that start with just the database name (legacy pattern)
            $searchPatterns += "${DatabaseName}*.$extension"
        }
        
        $allBlobs = @()
        
        foreach ($pattern in $searchPatterns) {
            Write-LogMessage -LogFile $LogFile -Message "Searching with pattern: $pattern" -Type Info
            $blobs = Get-AzStorageBlob -Container $ContainerName -Context $storageContext | 
            Where-Object { $_.Name -like $pattern }
            
            if ($blobs) {
                $allBlobs += $blobs
                Write-LogMessage -LogFile $LogFile -Message "Found $($blobs.Count) files matching pattern: $pattern" -Type Info
            }
        }
        
        # Remove duplicates and sort by LastModified descending
        $uniqueBlobs = $allBlobs | Sort-Object Name -Unique | Sort-Object LastModified -Descending
        
        Write-LogMessage -LogFile $LogFile -Message "Found $($uniqueBlobs.Count) total matching backup files" -Type Info
        
        if ($uniqueBlobs.Count -eq 0) {
            $warningMessage = "No backup files found for database: $DatabaseName"
            Write-StatusMessage $warningMessage -Type Warning -Indent 4
            Write-LogMessage -LogFile $LogFile -Message $warningMessage -Type Warning
            return $null
        }
        
        # Log all found files for debugging
        Write-LogMessage -LogFile $LogFile -Message "Available backup files:" -Type Info
        foreach ($blob in $uniqueBlobs) {
            Write-LogMessage -LogFile $LogFile -Message "  - $($blob.Name) (Modified: $($blob.LastModified))" -Type Info
        }
        
        $latestBlob = $uniqueBlobs[0]
        $foundMessage = "Found latest backup: $($latestBlob.Name) (Modified: $($latestBlob.LastModified))"
        Write-StatusMessage $foundMessage -Type Success -Indent 4
        Write-LogMessage -LogFile $LogFile -Message $foundMessage -Type Success
        
        return $latestBlob.Name
    }
    catch {
        $errorMessage = "Error searching for backup files: $($_.Exception.Message)"
        Write-StatusMessage $errorMessage -Type Error -
        $errorMessage = "Error searching for backup files: $($_.Exception.Message)"
        Write-StatusMessage $errorMessage -Type Error -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
        return $null
    }
}

function New-SasTokenFromStorageKey {
    [CmdletBinding()]
    param(
        [string]$StorageAccount,
        [string]$StorageKey,
        [string]$ContainerName,
        [datetime]$ExpiryTime = (Get-Date).AddHours(2)
    )
    
    try {
        $storageContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $StorageKey
        
        # Generate container SAS token with read permissions
        $sasToken = New-AzStorageContainerSASToken -Name $ContainerName -Context $storageContext -Permission r -ExpiryTime $ExpiryTime
        
        # Remove the leading '?' if present
        if ($sasToken.StartsWith('?')) {
            $sasToken = $sasToken.Substring(1)
        }
        
        return $sasToken
    }
    catch {
        Write-Error "Failed to generate SAS token: $($_.Exception.Message)"
        return $null
    }
}

# New helper function to handle backup file management
function Get-BackupFileInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Row
    )

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $extension = ".bacpac"  # Default to .bacpac for Azure SQL
    $backupFileName = "$($Row.Operation_ID)_$($Row.Database_Name)_${timestamp}${extension}"
    $localBackupPath = Join-Path -Path $Row.Local_Folder -ChildPath $backupFileName

    return @{
        FileName = $backupFileName
        FullPath = $localBackupPath
    }
}


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #
#                                                                                           Export functions                                                                                           #
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #

function Invoke-SqlPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,

        [Parameter(Mandatory = $true)]
        [string]$SqlPackagePath,

        [Parameter(Mandatory = $false)]
        [string]$LogFile,

        [Parameter(Mandatory = $false)]
        [string]$ProgressMessage = "Processing with SqlPackage..."
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $outputFile = [System.IO.Path]::GetTempFileName()
    $errorFile = "$outputFile.err"

    try {
        $process = Start-Process -FilePath $SqlPackagePath -ArgumentList $ArgumentList -NoNewWindow -PassThru -RedirectStandardOutput $outputFile -RedirectStandardError $errorFile
        
        Show-OperationProgress -Operation $ProgressMessage -Stopwatch $stopwatch -LogFile $LogFile -ProgressCheck { $process.HasExited }
        
        $stopwatch.Stop()

        if ($process.ExitCode -ne 0) {
            $errorMessage = "SqlPackage operation failed with exit code $($process.ExitCode)."
            Write-OperationStatus -Message $errorMessage -Type Error -Indent 3 -LogFile $LogFile
            
            if (Test-Path $errorFile) {
                $errorContent = Get-Content $errorFile
                if ($errorContent) {
                    Write-OperationStatus -Message "Error details:" -Type Error -Indent 4 -LogFile $LogFile
                    $errorContent | ForEach-Object {
                        Write-OperationStatus -Message $_ -Type Error -Indent 5 -LogFile $LogFile
                    }
                }
            }
            return $false
        }

        $totalTimeFormatted = "{0:hh\:mm\:ss}" -f $stopwatch.Elapsed
        $successMessage = "SqlPackage operation completed successfully in $totalTimeFormatted."
        Write-OperationStatus -Message $successMessage -Type Success -Indent 3 -LogFile $LogFile
        return $true
    }
    catch {
        Write-OperationStatus -Message "Error invoking SqlPackage: $($_.Exception.Message)" -Type Error -Indent 3 -LogFile $LogFile
        return $false
    }
    finally {
        if (Test-Path $outputFile) { Remove-Item $outputFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $errorFile) { Remove-Item $errorFile -Force -ErrorAction SilentlyContinue }
    }
}

function Export-SqlDatabaseToBacpac {
    [CmdletBinding()]
    param(
        [string]$ServerFQDN,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password,
        [string]$OutputPath,
        [string]$SqlPackagePath,
        [string]$LogFile
    )
    
    $message = "Starting BACPAC export from '$DatabaseName' on '$ServerFQDN'..."
    Write-OperationStatus -Message $message -Type Action -Indent 3 -LogFile $LogFile
    
    $exportArgs = @(
        "/Action:Export",
        "/SourceServerName:$ServerFQDN",
        "/SourceDatabaseName:$DatabaseName",
        "/SourceUser:$Username",
        "/SourcePassword:$Password",
        "/TargetFile:$OutputPath",
        "/p:VerifyExtraction=false",
        "/p:Storage=Memory",
        "/p:CommandTimeout=0"
    )
    
    $success = Invoke-SqlPackage -ArgumentList $exportArgs -SqlPackagePath $SqlPackagePath -LogFile $LogFile -ProgressMessage "Exporting BACPAC"
    
    if ($success -and (Test-Path $OutputPath)) {
        $fileInfo = Get-Item $OutputPath
        $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        $sizeMessage = "BACPAC file size: $fileSizeMB MB"
        Write-OperationStatus -Message $sizeMessage -Type Success -Indent 4 -LogFile $LogFile
    }
    
    return $success
}

function Export-SqlDatabaseToBak {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerFQDN,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $true)]
        [string]$Username,
        
        [Parameter(Mandatory = $true)]
        [string]$Password,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [string]$LogFile,
        
        [Parameter(Mandatory = $false)]
        [int]$CommandTimeout = 3600,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Full', 'Differential', 'Log')]
        [string]$BackupType = 'Full',
        
        [Parameter(Mandatory = $false)]
        [int]$Compression = 1
    )
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $startTime = Get-Date
        
        $message = "Starting BAK file export from '$DatabaseName' on '$ServerFQDN'..."
        Write-StatusMessage $message -Type Action -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $message -Type Action
        
        # Ensure output directory exists
        $outputDir = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
            Write-LogMessage -LogFile $LogFile -Message "Created output directory: $outputDir" -Type Info
        }
        
        # Build the backup command based on backup type
        $backupTypeSQL = switch ($BackupType) {
            'Full' { 'DATABASE' }
            'Differential' { 'DATABASE WITH DIFFERENTIAL' }
            'Log' { 'LOG' }
        }
        
        $compressionOption = if ($Compression -eq 1) { ", COMPRESSION" } else { "" }
        
        $backupSQL = @"
BACKUP $backupTypeSQL [$DatabaseName] 
TO DISK = N'$OutputPath' 
WITH NOFORMAT, INIT, NAME = N'$DatabaseName-$BackupType-$(Get-Date -Format 'yyyyMMdd_HHmmss')', 
SKIP, NOREWIND, NOUNLOAD$compressionOption, STATS = 10
"@
        
        Write-LogMessage -LogFile $LogFile -Message "Executing SQL Backup Command: $backupSQL" -Type Info
        
        # Create SQL connection
        Add-Type -AssemblyName System.Data
        $connectionString = "Server=$ServerFQDN;Database=master;User Id=$Username;Password=$Password;Connection Timeout=30;Encrypt=True;TrustServerCertificate=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        
        try {
            $connection.Open()
            
            # Create and execute the backup command
            $command = $connection.CreateCommand()
            $command.CommandText = $backupSQL
            $command.CommandTimeout = $CommandTimeout
            
            # Set up progress reporting
            $reader = $null
            $outputFile = [System.IO.Path]::GetTempFileName()
            
            # Create a data adapter to capture the BACKUP command output
            $dataTable = New-Object System.Data.DataTable
            
            # Progress monitoring
            $spinChars = '|', '/', '-', '\'
            $spinIndex = 0
            $lastProgressTime = [DateTime]::Now
            $progressInterval = [TimeSpan]::FromSeconds(5)
            $lastPercentComplete = 0
            
            Write-StatusMessage "Starting SQL backup process..." -Type Info -Indent 4
            
            # Execute the backup command asynchronously
            $task = $command.ExecuteNonQueryAsync()
            
            # Monitor the backup progress
            while (-not $task.IsCompleted) {
                $spinChar = $spinChars[$spinIndex]
                $spinIndex = ($spinIndex + 1) % $spinChars.Length
                $elapsedTime = $stopwatch.Elapsed
                $elapsedFormatted = "{0:hh\:mm\:ss}" -f $elapsedTime
                
                # Check for progress every few seconds
                if (([DateTime]::Now - $lastProgressTime) -ge $progressInterval) {
                    # Query the backup progress using a separate connection
                    $progressConn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
                    $progressConn.Open()
                    $progressCmd = $progressConn.CreateCommand()
                    $progressCmd.CommandText = "SELECT r.percent_complete FROM sys.dm_exec_requests r WHERE r.session_id = @@SPID AND r.command LIKE 'BACKUP%'"
                    
                    try {
                        $percentComplete = [int]($progressCmd.ExecuteScalar())
                        if ($percentComplete -gt 0 -and $percentComplete -ne $lastPercentComplete) {
                            $progressMsg = "Backup progress: $percentComplete% complete"
                            Write-StatusMessage $progressMsg -Type Info -Indent 4
                            Write-LogMessage -LogFile $LogFile -Message $progressMsg -Type Info
                            $lastPercentComplete = $percentComplete
                        }
                    }
                    catch {
                        # Ignore errors in progress reporting
                    }
                    finally {
                        $progressConn.Close()
                    }
                    
                    $lastProgressTime = [DateTime]::Now
                }
                
                Write-Host "`r      $spinChar Backing up database... Time elapsed: $elapsedFormatted" -NoNewline
                Start-Sleep -Milliseconds 250
            }
            
            # Get the final result
            $result = $task.Result
            Write-Host "`r                                                                    " -NoNewline
            
            # Check if the backup completed successfully
            $stopwatch.Stop()
            $totalTime = $stopwatch.Elapsed
            $totalTimeFormatted = "{0:hh\:mm\:ss}" -f $totalTime
            
            if ($task.Status -eq 'RanToCompletion') {
                $successMessage = "Backup completed successfully in $totalTimeFormatted"
                Write-StatusMessage $successMessage -Type Success -Indent 3
                Write-LogMessage -LogFile $LogFile -Message $successMessage -Type Success
                
                if (Test-Path $OutputPath) {
                    $fileInfo = Get-Item $OutputPath
                    $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
                    $sizeMessage = "BAK file size: $fileSizeMB MB"
                    Write-StatusMessage $sizeMessage -Type Success -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message $sizeMessage -Type Success
                }
                
                return $true
            }
            else {
                $errorMessage = "Backup task completed with status: $($task.Status)"
                Write-StatusMessage $errorMessage -Type Error -Indent 3
                Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                return $false
            }
        }
        catch {
            $errorMessage = "Error during SQL backup: $($_.Exception.Message)"
            Write-StatusMessage $errorMessage -Type Error -Indent 3
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            return $false
        }
        finally {
            # Close the connection
            if ($connection -and $connection.State -eq 'Open') {
                $connection.Close()
            }
        }
    }
    catch {
        $errorMessage = "Error during export to BAK: $($_.Exception.Message)"
        Write-StatusMessage $errorMessage -Type Error -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
        return $false
    }
}

function Export-DatabaseOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Row,
        [Parameter(Mandatory = $true)]
        [string]$SqlPackagePath,
        [Parameter(Mandatory = $false)]
        [string]$LogFile,
        [Parameter(Mandatory = $false)]
        [datetime]$StartTime
    )
    
    $exportStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Write-LogMessage -LogFile $LogFile -Message "Starting export database operation" -Type Action
        
        $deploymentType = if ([string]::IsNullOrEmpty($Row.Type)) { "AzurePaaS" } else { $Row.Type }
        $srcServerFQDN = Get-ServerFQDN -ServerName $Row.SRC_server -DeploymentType $deploymentType
        
        # Generate backup file path from components
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $extension = if ($deploymentType -eq "AzureIaaS") { ".bak" } else { ".bacpac" }
        $backupFileName = "$($Row.Operation_ID)_$($Row.Database_Name)_${timestamp}${extension}"
        $localBackupPath = Join-Path -Path $Row.Local_Folder -ChildPath $backupFileName
        
        Write-StatusMessage "Using backup file: $backupFileName" -Type Info -Indent 2
        Write-LogMessage -LogFile $LogFile -Message "Using backup file: $backupFileName" -Type Info
        
        
        # Export based on deployment type
        $exportSuccess = switch ($deploymentType) {
            "AzurePaaS" {
                Export-SqlDatabaseToBacpac -ServerFQDN $srcServerFQDN `
                    -DatabaseName $Row.Database_Name `
                    -Username $Row.SRC_SQL_Admin `
                    -Password $Row.SRC_SQL_Password `
                    -OutputPath $localBackupPath `
                    -SqlPackagePath $SqlPackagePath `
                    -LogFile $LogFile
            }
            "AzureMI" {
                Export-SqlDatabaseToBacpac -ServerFQDN $srcServerFQDN `
                    -DatabaseName $Row.Database_Name `
                    -Username $Row.SRC_SQL_Admin `
                    -Password $Row.SRC_SQL_Password `
                    -OutputPath $localBackupPath `
                    -SqlPackagePath $SqlPackagePath `
                    -LogFile $LogFile
            }
            "AzureIaaS" {
                Export-SqlDatabaseToBak -ServerFQDN $srcServerFQDN `
                    -DatabaseName $Row.Database_Name `
                    -Username $Row.SRC_SQL_Admin `
                    -Password $Row.SRC_SQL_Password `
                    -OutputPath $localBackupPath `
                    -LogFile $LogFile
            }
            default {
                Export-SqlDatabaseToBacpac -ServerFQDN $srcServerFQDN `
                    -DatabaseName $Row.Database_Name `
                    -Username $Row.SRC_SQL_Admin `
                    -Password $Row.SRC_SQL_Password `
                    -OutputPath $localBackupPath `
                    -SqlPackagePath $SqlPackagePath `
                    -LogFile $LogFile
            }
        }
        
        if (-not $exportSuccess) {
            Write-StatusMessage "Failed to export database to local file" -Type Error -Indent 2
            return $false
        }

        $uploadPath = $localBackupPath
        if ($deploymentType -eq "AzureIaaS") {
            $drive = $localBackupPath.Substring(0,1)
            $folder = $localBackupPath.Substring(2)
            $remotePathForCopy = "$($drive):\$($folder)"
            $localTempPath = Join-Path $env:TEMP $backupFileName
            $copySuccess = Copy-FileFromRemote -ServerFQDN $Row.SRC_server -RemotePath $remotePathForCopy -LocalPath $localTempPath -Username $Row.PS_User -Password $Row.PS_Password -LogFile $LogFile
            if (-not $copySuccess) {
                Write-StatusMessage "Failed to copy backup file from remote server." -Type Error -Indent 2
                return $false
            }
            $uploadPath = $localTempPath
        }
        
        # Upload to storage using the same filename
        $uploadFunction = if ($deploymentType -eq "AzureIaaS") { ${function:Upload-BakToStorage} } else { ${function:Upload-BacpacToStorage} }
        $uploadSuccess = & $uploadFunction -FilePath $uploadPath `
            -StorageAccount $Row.Storage_Account `
            -ContainerName $Row.Storage_Container `
            -StorageKey $Row.Storage_Access_Key `
            -BlobName $backupFileName `
            -LogFile $LogFile
            
        if ($deploymentType -eq "AzureIaaS" -and (Test-Path $uploadPath)) {
            Remove-Item -Path $uploadPath -Force
        }
            
        if (-not $uploadSuccess) {
            Write-StatusMessage "Failed to upload backup file to storage" -Type Error -Indent 2
            return $false
        }
        
        $exportStopwatch.Stop()
        $exportEndTime = Get-Date
        $exportDuration = if ($PSBoundParameters.ContainsKey('StartTime')) { New-TimeSpan -Start $StartTime -End $exportEndTime } else { $exportStopwatch.Elapsed }
        $exportDurationFormatted = "{0:hh\:mm\:ss}" -f $exportDuration
        Write-StatusMessage "Export operation completed successfully in $exportDurationFormatted" -Type Success -Indent 2
        Write-LogMessage -LogFile $LogFile -Message "Export operation duration: $exportDurationFormatted" -Type Success
        
        return $true
    }
    catch {
        Write-StatusMessage "Error in export operation: $($_.Exception.Message)" -Type Error -Indent 2
        Write-LogMessage -LogFile $LogFile -Message "Error in export operation: $($_.Exception.Message)" -Type Error
        return $false
    }
    finally {
        $exportStopwatch.Stop()
    }
}

function Export-BacpacWithProgress {
    [CmdletBinding()]
    param(
        [string]$ServerFQDN,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password,
        [string]$OutputPath,
        [string]$SqlPackagePath,
        [string]$LogFile
    )
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    $exportArgs = @(
        "/Action:Export",
        "/SourceServerName:$ServerFQDN",
        "/SourceDatabaseName:$DatabaseName",
        "/SourceUser:$Username",
        "/SourcePassword:$Password",
        "/TargetFile:$OutputPath",
        "/p:VerifyExtraction=false",
        "/p:Storage=Memory",
        "/p:CommandTimeout=0"
    )
    
    $process = Start-Process -FilePath $SqlPackagePath -ArgumentList $exportArgs -NoNewWindow -PassThru
    
    Show-OperationProgress -Operation "Exporting BACPAC" -Stopwatch $stopwatch -LogFile $LogFile -ProgressCheck {
        $process.HasExited
    }
    
    return $process.ExitCode -eq 0
}

function Export-BakWithProgress {
    [CmdletBinding()]
    param(
        [string]$ServerFQDN,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password,
        [string]$OutputPath,
        [string]$LogFile,
        [string]$DeploymentType # Added DeploymentType
    )
    
    $trustCert = ($DeploymentType -eq "AzureIaaS")
    $connection = New-SqlConnection -ServerFQDN $ServerFQDN -Database "master" -Username $Username -Password $Password -TrustServerCertificate $trustCert
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        $connection.Open()
        $backupCmd = $connection.CreateCommand()
        $backupCmd.CommandText = "BACKUP DATABASE [$DatabaseName] TO DISK = N'$OutputPath' WITH COMPRESSION, STATS = 10"
        $backupTask = $backupCmd.ExecuteNonQueryAsync()
        
        Show-OperationProgress -Operation "Exporting BAK" -Stopwatch $stopwatch -LogFile $LogFile -ProgressCheck {
            $backupTask.IsCompleted
        }
        
        return $backupTask.Status -eq 'RanToCompletion'
    }
    finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
    }
}

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #
#                                                                                           Import funcitons                                                                                           #
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #
function Import-BacpacToSqlDatabase {
    [CmdletBinding()]
    param(
        [string]$BacpacSource,
        [string]$ServerFQDN,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password,
        [string]$SqlPackagePath,
        [string]$LogFile
    )
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $startTime = Get-Date
    
    try {
        # Create temp directory for download
        $tempDir = Join-Path $env:TEMP "SQLMove"
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }
        
        # Download BACPAC to temp location
        $localBacpac = Join-Path $tempDir "$DatabaseName.bacpac"
        $downloadSuccess = Download-BackupFromStorage -StorageAccount $Row.Storage_Account `
            -ContainerName $Row.Storage_Container `
            -StorageKey $Row.Storage_Access_Key `
            -BlobName $blobName `
            -LocalPath $localBacpac `
            -LogFile $LogFile
            
        if (-not $downloadSuccess) {
            throw "Failed to download BACPAC file"
        }
        
        # Import using local file
        $importArgs = @(
            "/action:Import"
            "/SourceFile:$localBacpac"
            "/TargetServerName:$ServerFQDN"
            "/TargetDatabaseName:$DatabaseName"
            "/TargetUser:$Username"
            "/TargetPassword:$Password"
            "/p:CommandTimeout=3600"
        )
        
        $process = Start-Process -FilePath $SqlPackagePath -ArgumentList $importArgs -NoNewWindow -PassThru
        
        Show-OperationProgress -Operation "Importing BACPAC" -Stopwatch $stopwatch -LogFile $LogFile -ProgressCheck {
            $process.HasExited
        }
        
        # Cleanup temp file
        if (Test-Path $localBacpac) {
            Remove-Item $localBacpac -Force
        }
        
        if ($process.ExitCode -eq 0) {
            Write-ImportSuccess -DatabaseName $DatabaseName -ServerFQDN $ServerFQDN -Username $Username `
                -StartTime $startTime -Duration $stopwatch.Elapsed -LogFile $LogFile
            return $true
        }
        
        Write-OperationStatus "Import failed with exit code $($process.ExitCode)" -Type Error -Indent 3 -LogFile $LogFile
        return $false
    }
    catch {
        Write-OperationStatus "Error during import: $($_.Exception.Message)" -Type Error -Indent 3 -LogFile $LogFile
        return $false
    }
}

function Import-BacpacToSqlManagedInstance {
    [CmdletBinding()]
    param(
        [string]$BacpacSource,
        [string]$ServerFQDN,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password,
        [string]$SqlPackagePath,
        [string]$LogFile,
        [string]$DeploymentType # Added DeploymentType
    )
    
    $startTime = Get-Date
    
    try {
        $trustCert = ($DeploymentType -eq "AzureIaaS")
        # First, check and drop existing database
        $connection = New-SqlConnection -ServerFQDN $ServerFQDN -Username $Username -Password $Password -TrustServerCertificate $trustCert
        $connection.Open()

        Write-OperationStatus "Checking for existing database..." -Type Info -Indent 3 -LogFile $LogFile

        $dropSQL = "IF EXISTS (SELECT * FROM sys.databases WHERE name = '$DatabaseName') BEGIN DROP DATABASE [$DatabaseName]; END"
        $command = $connection.CreateCommand()
        $command.CommandText = $dropSQL
        $command.CommandTimeout = 300
        $command.ExecuteNonQuery()
        
        Write-OperationStatus "Database dropped successfully" -Type Success -Indent 3 -LogFile $LogFile
        $connection.Close()

        # Proceed with import
        $importArgs = @(
            "/action:Import",
            "/SourceFile:$BacpacSource",
            "/TargetServerName:$ServerFQDN",
            "/TargetDatabaseName:$DatabaseName",
            "/TargetUser:$Username",
            "/TargetPassword:$Password",
            "/p:CommandTimeout=3600"
        )
        
        $success = Invoke-SqlPackage -ArgumentList $importArgs -SqlPackagePath $SqlPackagePath -LogFile $LogFile -ProgressMessage "Importing BACPAC to MI"
        
        if ($success) {
            Write-ImportSuccess -DatabaseName $DatabaseName -ServerFQDN $ServerFQDN -Username $Username -StartTime $startTime -LogFile $LogFile
        }
        
        return $success
    }
    catch {
        Write-OperationStatus "Error during MI import: $($_.Exception.Message)" -Type Error -Indent 3 -LogFile $LogFile
        return $false
    }
}

# Placeholder for future IaaS import method
function Import-BacpacToSqlIaaS {
    [CmdletBinding()]
    param(
        [string]$BacpacSource,
        [string]$ServerFQDN,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password,
        [string]$SqlPackagePath,
        [string]$LogFile
    )
    
    Write-StatusMessage "Azure SQL IaaS VM import not yet implemented" -Type Warning -Indent 3
    Write-LogMessage -LogFile $LogFile -Message "Azure SQL IaaS VM import not yet implemented" -Type Warning
    
    # TODO: Implement IaaS-specific import logic
    return $false
}

function Import-BakToSqlDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BakSource,
        
        [Parameter(Mandatory = $true)]
        [string]$ServerFQDN,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $true)]
        [string]$Username,
        
        [Parameter(Mandatory = $true)]
        [string]$Password,
        
        [Parameter(Mandatory = $false)]
        [string]$LogFile,
        
        [Parameter(Mandatory = $false)]
        [int]$CommandTimeout = 3600,
        
        [Parameter(Mandatory = $false)]
        [switch]$Replace = $true,
        
        [Parameter(Mandatory = $false)]
        [string]$DataFileLocation,
        
        [Parameter(Mandatory = $false)]
        [string]$LogFileLocation,
        
        # New parameters for Azure Managed Instance
        [Parameter(Mandatory = $false)]
        [string]$StorageAccount,
        
        [Parameter(Mandatory = $false)]
        [string]$StorageContainer,
        
        [Parameter(Mandatory = $false)]
        [string]$StorageKey
    )

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $startTime = Get-Date

        $message = "Starting BAK file restore to '$DatabaseName' on '$ServerFQDN'..."
        Write-StatusMessage $message -Type Action -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $message -Type Action

        # Get file size for progress context
        $fileSizeMB = 0
        try {
            $fileInfo = Get-Item $BakSource -ErrorAction Stop
            $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
            $sizeMessage = "Restore source size: $fileSizeMB MB"
            Write-StatusMessage $sizeMessage -Type Info -Indent 4
            Write-LogMessage -LogFile $LogFile -Message $sizeMessage -Type Info
        }
        catch {
            # This will fail if the file is on the remote server, which is expected for IaaS.
            Write-LogMessage -LogFile $LogFile -Message "Could not get local file size for $BakSource. This is expected for IaaS." -Type Info
        }

        # Check if this is Azure SQL Managed Instance (contains specific patterns in FQDN)
        $isAzureManagedInstance = $ServerFQDN -match "\.database\.windows\.net$"
        $bakUrl = $null
        
        if ($isAzureManagedInstance -and $StorageAccount -and $StorageContainer -and $StorageKey) {
            Write-StatusMessage "Detected Azure SQL Managed Instance - uploading BAK to storage first" -Type Info -Indent 4
            Write-LogMessage -LogFile $LogFile -Message "Azure SQL Managed Instance detected - BAK must be uploaded to storage" -Type Info
            
            # Generate blob name with timestamp
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $bakFileName = [System.IO.Path]::GetFileNameWithoutExtension($BakSource)
            $blobName = "${bakFileName}_${timestamp}.bak"
            
            # Upload BAK file to storage
            $bakUrl = Upload-BakToStorage -FilePath $BakSource `
                -StorageAccount $StorageAccount `
                -ContainerName $StorageContainer `
                -StorageKey $StorageKey `
                -BlobName $blobName `
                -LogFile $LogFile
            
            if (-not $bakUrl) {
                $errorMessage = "Failed to upload BAK file to storage"
                Write-StatusMessage $errorMessage -Type Error -Indent 4
                Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                return $false
            }
            
            Write-StatusMessage "BAK file uploaded successfully, proceeding with restore from URL" -Type Success -Indent 4
            Write-LogMessage -LogFile $LogFile -Message "BAK file uploaded to: $bakUrl" -Type Success
        }

        # Create SQL connection
        Add-Type -AssemblyName System.Data
        $trustCert = ($DeploymentType -eq "AzureIaaS")
        $connectionString = "Server=$ServerFQDN;Database=master;User Id=$Username;Password=$Password;Connection Timeout=30;Encrypt=True;TrustServerCertificate=$trustCert;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        
        try {
            $connection.Open()
            Write-StatusMessage "Connected to SQL Server successfully" -Type Success -Indent 4
            Write-LogMessage -LogFile $LogFile -Message "Connected to SQL Server successfully" -Type Success

            # Build the RESTORE command based on whether we're using URL or local file
            $restoreSQL = ""
            $credentialName = ""
            
            if ($bakUrl) {
                # Generate SAS token from storage key
                $sasToken = New-SasTokenFromStorageKey -StorageAccount $StorageAccount -StorageKey $StorageKey -ContainerName $StorageContainer
    
                if (-not $sasToken) {
                    $errorMessage = "Failed to generate SAS token for storage access"
                    Write-StatusMessage $errorMessage -Type Error -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                    return $false
                }
    
                # Create credential name that matches the container URL
                $credentialName = "https://$StorageAccount.blob.core.windows.net/$StorageContainer"
    
                Write-StatusMessage "Creating SQL credential for storage access..." -Type Info -Indent 4
                Write-LogMessage -LogFile $LogFile -Message "Creating SQL credential: $credentialName" -Type Info
    
                # Create SQL Server credential with SAS token
                $createCredentialSQL = @"
CREATE CREDENTIAL [$credentialName]
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
SECRET = '$sasToken';
"@
                
                Write-LogMessage -LogFile $LogFile -Message "Creating credential with SQL: $createCredentialSQL" -Type Info
                
                $credentialCommand = $connection.CreateCommand()
                $credentialCommand.CommandText = $createCredentialSQL
                $credentialCommand.CommandTimeout = $CommandTimeout
                
                try {
                    $credentialCommand.ExecuteNonQuery() | Out-Null
                    Write-StatusMessage "SQL credential created successfully" -Type Success -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message "SQL credential created successfully" -Type Success
                    
                    # Verify the credential was created
                    $verifyCredentialCommand = $connection.CreateCommand()
                    $verifyCredentialCommand.CommandText = "SELECT name FROM sys.credentials WHERE name = @credName"
                    $verifyCredentialCommand.Parameters.AddWithValue("@credName", $credentialName)
                    $credExists = $verifyCredentialCommand.ExecuteScalar()
                    
                    if ($credExists) {
                        Write-StatusMessage "Credential verification successful" -Type Success -Indent 4
                        Write-LogMessage -LogFile $LogFile -Message "Credential verification successful: $credExists" -Type Success
                    }
                    else {
                        Write-StatusMessage "Warning: Credential not found after creation" -Type Warning -Indent 4
                        Write-LogMessage -LogFile $LogFile -Message "Warning: Credential not found after creation" -Type Warning
                    }
                }
                catch {
                    # If credential already exists, try to drop and recreate
                    if ($_.Exception.Message -like "*already exists*") {
                        Write-StatusMessage "Credential exists, recreating..." -Type Info -Indent 4
                        Write-LogMessage -LogFile $LogFile -Message "Credential exists, attempting to recreate" -Type Info
                        
                        try {
                            $dropCredentialCommand = $connection.CreateCommand()
                            $dropCredentialCommand.CommandText = "DROP CREDENTIAL [$credentialName]"
                            $dropCredentialCommand.CommandTimeout = $CommandTimeout
                            $dropCredentialCommand.ExecuteNonQuery() | Out-Null
                            
                            # Recreate the credential
                            $credentialCommand.ExecuteNonQuery() | Out-Null
                            Write-StatusMessage "SQL credential recreated successfully" -Type Success -Indent 4
                            Write-LogMessage -LogFile $LogFile -Message "SQL credential recreated successfully" -Type Success
                        }
                        catch {
                            $errorMessage = "Failed to recreate SQL credential: $($_.Exception.Message)"
                            Write-StatusMessage $errorMessage -Type Error -Indent 4
                            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                            return $false
                        }
                    }
                    else {
                        $errorMessage = "Failed to create SQL credential: $($_.Exception.Message)"
                        Write-StatusMessage $errorMessage -Type Error -Indent 4
                        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                        return $false
                    }
                }
                
                # For Azure SQL MI, we need to check if database exists first and drop it if Replace is specified
                if ($Replace) {
                    Write-StatusMessage "Checking if database exists for replacement..." -Type Info -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message "Checking if database exists for replacement" -Type Info
                    
                    $checkDbCommand = $connection.CreateCommand()
                    $checkDbCommand.CommandText = "SELECT COUNT(*) FROM sys.databases WHERE name = @dbname"
                    $checkDbCommand.Parameters.AddWithValue("@dbname", $DatabaseName)
                    $dbExists = [int]$checkDbCommand.ExecuteScalar()
                    
                    if ($dbExists -gt 0) {
                        Write-StatusMessage "Database exists, dropping before restore..." -Type Info -Indent 4
                        Write-LogMessage -LogFile $LogFile -Message "Database exists, dropping before restore" -Type Info
                        
                        # First, kill all existing connections
                        $killConnectionsCommand = $connection.CreateCommand()
                        $killConnectionsCommand.CommandText = @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '$($Row.Database_Name)')
BEGIN
    SELECT session_id INTO #tempSessions FROM sys.dm_exec_sessions 
    WHERE database_id = DB_ID('$($Row.Database_Name)');
    
    DECLARE @kill varchar(8000) = '';
    SELECT @kill = @kill + 'KILL ' + CONVERT(varchar(5), session_id) + ';'
    FROM #tempSessions;
    
    EXEC(@kill);
    DROP TABLE #tempSessions;
END
"@
                        $killConnectionsCommand.ExecuteNonQuery()

                        # Then drop the database
                        $dropCommand = $connection.CreateCommand()
                        $dropCommand.CommandText = "DROP DATABASE IF EXISTS [$($Row.Database_Name)]"
                        $dropCommand.ExecuteNonQuery()
                        
                        try {
                            $killConnectionsCommand.ExecuteNonQuery() | Out-Null
                            Write-StatusMessage "Database dropped successfully" -Type Success -Indent 4
                            Write-LogMessage -LogFile $LogFile -Message "Database dropped successfully" -Type Success
                        }
                        catch {
                            $warningMessage = "Warning: Could not drop existing database: $($_.Exception.Message)"
                            Write-StatusMessage $warningMessage -Type Warning -Indent 4
                            Write-LogMessage -LogFile $LogFile -Message $warningMessage -Type Warning
                            Write-StatusMessage "Proceeding with restore - may fail if database exists" -Type Warning -Indent 4
                        }
                    }
                }
                
                # Azure SQL MI restore syntax - minimal options only (no REPLACE, no STATS)
                Write-StatusMessage "Building minimal restore command for Azure SQL Managed Instance..." -Type Info -Indent 4
                Write-LogMessage -LogFile $LogFile -Message "Using minimal RESTORE FROM URL syntax for Azure SQL Managed Instance" -Type Info
                
                $restoreSQL = @"
RESTORE DATABASE [$DatabaseName] 
FROM URL = N'$bakUrl'
"@


            }
            else {
                # Traditional SQL Server - get file list and build MOVE options
                Write-StatusMessage "Reading backup file header..." -Type Info -Indent 4
                Write-LogMessage -LogFile $LogFile -Message "Reading backup file header" -Type Info
                
                $fileListCommand = $connection.CreateCommand()
                $fileListCommand.CommandText = "RESTORE FILELISTONLY FROM DISK = N'$BakSource'"
                $fileListCommand.CommandTimeout = $CommandTimeout
                
                $fileListAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($fileListCommand)
                $fileListTable = New-Object System.Data.DataTable
                $fileListAdapter.Fill($fileListTable) | Out-Null
                
                if ($fileListTable.Rows.Count -eq 0) {
                    $errorMessage = "Could not read file list from backup file"
                    Write-StatusMessage $errorMessage -Type Error -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                    return $false
                }

                # Build MOVE options for data and log files
                $moveOptions = @()
                foreach ($row in $fileListTable.Rows) {
                    $logicalName = $row["LogicalName"]
                    $fileType = $row["Type"]
                    
                    if ($fileType -eq "D") {
                        # Data file
                        if ($DataFileLocation) {
                            $newPath = Join-Path $DataFileLocation "$DatabaseName.mdf"
                        }
                        else {
                            # Use default SQL Server data directory
                            $newPath = "$DatabaseName.mdf"
                        }
                        $moveOptions += "MOVE N'$logicalName' TO N'$newPath'"
                    }
                    elseif ($fileType -eq "L") {
                        # Log file
                        if ($LogFileLocation) {
                            $newPath = Join-Path $LogFileLocation "$DatabaseName.ldf"
                        }
                        else {
                            # Use default SQL Server log directory
                            $newPath = "$DatabaseName.ldf"
                        }
                        $moveOptions += "MOVE N'$logicalName' TO N'$newPath'"
                    }
                }
                
                $moveClause = if ($moveOptions.Count -gt 0) { 
                    ($moveOptions -join ", ") + ", " 
                }
                else { 
                    "" 
                }

                # Build the complete RESTORE command for traditional SQL Server
                $replaceOption = if ($Replace) { "REPLACE, " } else { "" }
                $restoreSQL = @"
RESTORE DATABASE [$DatabaseName] 
FROM DISK = N'$BakSource' 
WITH $moveClause$replaceOption NOUNLOAD, STATS = 10
"@
            }

            Write-StatusMessage "Executing database restore..." -Type Info -Indent 4
            Write-LogMessage -LogFile $LogFile -Message "Executing SQL Restore Command: $restoreSQL" -Type Info

            # Create and execute the restore command
            $restoreCommand = $connection.CreateCommand()
            $restoreCommand.CommandText = $restoreSQL
            $restoreCommand.CommandTimeout = $CommandTimeout

            # Progress monitoring
            $spinChars = '|', '/', '-', '\'
            $spinIndex = 0
            $lastProgressTime = [DateTime]::Now
            $progressInterval = [TimeSpan]::FromSeconds(10)
            $lastPercentComplete = 0

            # Execute the restore command asynchronously
            $task = $restoreCommand.ExecuteNonQueryAsync()

            # Monitor the restore progress
            while (-not $task.IsCompleted) {
                $spinChar = $spinChars[$spinIndex]
                $spinIndex = ($spinIndex + 1) % $spinChars.Length
                $elapsedTime = $stopwatch.Elapsed
                $elapsedFormatted = "{0:hh\:mm\:ss}" -f $elapsedTime

                # For Azure SQL MI, we can't query progress the same way, so just show elapsed time
                if (([DateTime]::Now - $lastProgressTime) -ge $progressInterval) {
                    if (-not $isAzureManagedInstance) {
                        # Query the restore progress using a separate connection (only for traditional SQL Server)
                        try {
                            $progressConn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
                            $progressConn.Open()
                            $progressCmd = $progressConn.CreateCommand()
                            $progressCmd.CommandText = "SELECT r.percent_complete FROM sys.dm_exec_requests r WHERE r.session_id = @@SPID AND r.command LIKE 'RESTORE%'"
                            
                            $percentComplete = [int]($progressCmd.ExecuteScalar())
                            if ($percentComplete -gt 0 -and $percentComplete -ne $lastPercentComplete) {
                                $progressMsg = "Restore progress: $percentComplete% complete"
                                Write-StatusMessage $progressMsg -Type Info -Indent 4
                                Write-LogMessage -LogFile $LogFile -Message $progressMsg -Type Info
                                $lastPercentComplete = $percentComplete
                            }
                            $progressConn.Close()
                        }
                        catch {
                            # Ignore errors in progress reporting
                        }
                    }
                    else {
                        # For Azure SQL MI, just log elapsed time
                        Write-LogMessage -LogFile $LogFile -Message "Restore in progress... Elapsed: $elapsedFormatted" -Type Info
                    }
                    
                    $lastProgressTime = [DateTime]::Now
                }

                $serverType = if ($isAzureManagedInstance) { "Azure SQL MI" } else { "SQL Server" }
                Write-Host "`r      $spinChar Restoring database to $serverType as $Username... Time elapsed: $elapsedFormatted" -NoNewline
                Start-Sleep -Milliseconds 250
            }

            # Get the final result
            Write-Host "`r                                                                    " -NoNewline
            
            # Check if the restore completed successfully
            $stopwatch.Stop()
            $totalTime = $stopwatch.Elapsed
            $totalTimeFormatted = "{0:hh\:mm\:ss}" -f $totalTime
            $endTime = Get-Date

            if ($task.Status -eq 'RanToCompletion') {
                Write-StatusMessage "Database restore completed successfully! 🎉" -Type Success -Indent 3
                Write-StatusMessage "Database: $DatabaseName" -Type Success -Indent 4
                Write-StatusMessage "Server: $ServerFQDN" -Type Success -Indent 4
                Write-StatusMessage "User: $Username" -Type Success -Indent 4
                Write-StatusMessage "Total time: $totalTimeFormatted" -Type Success -Indent 4

                Write-LogMessage -LogFile $LogFile -Message "Database restore completed successfully!" -Type Success
                Write-LogMessage -LogFile $LogFile -Message "Database: $DatabaseName" -Type Success
                Write-LogMessage -LogFile $LogFile -Message "Server: $ServerFQDN" -Type Success
                Write-LogMessage -LogFile $LogFile -Message "User: $Username" -Type Success
                Write-LogMessage -LogFile $LogFile -Message "Total time: $totalTimeFormatted" -Type Success
                Write-LogMessage -LogFile $LogFile -Message "Started: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Type Success
                Write-LogMessage -LogFile $LogFile -Message "Completed: $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Type Success

                if ($fileSizeMB -gt 0 -and $totalTime.TotalSeconds -gt 0) {
                    $transferRateMBps = [math]::Round($fileSizeMB / $totalTime.TotalSeconds, 2)
                    $rateMessage = "Transfer rate: $transferRateMBps MB/sec"
                    Write-StatusMessage $rateMessage -Type Success -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message $rateMessage -Type Success
                }

                # Clean up the credential after successful restore
                if ($credentialName -and $isAzureManagedInstance) {
                    try {
                        Write-StatusMessage "Cleaning up SQL credential..." -Type Info -Indent 4
                        Write-LogMessage -LogFile $LogFile -Message "Cleaning up SQL credential: $credentialName" -Type Info
                        
                        $dropCredentialCommand = $connection.CreateCommand()
                        $dropCredentialCommand.CommandText = "DROP CREDENTIAL [$credentialName]"
                        $dropCredentialCommand.CommandTimeout = 30
                        $dropCredentialCommand.ExecuteNonQuery() | Out-Null
                        
                        Write-StatusMessage "SQL credential cleaned up successfully" -Type Success -Indent 4
                        Write-LogMessage -LogFile $LogFile -Message "SQL credential cleaned up successfully" -Type Success
                    }
                    catch {
                        $warningMessage = "Warning: Could not clean up SQL credential: $($_.Exception.Message)"
                        Write-StatusMessage $warningMessage -Type Warning -Indent 4
                        Write-LogMessage -LogFile $LogFile -Message $warningMessage -Type Warning
                    }
                }

                return $true
            }
            else {
                $errorMessage = "Restore task completed with status: $($task.Status)"
                if ($task.Exception) {
                    $errorMessage += " - Exception: $($task.Exception.Message)"
                    # Log inner exceptions for better debugging
                    if ($task.Exception.InnerException) {
                        $errorMessage += " - Inner Exception: $($task.Exception.InnerException.Message)"
                    }
                }
                Write-StatusMessage $errorMessage -Type Error -Indent 3
                Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                
                # Clean up the credential even on failure
                if ($credentialName -and $isAzureManagedInstance) {
                    try {
                        Write-StatusMessage "Cleaning up SQL credential after failure..." -Type Info -Indent 4
                        Write-LogMessage -LogFile $LogFile -Message "Cleaning up SQL credential after failure: $credentialName" -Type Info
                        
                        $dropCredentialCommand = $connection.CreateCommand()
                        $dropCredentialCommand.CommandText = "DROP CREDENTIAL [$credentialName]"
                        $dropCredentialCommand.CommandTimeout = 30
                        $dropCredentialCommand.ExecuteNonQuery() | Out-Null
                        
                        Write-LogMessage -LogFile $LogFile -Message "SQL credential cleaned up after failure" -Type Info
                    }
                    catch {
                        Write-LogMessage -LogFile $LogFile -Message "Could not clean up SQL credential after failure: $($_.Exception.Message)" -Type Warning
                    }
                }
                
                return $false
            }
        }
        catch {
            $errorMessage = "Error during SQL restore: $($_.Exception.Message)"
            Write-StatusMessage $errorMessage -Type Error -Indent 3
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            
            # Clean up the credential on exception
            if ($credentialName -and $isAzureManagedInstance -and $connection -and $connection.State -eq 'Open') {
                try {
                    Write-LogMessage -LogFile $LogFile -Message "Cleaning up SQL credential after exception: $credentialName" -Type Info
                    
                    $dropCredentialCommand = $connection.CreateCommand()
                    $dropCredentialCommand.CommandText = "DROP CREDENTIAL [$credentialName]"
                    $dropCredentialCommand.CommandTimeout = 30
                    $dropCredentialCommand.ExecuteNonQuery() | Out-Null
                    
                    Write-LogMessage -LogFile $LogFile -Message "SQL credential cleaned up after exception" -Type Info
                }
                catch {
                    Write-LogMessage -LogFile $LogFile -Message "Could not clean up SQL credential after exception: $($_.Exception.Message)" -Type Warning
                }
            }
            
            return $false
        }
        finally {
            # Close the connection
            if ($connection -and $connection.State -eq 'Open') {
                $connection.Close()
            }
        }
    }
    catch {
        $errorMessage = "Error restoring BAK file: $($_.Exception.Message)"
        Write-StatusMessage $errorMessage -Type Error -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
        return $false
    }
}

function Import-DatabaseOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Row,
        [Parameter(Mandatory = $true)]
        [string]$SqlPackagePath,
        [Parameter(Mandatory = $false)]
        [string]$LogFile,
        [Parameter(Mandatory = $false)]
        [datetime]$StartTime
    )
    
    $importStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Write-LogMessage -LogFile $LogFile -Message "Starting import database operation" -Type Action
        
        $deploymentType = if ([string]::IsNullOrEmpty($Row.Type)) { "AzurePaaS" } else { $Row.Type }
        $dstServerFQDN = Get-ServerFQDN -ServerName $Row.DST_server -DeploymentType $deploymentType
        
        # Find latest backup in storage
        $blobName = Find-LatestBackupBlob -StorageAccount $Row.Storage_Account `
            -ContainerName $Row.Storage_Container `
            -StorageKey $Row.Storage_Access_Key `
            -DatabaseName $Row.Database_Name `
            -LogFile $LogFile `
            -OperationId $Row.Operation_ID
            
        if (-not $blobName) {
            Write-StatusMessage "No backup file found in storage" -Type Error -Indent 2
            return $false
        }

        # Define local and remote paths. For IaaS, the final path is on the remote server.
        # For other types, it's the same as the local path.
        $localTempPath = Join-Path $env:TEMP $blobName
        $remoteBackupPath = Join-Path -Path $Row.Local_Folder -ChildPath $blobName
        $restoreSourcePath = if ($deploymentType -eq "AzureIaaS") { $remoteBackupPath } else { $localTempPath }

        # Always download to the local machine first
        $downloadSuccess = Download-BackupFromStorage -StorageAccount $Row.Storage_Account `
            -ContainerName $Row.Storage_Container `
            -StorageKey $Row.Storage_Access_Key `
            -BlobName $blobName `
            -LocalPath $localTempPath `
            -LogFile $LogFile
            
        if (-not $downloadSuccess) {
            Write-StatusMessage "Failed to download backup file from storage" -Type Error -Indent 2
            return $false
        }

        # If IaaS, copy the downloaded file to the destination server
        if ($deploymentType -eq "AzureIaaS") {
            $copySuccess = Copy-FileToRemote -ServerFQDN $dstServerFQDN `
                -LocalPath $localTempPath `
                -RemotePath $remoteBackupPath `
                -Username $Row.PS_User `
                -Password $Row.PS_Password `
                -LogFile $LogFile
            
            if (-not $copySuccess) {
                Write-StatusMessage "Failed to copy backup file to destination server" -Type Error -Indent 2
                # Clean up local temp file before exiting
                if (Test-Path $localTempPath) { Remove-Item $localTempPath -Force }
                return $false
            }
        }

        # Import based on deployment type
        $importSuccess = switch ($deploymentType) {
            "AzureMI" {
                Import-BacpacToSqlManagedInstance -BacpacSource $restoreSourcePath `
                    -ServerFQDN $dstServerFQDN `
                    -DatabaseName $Row.Database_Name `
                    -Username $Row.DST_SQL_Admin `
                    -Password $Row.DST_SQL_Password `
                    -SqlPackagePath $SqlPackagePath `
                    -LogFile $LogFile
            }
            "AzureIaaS" {
                Import-BakToSqlDatabase -BakSource $restoreSourcePath `
                    -ServerFQDN $dstServerFQDN `
                    -DatabaseName $Row.Database_Name `
                    -Username $Row.DST_SQL_Admin `
                    -Password $Row.DST_SQL_Password `
                    -LogFile $LogFile
            }
            default {
                Import-BacpacToSqlDatabase -BacpacSource $restoreSourcePath `
                    -ServerFQDN $dstServerFQDN `
                    -DatabaseName $Row.Database_Name `
                    -Username $Row.DST_SQL_Admin `
                    -Password $Row.DST_SQL_Password `
                    -SqlPackagePath $SqlPackagePath `
                    -LogFile $LogFile
            }
        }

        $importStopwatch.Stop()
        $importEndTime = Get-Date
        $importDuration = if ($PSBoundParameters.ContainsKey('StartTime')) { New-TimeSpan -Start $StartTime -End $importEndTime } else { $importStopwatch.Elapsed }
        $importDurationFormatted = "{0:hh\:mm\:ss}" -f $importDuration
        
        if ($importSuccess) {
            Write-StatusMessage "Import operation completed successfully in $importDurationFormatted" -Type Success -Indent 2
            Write-LogMessage -LogFile $LogFile -Message "Import operation duration: $importDurationFormatted" -Type Success
        }

        # Cleanup temp files
        if ([bool]::Parse($Row.Remove_Tempfile)) {
            # Clean up local temp file
            if (Test-Path $localTempPath) {
                Remove-Item $localTempPath -Force
                Write-OperationStatus "Cleaned up local temporary file." -Type Info -Indent 2 -LogFile $LogFile
            }

            # Clean up remote file for IaaS
            if ($deploymentType -eq "AzureIaaS") {
                Write-OperationStatus "Cleaning up remote file on $dstServerFQDN..." -Type Info -Indent 2 -LogFile $LogFile
                try {
                    $credential = New-Object System.Management.Automation.PSCredential($Row.PS_User, (ConvertTo-SecureString $Row.PS_Password -AsPlainText -Force))
                    $psSession = New-PSSession -ComputerName $dstServerFQDN -Credential $credential
                    Invoke-Command -Session $psSession -ScriptBlock { param($Path) Remove-Item -Path $Path -Force } -ArgumentList $remoteBackupPath
                    Remove-PSSession $psSession
                    Write-OperationStatus "Remote file cleaned up successfully." -Type Success -Indent 2 -LogFile $LogFile
                } 
                catch {
                    Write-OperationStatus "Warning: Could not clean up remote file: $_" -Type Warning -Indent 2 -LogFile $LogFile
                }
            }
        }

        return $importSuccess
    }
    catch {
        Write-StatusMessage "Error in import operation: $($_.Exception.Message)" -Type Error -Indent 2
        Write-LogMessage -LogFile $LogFile -Message "Error in import operation: $($_.Exception.Message)" -Type Error
        return $false
    }
    finally {
        $importStopwatch.Stop()
    }
}
