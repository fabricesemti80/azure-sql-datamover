# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #
#                                                                                           Helper functions                                                                                           #
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #
function Upload-BacpacToStorage {
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
        $message = "Uploading BACPAC to storage..."
        Write-StatusMessage $message -Type Action -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $message -Type Action
        
        $storageContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $StorageKey
        
        $fileInfo = Get-Item $FilePath
        $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        
        $uploadMessage = "Uploading file: $BlobName (Size: $fileSizeMB MB)"
        Write-StatusMessage $uploadMessage -Type Info -Indent 4
        Write-LogMessage -LogFile $LogFile -Message $uploadMessage -Type Info
        
        $result = Set-AzStorageBlobContent -File $FilePath -Container $ContainerName -Blob $BlobName -Context $storageContext -Force
        
        if ($result) {
            $successMessage = "Upload completed successfully"
            Write-StatusMessage $successMessage -Type Success -Indent 4
            Write-LogMessage -LogFile $LogFile -Message $successMessage -Type Success
            
            $urlMessage = "Blob URL: $($result.ICloudBlob.Uri.AbsoluteUri)"
            Write-StatusMessage $urlMessage -Type Success -Indent 4
            Write-LogMessage -LogFile $LogFile -Message $urlMessage -Type Success
            return $true
        }
        else {
            $errorMessage = "Upload failed"
            Write-StatusMessage $errorMessage -Type Error -Indent 4
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            return $false
        }
    }
    catch {
        $errorMessage = "Error uploading to storage: $($_.Exception.Message)"
        Write-StatusMessage $errorMessage -Type Error -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
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
    
    Write-Host "$timestamp $indentation$prefix$Message" -ForegroundColor $colors[$Type]
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
        [string]$ServerName
    )
    
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
        $exportFields = @('SRC_server', 'SRC_SQL_Admin', 'SRC_SQL_Password', 'Local_Backup_File_Path')
        foreach ($field in $exportFields) {
            if ([string]::IsNullOrEmpty($Row.$field)) {
                $missingFields += $field
            }
        }
    }
    
    # Import-specific required fields
    if ($ImportAction) {
        $importFields = @('DST_server', 'DST_SQL_Admin', 'DST_SQL_Password')
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

function Test-SqlServerAccess {
    [CmdletBinding()]
    param(
        [string]$ServerFQDN,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password,
        [string]$Operation,
        [string]$LogFile
    )
    
    try {
        $message = "Testing $Operation SQL Server access: $ServerFQDN"
        Write-StatusMessage $message -Type Info -Indent 2
        Write-LogMessage -LogFile $LogFile -Message $message -Type Info
        
        # Use longer timeout for complex connections
        $timeout = 60
        $connectionString = "Server=$ServerFQDN;Database=master;User Id=$Username;Password=$Password;Connection Timeout=$timeout;Encrypt=True;TrustServerCertificate=False;"
        
        try {
            Add-Type -AssemblyName System.Data
            $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
            $connection.Open()
            
            # Test if we can access the specific database
            $command = $connection.CreateCommand()
            $command.CommandText = "SELECT name FROM sys.databases WHERE name = @dbname"
            $command.Parameters.AddWithValue("@dbname", $DatabaseName)
            $result = $command.ExecuteScalar()
            
            $connection.Close()
            
            $successMessage = "$Operation server '$ServerFQDN' is accessible"
            Write-StatusMessage $successMessage -Type Success -Indent 3
            Write-LogMessage -LogFile $LogFile -Message $successMessage -Type Success
            return $true
        }
        catch {
            $errorMessage = "Cannot connect to $Operation server '$ServerFQDN': $($_.Exception.Message)"
            Write-StatusMessage $errorMessage -Type Error -Indent 3
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            return $false
        }
    }
    catch {
        $errorMessage = "Error testing $Operation server access: $_"
        Write-StatusMessage $errorMessage -Type Error -Indent 2
        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
        return $false
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

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #
#                                                                                           Export functions                                                                                           #
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #

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
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $startTime = Get-Date
        
        $message = "Starting BACPAC export from '$DatabaseName' on '$ServerFQDN'..."
        Write-StatusMessage $message -Type Action -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $message -Type Action
        
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
        
        Write-LogMessage -LogFile $LogFile -Message "SqlPackage arguments: $($exportArgs -join ' ')" -Type Info
        
        $outputFile = [System.IO.Path]::GetTempFileName()
        $process = Start-Process -FilePath $SqlPackagePath -ArgumentList $exportArgs -NoNewWindow -PassThru -RedirectStandardOutput $outputFile -RedirectStandardError "$outputFile.err"
        
        # Progress monitoring
        $spinChars = '|', '/', '-', '\'
        $spinIndex = 0
        $lastProgressTime = [DateTime]::Now
        $progressInterval = [TimeSpan]::FromSeconds(10)
        
        while (-not $process.HasExited) {
            $spinChar = $spinChars[$spinIndex]
            $spinIndex = ($spinIndex + 1) % $spinChars.Length
            $elapsedTime = $stopwatch.Elapsed
            $elapsedFormatted = "{0:hh\:mm\:ss}" -f $elapsedTime
            
            # Log progress every 10 seconds
            if (([DateTime]::Now - $lastProgressTime) -ge $progressInterval) {
                Write-LogMessage -LogFile $LogFile -Message "Export in progress... Elapsed: $elapsedFormatted" -Type Info
                $lastProgressTime = [DateTime]::Now
            }
            
            Write-Host "`r      $spinChar Exporting database... Time elapsed: $elapsedFormatted" -NoNewline
            Start-Sleep -Milliseconds 250
        }
        
        Write-Host "`r                                                                    " -NoNewline
        $stopwatch.Stop()
        
        if ($process.ExitCode -eq 0) {
            $totalTime = $stopwatch.Elapsed
            $totalTimeFormatted = "{0:hh\:mm\:ss}" -f $totalTime
            $successMessage = "Export completed successfully in $totalTimeFormatted"
            Write-StatusMessage $successMessage -Type Success -Indent 3
            Write-LogMessage -LogFile $LogFile -Message $successMessage -Type Success
            
            if (Test-Path $OutputPath) {
                $fileInfo = Get-Item $OutputPath
                $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
                $sizeMessage = "BACPAC file size: $fileSizeMB MB"
                Write-StatusMessage $sizeMessage -Type Success -Indent 4
                Write-LogMessage -LogFile $LogFile -Message $sizeMessage -Type Success
            }
            
            return $true
        }
        else {
            $errorMessage = "Export failed with exit code $($process.ExitCode)"
            Write-StatusMessage $errorMessage -Type Error -Indent 3
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            
            if (Test-Path "$outputFile.err") {
                $errorContent = Get-Content "$outputFile.err"
                if ($errorContent) {
                    Write-StatusMessage "Error details:" -Type Error -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message "Error details:" -Type Error
                    $errorContent | ForEach-Object {
                        Write-StatusMessage "$_" -Type Error -Indent 5
                        Write-LogMessage -LogFile $LogFile -Message "$_" -Type Error
                    }
                }
            }
            return $false
        }
    }
    catch {
        $errorMessage = "Error during export: $($_.Exception.Message)"
        Write-StatusMessage $errorMessage -Type Error -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
        return $false
    }
    finally {
        # Cleanup
        try {
            if (Test-Path $outputFile -ErrorAction SilentlyContinue) { Remove-Item $outputFile -ErrorAction SilentlyContinue }
            if (Test-Path "$outputFile.err" -ErrorAction SilentlyContinue) { Remove-Item "$outputFile.err" -ErrorAction SilentlyContinue }
        }
        catch {}
    }
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
        $connectionString = "Server=$ServerFQDN;Database=master;User Id=$Username;Password=$Password;Connection Timeout=30;Encrypt=True;TrustServerCertificate=False;"
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
        [string]$LogFile
    )
    
    try {
        Write-LogMessage -LogFile $LogFile -Message "Starting export database operation" -Type Action
        
        $srcServerFQDN = Get-ServerFQDN -ServerName $Row.SRC_server

        # Get the deployment type - default to AzurePaaS if not specified
        $deploymentType = if ([string]::IsNullOrEmpty($Row.Type)) { "AzurePaaS" } else { $Row.Type }
        Write-StatusMessage "Deployment Type: $deploymentType" -Type Info -Indent 2
        Write-LogMessage -LogFile $LogFile -Message "Deployment Type: $deploymentType" -Type Info
        
        # Modify the local backup path to include Operation ID at the front
        $originalPath = $Row.Local_Backup_File_Path
        $directory = Split-Path -Path $originalPath -Parent
        $originalFileName = Split-Path -Path $originalPath -Leaf
        $extension = [System.IO.Path]::GetExtension($originalFileName)
        $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($originalFileName)
        
        # Check if the filename already starts with the Operation ID to avoid duplication
        if ($fileNameWithoutExt.StartsWith("$($Row.Operation_ID)_")) {
            $newFileName = "$fileNameWithoutExt$extension"
            Write-LogMessage -LogFile $LogFile -Message "Filename already contains Operation ID prefix, using as-is" -Type Info
        }
        else {
            # Create new filename with Operation ID at the front
            $newFileName = "$($Row.Operation_ID)_$fileNameWithoutExt$extension"
            Write-LogMessage -LogFile $LogFile -Message "Adding Operation ID prefix to filename" -Type Info
        }
        
        $localBackupPath = Join-Path -Path $directory -ChildPath $newFileName
        
        # Ensure local backup directory exists
        $backupDir = Split-Path -Path $localBackupPath -Parent
        if (-not (Test-Path $backupDir)) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
            $message = "Created backup directory: $backupDir"
            Write-StatusMessage $message -Type Info -Indent 2
            Write-LogMessage -LogFile $LogFile -Message $message -Type Info
        }
        
        # Log the modified path
        Write-LogMessage -LogFile $LogFile -Message "Modified local backup path: $localBackupPath" -Type Info
        
        # Step 1: Export database to local BACPAC file based on deployment type
        Write-StatusMessage "Exporting database to local BACPAC file..." -Type Action -Indent 2
        Write-LogMessage -LogFile $LogFile -Message "Starting BACPAC export to local file: $localBackupPath" -Type Action
        
        $exportSuccess = $false

        switch ($deploymentType) {
            "AzurePaaS" {
                Write-StatusMessage "Using Azure SQL Database (PaaS) export method" -Type Info -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Using Azure SQL Database (PaaS) export method" -Type Info
                
                $exportSuccess = Export-SqlDatabaseToBacpac -ServerFQDN $srcServerFQDN `
                    -DatabaseName $Row.Database_Name `
                    -Username $Row.SRC_SQL_Admin `
                    -Password $Row.SRC_SQL_Password `
                    -OutputPath $localBackupPath `
                    -SqlPackagePath $SqlPackagePath `
                    -LogFile $LogFile
            }
            
            "AzureMI" {
                Write-StatusMessage "Using Azure SQL Managed Instance export method" -Type Info -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Using Azure SQL Managed Instance export method" -Type Info
    
                if ($exportFormat -eq "BAK") {
                    Write-StatusMessage "Exporting database to BAK file..." -Type Info -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message "Using BAK export format for Azure SQL Managed Instance" -Type Info
        
                    $exportSuccess = Export-SqlDatabaseToBak -ServerFQDN $srcServerFQDN `
                        -DatabaseName $Row.Database_Name `
                        -Username $Row.SRC_SQL_Admin `
                        -Password $Row.SRC_SQL_Password `
                        -OutputPath $localBackupPath `
                        -LogFile $LogFile `
                        -BackupType 'Full' `
                        -Compression 1
                }
                else {
                    Write-StatusMessage "Exporting database to BACPAC file..." -Type Info -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message "Using BACPAC export format for Azure SQL Managed Instance" -Type Info
        
                    $exportSuccess = Export-SqlDatabaseToBacpac -ServerFQDN $srcServerFQDN `
                        -DatabaseName $Row.Database_Name `
                        -Username $Row.SRC_SQL_Admin `
                        -Password $Row.SRC_SQL_Password `
                        -OutputPath $localBackupPath `
                        -SqlPackagePath $SqlPackagePath `
                        -LogFile $LogFile
                }
            }

            
            "AzureIaaS" {
                Write-StatusMessage "Using Azure SQL IaaS VM export method" -Type Info -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Using Azure SQL IaaS VM export method" -Type Info
                
                # TODO: Implement IaaS-specific export method
                Write-StatusMessage "Azure SQL IaaS VM export not yet implemented" -Type Warning -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Azure SQL IaaS VM export not yet implemented" -Type Warning
                
                $exportSuccess = $false
            }
            
            default {
                # Default to AzurePaaS method for backward compatibility
                Write-StatusMessage "Unknown deployment type. Using default Azure SQL Database (PaaS) export method" -Type Warning -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Unknown deployment type. Using default Azure SQL Database (PaaS) export method" -Type Warning
                
                $exportSuccess = Export-SqlDatabaseToBacpac -ServerFQDN $srcServerFQDN `
                    -DatabaseName $Row.Database_Name `
                    -Username $Row.SRC_SQL_Admin `
                    -Password $Row.SRC_SQL_Password `
                    -OutputPath $localBackupPath `
                    -SqlPackagePath $SqlPackagePath `
                    -LogFile $LogFile
            }
        }
        
        if (-not $exportSuccess) {
            $errorMessage = "Failed to export database to local file"
            Write-StatusMessage $errorMessage -Type Error -Indent 2
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            return $false
        }
        
        # Step 2: Upload BACPAC file to storage
        Write-StatusMessage "Uploading BACPAC file to Azure Storage..." -Type Action -Indent 2
        Write-LogMessage -LogFile $LogFile -Message "Starting upload to Azure Storage" -Type Action
        
        # Generate blob name with Operation ID and timestamp
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $blobName = "$($Row.Operation_ID)_$($Row.Database_Name)_$timestamp.bacpac"
        
        $uploadSuccess = Upload-BacpacToStorage -FilePath $localBackupPath `
            -StorageAccount $Row.Storage_Account `
            -ContainerName $Row.Storage_Container `
            -StorageKey $Row.Storage_Access_Key `
            -BlobName $blobName `
            -LogFile $LogFile
        
        if (-not $uploadSuccess) {
            $errorMessage = "Failed to upload BACPAC file to storage"
            Write-StatusMessage $errorMessage -Type Error -Indent 2
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            return $false
        }
        
        # Cleanup local file after successful upload (based on Remove_Tempfile setting)
        $removeTempFile = $true  # Default to true for backward compatibility
        if ($Row.PSObject.Properties.Name -contains 'Remove_Tempfile') {
            $removeTempFile = [bool]::Parse($Row.Remove_Tempfile)
        }
        
        if ($removeTempFile) {
            try {
                Remove-Item -Path $localBackupPath -Force
                $message = "Cleaned up local BACPAC file"
                Write-StatusMessage $message -Type Info -Indent 2
                Write-LogMessage -LogFile $LogFile -Message $message -Type Info
            }
            catch {
                $warningMessage = "Warning: Could not clean up local file: $_"
                Write-StatusMessage $warningMessage -Type Warning -Indent 2
                Write-LogMessage -LogFile $LogFile -Message $warningMessage -Type Warning
            }
        }
        else {
            $message = "Local BACPAC file preserved: $localBackupPath"
            Write-StatusMessage $message -Type Info -Indent 2
            Write-LogMessage -LogFile $LogFile -Message $message -Type Info
        }
        
        $successMessage = "Export operation completed successfully"
        Write-StatusMessage $successMessage -Type Success -Indent 2
        Write-LogMessage -LogFile $LogFile -Message $successMessage -Type Success
        return $true
        
    }
    catch {
        $errorMessage = "Error in export operation: $($_.Exception.Message)"
        Write-StatusMessage $errorMessage -Type Error -Indent 2
        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
        return $false
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

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $startTime = Get-Date

        $message = "Starting BACPAC import to '$DatabaseName' on '$ServerFQDN'..."
        Write-StatusMessage $message -Type Action -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $message -Type Action

        # Get file size for progress context
        $fileSizeMB = 0
        if (Test-Path $BacpacSource) {
            $fileInfo = Get-Item $BacpacSource
            $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
            $sizeMessage = "Import source size: $fileSizeMB MB"
            Write-StatusMessage $sizeMessage -Type Info -Indent 4
            Write-LogMessage -LogFile $LogFile -Message $sizeMessage -Type Info
        }

        $importArgs = @(
            "/action:Import"
            "/sf:$BacpacSource"
            "/tsn:$ServerFQDN"
            "/tdn:$DatabaseName"
            "/tu:$Username"
            "/tp:$Password"
            "/p:CommandTimeout=3600"
        )

        Write-LogMessage -LogFile $LogFile -Message "SqlPackage import arguments: $($importArgs -join ' ')" -Type Info

        $outputFile = [System.IO.Path]::GetTempFileName()
        $process = Start-Process -FilePath $SqlPackagePath -ArgumentList $importArgs -NoNewWindow -PassThru -RedirectStandardOutput $outputFile -RedirectStandardError "$outputFile.err"

        # Progress monitoring
        $spinChars = '|', '/', '-', '\'
        $spinIndex = 0
        $lastProgressTime = [DateTime]::Now
        $progressInterval = [TimeSpan]::FromSeconds(10)

        while (-not $process.HasExited) {
            $spinChar = $spinChars[$spinIndex]
            $spinIndex = ($spinIndex + 1) % $spinChars.Length
            $elapsedTime = $stopwatch.Elapsed
            $elapsedFormatted = "{0:hh\:mm\:ss}" -f $elapsedTime

            if (([DateTime]::Now - $lastProgressTime) -ge $progressInterval) {
                Write-LogMessage -LogFile $LogFile -Message "Import in progress... Elapsed: $elapsedFormatted" -Type Info

                if (Test-Path $outputFile) {
                    $content = Get-Content $outputFile -Tail 1 | Where-Object { $_ -match '\S' }
                    if ($content) {
                        Write-LogMessage -LogFile $LogFile -Message "SqlPackage: $content" -Type Info
                    }
                }
                $lastProgressTime = [DateTime]::Now
            }

            Write-Host "`r      $spinChar Importing database as $Username... Time elapsed: $elapsedFormatted" -NoNewline
            Start-Sleep -Milliseconds 250
        }

        Write-Host "`r                                                                    " -NoNewline
        $stopwatch.Stop()

        if ($process.ExitCode -eq 0) {
            $totalTime = $stopwatch.Elapsed
            $totalTimeFormatted = "{0:hh\:mm\:ss}" -f $totalTime
            $endTime = Get-Date

            Write-StatusMessage "Import completed successfully! 🎉" -Type Success -Indent 3
            Write-StatusMessage "Database: $DatabaseName" -Type Success -Indent 4
            Write-StatusMessage "Server: $ServerFQDN" -Type Success -Indent 4
            Write-StatusMessage "User: $Username" -Type Success -Indent 4
            Write-StatusMessage "Total time: $totalTimeFormatted" -Type Success -Indent 4

            Write-LogMessage -LogFile $LogFile -Message "Import completed successfully!" -Type Success
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

            return $true
        }
        else {
            $errorMessage = "Import failed with exit code $($process.ExitCode)"
            Write-StatusMessage $errorMessage -Type Error -Indent 3
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error

            if (Test-Path "$outputFile.err") {
                $errorContent = Get-Content "$outputFile.err"
                if ($errorContent) {
                    Write-StatusMessage "Error details:" -Type Error -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message "Error details:" -Type Error
                    $errorContent | ForEach-Object {
                        Write-StatusMessage "$_" -Type Error -Indent 5
                        Write-LogMessage -LogFile $LogFile -Message "$_" -Type Error
                    }
                }
            }
            return $false
        }
    }
    catch {
        $errorMessage = "Error importing data: $($_.Exception.Message)"
        Write-StatusMessage $errorMessage -Type Error -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
        return $false
    }
    finally {
        try {
            if (Test-Path $outputFile -ErrorAction SilentlyContinue) { Remove-Item $outputFile -ErrorAction SilentlyContinue }
            if (Test-Path "$outputFile.err" -ErrorAction SilentlyContinue) { Remove-Item "$outputFile.err" -ErrorAction SilentlyContinue }
        }
        catch {}
    }
}

# Placeholder for future Managed Instance import method
function Import-BacpacToSqlManagedInstance {
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
    
    Write-StatusMessage "Azure SQL Managed Instance import not yet implemented" -Type Warning -Indent 3
    Write-LogMessage -LogFile $LogFile -Message "Azure SQL Managed Instance import not yet implemented" -Type Warning
    
    # TODO: Implement MI-specific import logic
    return $false
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
        if (Test-Path $BakSource) {
            $fileInfo = Get-Item $BakSource
            $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
            $sizeMessage = "Restore source size: $fileSizeMB MB"
            Write-StatusMessage $sizeMessage -Type Info -Indent 4
            Write-LogMessage -LogFile $LogFile -Message $sizeMessage -Type Info
        }
        else {
            $errorMessage = "BAK file not found: $BakSource"
            Write-StatusMessage $errorMessage -Type Error -Indent 4
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            return $false
        }

        # Check if this is Azure SQL Managed Instance (contains specific patterns in FQDN)
        $isAzureManagedInstance = $ServerFQDN -match "\.sql\.azuresynapse\.net$|\.database\.windows\.net$"
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
        $connectionString = "Server=$ServerFQDN;Database=master;User Id=$Username;Password=$Password;Connection Timeout=30;Encrypt=True;TrustServerCertificate=False;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        
        try {
            $connection.Open()
            Write-StatusMessage "Connected to SQL Server successfully" -Type Success -Indent 4
            Write-LogMessage -LogFile $LogFile -Message "Connected to SQL Server successfully" -Type Success

            # Build the RESTORE command based on whether we're using URL or local file
            $replaceOption = if ($Replace) { "REPLACE, " } else { "" }
            $restoreSQL = ""
            
            if ($bakUrl) {
                # Azure SQL Managed Instance - restore from URL
                Write-StatusMessage "Using RESTORE FROM URL for Azure SQL Managed Instance" -Type Info -Indent 4
                Write-LogMessage -LogFile $LogFile -Message "Using RESTORE FROM URL syntax" -Type Info
                
                $restoreSQL = @"
RESTORE DATABASE [$DatabaseName] 
FROM URL = N'$bakUrl' 
WITH $replaceOption NOUNLOAD, STATS = 10
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
            $progressInterval = [TimeSpan]::FromSeconds(5)
            $lastPercentComplete = 0

            # Execute the restore command asynchronously
            $task = $restoreCommand.ExecuteNonQueryAsync()

            # Monitor the restore progress
            while (-not $task.IsCompleted) {
                $spinChar = $spinChars[$spinIndex]
                $spinIndex = ($spinIndex + 1) % $spinChars.Length
                $elapsedTime = $stopwatch.Elapsed
                $elapsedFormatted = "{0:hh\:mm\:ss}" -f $elapsedTime

                # Check for progress every few seconds
                if (([DateTime]::Now - $lastProgressTime) -ge $progressInterval) {
                    # Query the restore progress using a separate connection
                    $progressConn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
                    $progressConn.Open()
                    $progressCmd = $progressConn.CreateCommand()
                    $progressCmd.CommandText = "SELECT r.percent_complete FROM sys.dm_exec_requests r WHERE r.session_id = @@SPID AND r.command LIKE 'RESTORE%'"
                    
                    try {
                        $percentComplete = [int]($progressCmd.ExecuteScalar())
                        if ($percentComplete -gt 0 -and $percentComplete -ne $lastPercentComplete) {
                            $progressMsg = "Restore progress: $percentComplete% complete"
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

                Write-Host "`r      $spinChar Restoring database as $Username... Time elapsed: $elapsedFormatted" -NoNewline
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

                return $true
            }
            else {
                $errorMessage = "Restore task completed with status: $($task.Status)"
                if ($task.Exception) {
                    $errorMessage += " - Exception: $($task.Exception.Message)"
                }
                Write-StatusMessage $errorMessage -Type Error -Indent 3
                Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                return $false
            }
        }
        catch {
            $errorMessage = "Error during SQL restore: $($_.Exception.Message)"
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
        $errorMessage = "Error restoring BAK file: $($_.Exception.Message)"
        Write-StatusMessage $errorMessage -Type Error -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
        return $false
    }
}

# Update the Import-DatabaseOperation function to use the new generic functions
function Import-DatabaseOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Row,
        
        [Parameter(Mandatory = $true)]
        [string]$SqlPackagePath,
        
        [Parameter(Mandatory = $false)]
        [string]$LogFile
    )
    
    try {
        Write-LogMessage -LogFile $LogFile -Message "Starting import database operation" -Type Action
        
        $dstServerFQDN = Get-ServerFQDN -ServerName $Row.DST_server
        $localBackupPath = $Row.Local_Backup_File_Path

        # Get the deployment type - default to AzurePaaS if not specified
        $deploymentType = if ([string]::IsNullOrEmpty($Row.Type)) { "AzurePaaS" } else { $Row.Type }
        Write-StatusMessage "Deployment Type: $deploymentType" -Type Info -Indent 2
        Write-LogMessage -LogFile $LogFile -Message "Deployment Type: $deploymentType" -Type Info
        
        # Step 1: Download backup file from storage (if not already local)
        if (-not (Test-Path $localBackupPath)) {
            Write-StatusMessage "Backup file not found locally, downloading from storage..." -Type Action -Indent 2
            Write-LogMessage -LogFile $LogFile -Message "Backup file not found locally, searching in storage" -Type Info
            
            # Determine which file extensions to search for based on deployment type
            $searchExtensions = switch ($deploymentType) {
                "AzureMI" { @("bak", "bacpac") }  # Prefer BAK for MI, but allow BACPAC
                "AzurePaaS" { @("bacpac") }       # Only BACPAC for PaaS
                "AzureIaaS" { @("bak", "bacpac") } # Both for IaaS
                default { @("bacpac", "bak") }    # Default to both
            }
            
            # For import-only operations, we need to find the backup file in storage
            $blobName = Find-LatestBackupBlob -StorageAccount $Row.Storage_Account `
                -ContainerName $Row.Storage_Container `
                -StorageKey $Row.Storage_Access_Key `
                -DatabaseName $Row.Database_Name `
                -LogFile $LogFile `
                -FileExtensions $searchExtensions
            
            if (-not $blobName) {
                $errorMessage = "No backup file found in storage for database: $($Row.Database_Name)"
                Write-StatusMessage $errorMessage -Type Error -Indent 2
                Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                return $false
            }
            
            # Update the local backup path to match the found file extension
            $foundExtension = [System.IO.Path]::GetExtension($blobName)
            $localBackupPath = [System.IO.Path]::ChangeExtension($localBackupPath, $foundExtension)
            
            $downloadSuccess = Download-BackupFromStorage -StorageAccount $Row.Storage_Account `
                -ContainerName $Row.Storage_Container `
                -StorageKey $Row.Storage_Access_Key `
                -BlobName $blobName `
                -LocalPath $localBackupPath `
                -LogFile $LogFile
            
            if (-not $downloadSuccess) {
                $errorMessage = "Failed to download backup file from storage"
                Write-StatusMessage $errorMessage -Type Error -Indent 2
                Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                return $false
            }
        }
        else {
            $message = "Using existing local backup file: $localBackupPath"
            Write-StatusMessage $message -Type Info -Indent 2
            Write-LogMessage -LogFile $LogFile -Message $message -Type Info
        }
        
        # Step 2: Import backup file to destination database based on deployment type
        Write-StatusMessage "Importing backup file to destination database..." -Type Action -Indent 2
        Write-LogMessage -LogFile $LogFile -Message "Starting backup import to destination database" -Type Action
        
        $importSuccess = $false

        switch ($deploymentType) {
            "AzurePaaS" {
                Write-StatusMessage "Using Azure SQL Database (PaaS) import method" -Type Info -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Using Azure SQL Database (PaaS) import method" -Type Info
                
                $importParams = @{
                    BacpacSource   = $localBackupPath
                    ServerFQDN     = $dstServerFQDN
                    DatabaseName   = $Row.Database_Name
                    Username       = $Row.DST_SQL_Admin
                    Password       = $Row.DST_SQL_Password
                    SqlPackagePath = $SqlPackagePath
                    LogFile        = $LogFile
                }
                
                $importSuccess = Import-BacpacToSqlDatabase @importParams
            }
            
            "AzureMI" {
                Write-StatusMessage "Using Azure SQL Managed Instance import method" -Type Info -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Using Azure SQL Managed Instance import method" -Type Info
    
                # Check if the file is a BAK file (preferred for Managed Instance) or BACPAC
                $fileExtension = [System.IO.Path]::GetExtension($localBackupPath).ToLower()
    
                if ($fileExtension -eq ".bak") {
                    Write-StatusMessage "Importing BAK file to Azure SQL Managed Instance..." -Type Info -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message "Using BAK import method for Azure SQL Managed Instance" -Type Info
        
                    $importParams = @{
                        BakSource        = $localBackupPath
                        ServerFQDN       = $dstServerFQDN
                        DatabaseName     = $Row.Database_Name
                        Username         = $Row.DST_SQL_Admin
                        Password         = $Row.DST_SQL_Password
                        LogFile          = $LogFile
                        Replace          = $true
                        # Add storage parameters for Azure MI
                        StorageAccount   = $Row.Storage_Account
                        StorageContainer = $Row.Storage_Container
                        StorageKey       = $Row.Storage_Access_Key
                    }
        
                    # Add optional file location parameters if specified in the CSV
                    if (-not [string]::IsNullOrEmpty($Row.PSObject.Properties['DataFileLocation']) -and 
                        -not [string]::IsNullOrEmpty($Row.DataFileLocation)) {
                        $importParams['DataFileLocation'] = $Row.DataFileLocation
                    }
        
                    if (-not [string]::IsNullOrEmpty($Row.PSObject.Properties['LogFileLocation']) -and 
                        -not [string]::IsNullOrEmpty($Row.LogFileLocation)) {
                        $importParams['LogFileLocation'] = $Row.LogFileLocation
                    }
        
                    $importSuccess = Import-BakToSqlDatabase @importParams
                }
                elseif ($fileExtension -eq ".bacpac") {
                    Write-StatusMessage "Importing BACPAC file to Azure SQL Managed Instance..." -Type Info -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message "Using BACPAC import method for Azure SQL Managed Instance" -Type Info
        
                    $importParams = @{
                        BacpacSource   = $localBackupPath
                        ServerFQDN     = $dstServerFQDN
                        DatabaseName   = $Row.Database_Name
                        Username       = $Row.DST_SQL_Admin
                        Password       = $Row.DST_SQL_Password
                        SqlPackagePath = $SqlPackagePath
                        LogFile        = $LogFile
                    }
        
                    $importSuccess = Import-BacpacToSqlDatabase @importParams
                }
                else {
                    $errorMessage = "Unsupported file format for Azure SQL Managed Instance: $fileExtension. Supported formats: .bak, .bacpac"
                    Write-StatusMessage $errorMessage -Type Error -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                    $importSuccess = $false
                }
            }
            
            "AzureIaaS" {
                Write-StatusMessage "Using Azure SQL IaaS VM import method" -Type Info -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Using Azure SQL IaaS VM import method" -Type Info
                
                # Call future function for IaaS import
                Write-StatusMessage "Azure SQL IaaS VM import not yet implemented" -Type Warning -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Azure SQL IaaS VM import not yet implemented" -Type Warning
                
                # TODO: Call Import-BacpacToSqlIaaS when implemented
                $importSuccess = $false
            }
            
            default {
                # Default to AzurePaaS method for backward compatibility
                Write-StatusMessage "Unknown deployment type. Using default Azure SQL Database (PaaS) import method" -Type Warning -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Unknown deployment type. Using default Azure SQL Database (PaaS) import method" -Type Warning
                
                $importParams = @{
                    BacpacSource   = $localBackupPath
                    ServerFQDN     = $dstServerFQDN
                    DatabaseName   = $Row.Database_Name
                    Username       = $Row.DST_SQL_Admin
                    Password       = $Row.DST_SQL_Password
                    SqlPackagePath = $SqlPackagePath
                    LogFile        = $LogFile
                }
                
                $importSuccess = Import-BacpacToSqlDatabase @importParams
            }
        }
        
        if (-not $importSuccess) {
            $errorMessage = "Failed to import backup file to destination database"
            Write-StatusMessage $errorMessage -Type Error -Indent 2
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            return $false
        }
        
        $successMessage = "Import operation completed successfully"
        Write-StatusMessage $successMessage -Type Success -Indent 2
        Write-LogMessage -LogFile $LogFile -Message $successMessage -Type Success
        return $true
        
    }
    catch {
        $errorMessage = "Error in import operation: $($_.Exception.Message)"
        Write-StatusMessage $errorMessage -Type Error -Indent 2
        Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
        return $false
    }
}
