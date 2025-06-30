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
        $extension = [System.IO.Path]::GetExtension($originalFileName).ToLower()
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
        
        # Step 1: Export database to local file based on deployment type and file extension
        Write-StatusMessage "Exporting database to local $extension file..." -Type Action -Indent 2
        Write-LogMessage -LogFile $LogFile -Message "Starting export to local file: $localBackupPath" -Type Action
        
        $exportSuccess = $false

        switch ($deploymentType) {
            "AzurePaaS" {
                Write-StatusMessage "Using Azure SQL Database (PaaS) export method" -Type Info -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Using Azure SQL Database (PaaS) export method" -Type Info
                
                # PaaS only supports BACPAC
                if ($extension -ne ".bacpac") {
                    $errorMessage = "Azure SQL Database (PaaS) only supports BACPAC export. Invalid extension: $extension"
                    Write-StatusMessage $errorMessage -Type Error -Indent 3
                    Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                    return $false
                }
                
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

                # Use BACPAC export instead of BAK
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

            
            "AzureIaaS" {
                Write-StatusMessage "Using Azure SQL IaaS VM export method" -Type Info -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Using Azure SQL IaaS VM export method" -Type Info
                
                # Choose export method based on file extension
                if ($extension -eq ".bak") {
                    Write-StatusMessage "Exporting database to BAK file..." -Type Info -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message "Using BAK export format for Azure SQL IaaS VM" -Type Info
        
                    $exportSuccess = Export-SqlDatabaseToBak -ServerFQDN $srcServerFQDN `
                        -DatabaseName $Row.Database_Name `
                        -Username $Row.SRC_SQL_Admin `
                        -Password $Row.SRC_SQL_Password `
                        -OutputPath $localBackupPath `
                        -LogFile $LogFile `
                        -BackupType 'Full' `
                        -Compression 1
                }
                elseif ($extension -eq ".bacpac") {
                    Write-StatusMessage "Exporting database to BACPAC file..." -Type Info -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message "Using BACPAC export format for Azure SQL IaaS VM" -Type Info
        
                    $exportSuccess = Export-SqlDatabaseToBacpac -ServerFQDN $srcServerFQDN `
                        -DatabaseName $Row.Database_Name `
                        -Username $Row.SRC_SQL_Admin `
                        -Password $Row.SRC_SQL_Password `
                        -OutputPath $localBackupPath `
                        -SqlPackagePath $SqlPackagePath `
                        -LogFile $LogFile
                }
                else {
                    $errorMessage = "Unsupported file extension for export: $extension. Supported formats: .bak, .bacpac"
                    Write-StatusMessage $errorMessage -Type Error -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                    return $false
                }
            }
            
            default {
                # Default to AzurePaaS method for backward compatibility
                Write-StatusMessage "Unknown deployment type. Using default Azure SQL Database (PaaS) export method" -Type Warning -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Unknown deployment type. Using default Azure SQL Database (PaaS) export method" -Type Warning
                
                if ($extension -eq ".bacpac") {
                    $exportSuccess = Export-SqlDatabaseToBacpac -ServerFQDN $srcServerFQDN `
                        -DatabaseName $Row.Database_Name `
                        -Username $Row.SRC_SQL_Admin `
                        -Password $Row.SRC_SQL_Password `
                        -OutputPath $localBackupPath `
                        -SqlPackagePath $SqlPackagePath `
                        -LogFile $LogFile
                }
                else {
                    $errorMessage = "Default export method only supports BACPAC files. Invalid extension: $extension"
                    Write-StatusMessage $errorMessage -Type Error -Indent 3
                    Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                    return $false
                }
            }
        }
        
        if (-not $exportSuccess) {
            $errorMessage = "Failed to export database to local file"
            Write-StatusMessage $errorMessage -Type Error -Indent 2
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            return $false
        }
        
        # Step 2: Upload file to storage
        Write-StatusMessage "Uploading $extension file to Azure Storage..." -Type Action -Indent 2
        Write-LogMessage -LogFile $LogFile -Message "Starting upload to Azure Storage" -Type Action
        
        # Generate blob name with Operation ID and timestamp
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $blobName = "$($Row.Operation_ID)_$($Row.Database_Name)_$timestamp$extension"
        
        # Use the appropriate upload function based on file extension
        $uploadSuccess = $false
        if ($extension -eq ".bacpac") {
            $uploadSuccess = Upload-BacpacToStorage -FilePath $localBackupPath `
                -StorageAccount $Row.Storage_Account `
                -ContainerName $Row.Storage_Container `
                -StorageKey $Row.Storage_Access_Key `
                -BlobName $blobName `
                -LogFile $LogFile
        }
        elseif ($extension -eq ".bak") {
            $uploadUrl = Upload-BakToStorage -FilePath $localBackupPath `
                -StorageAccount $Row.Storage_Account `
                -ContainerName $Row.Storage_Container `
                -StorageKey $Row.Storage_Access_Key `
                -BlobName $blobName `
                -LogFile $LogFile
            
            $uploadSuccess = ($uploadUrl -ne $null)
        }
        
        if (-not $uploadSuccess) {
            $errorMessage = "Failed to upload $extension file to storage"
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
                $message = "Cleaned up local file"
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
            $message = "Local file preserved: $localBackupPath"
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
        [string]$LogFile,
        [switch]$FromStorageUrl = $false
    )

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $startTime = Get-Date

        $message = "Starting BACPAC import to '$DatabaseName' on '$ServerFQDN'..."
        Write-StatusMessage $message -Type Action -Indent 3
        Write-LogMessage -LogFile $LogFile -Message $message -Type Action

        # Get file size for progress context (only for local files)
        $fileSizeMB = 0
        if (-not $FromStorageUrl -and (Test-Path $BacpacSource)) {
            $fileInfo = Get-Item $BacpacSource
            $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
            $sizeMessage = "Import source size: $fileSizeMB MB"
            Write-StatusMessage $sizeMessage -Type Info -Indent 4
            Write-LogMessage -LogFile $LogFile -Message $sizeMessage -Type Info
        }
        elseif ($FromStorageUrl) {
            # Log URL (redact SAS token for security)
            $urlForLog = $BacpacSource
            if ($BacpacSource -match '\?') {
                $urlForLog = $BacpacSource.Substring(0, $BacpacSource.IndexOf('?')) + "?[SAS_TOKEN_REDACTED]"
            }
            $message = "Import source: Azure Storage URL ($urlForLog)"
            Write-StatusMessage $message -Type Info -Indent 4
            Write-LogMessage -LogFile $LogFile -Message $message -Type Info
        }

        # Build import arguments based on source type
        if ($FromStorageUrl) {
            $importArgs = @(
                "/action:Import"
                "/SourceFile:$BacpacSource"
                "/TargetServerName:$ServerFQDN"
                "/TargetDatabaseName:$DatabaseName"
                "/TargetUser:$Username"
                "/TargetPassword:$Password"
                "/p:CommandTimeout=3600"
            )
            
            Write-LogMessage -LogFile $LogFile -Message "Using direct import from Azure Storage URL" -Type Info
        }
        else {
            $importArgs = @(
                "/action:Import"
                "/SourceFile:$BacpacSource"
                "/TargetServerName:$ServerFQDN"
                "/TargetDatabaseName:$DatabaseName"
                "/TargetUser:$Username"
                "/TargetPassword:$Password"
                "/p:CommandTimeout=3600"
            )
            
            Write-LogMessage -LogFile $LogFile -Message "Using local file import" -Type Info
        }

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

            $sourceType = if ($FromStorageUrl) { "Azure Storage URL" } else { "local file" }
            Write-Host "`r      $spinChar Importing database from $sourceType as $Username... Time elapsed: $elapsedFormatted" -NoNewline
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

            if (-not $FromStorageUrl -and $fileSizeMB -gt 0 -and $totalTime.TotalSeconds -gt 0) {
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
        $connectionString = "Server=$ServerFQDN;Database=master;User Id=$Username;Password=$Password;Connection Timeout=30;Encrypt=True;TrustServerCertificate=False;"
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
                        
                        # First, ensure no active connections to the database
                        $killConnectionsCommand = $connection.CreateCommand()
                        $killConnectionsCommand.CommandText = @"
ALTER DATABASE [$DatabaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [$DatabaseName];
"@
                        $killConnectionsCommand.CommandTimeout = $CommandTimeout
                        
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
        
        $useDirectImport = $false
        $blobName = $null
        $fileExtension = $null
        $bacpacUrl = $null
        
        # Step 1: Check if backup file exists locally or needs to be accessed from storage
        if (-not (Test-Path $localBackupPath)) {
            Write-StatusMessage "Backup file not found locally, searching in Azure Storage..." -Type Action -Indent 2
            Write-LogMessage -LogFile $LogFile -Message "Backup file not found locally, searching in storage" -Type Info
            
            # For import-only operations, we need to find the backup file in storage
            $blobName = Find-LatestBackupBlob -StorageAccount $Row.Storage_Account `
                -ContainerName $Row.Storage_Container `
                -StorageKey $Row.Storage_Access_Key `
                -DatabaseName $Row.Database_Name `
                -LogFile $LogFile `
                -OperationId $Row.Operation_ID
            
            if (-not $blobName) {
                $errorMessage = "No backup file found in storage for database: $($Row.Database_Name)"
                Write-StatusMessage $errorMessage -Type Error -Indent 2
                Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                return $false
            }
            
            # Determine if we're dealing with a BACPAC or BAK file
            $fileExtension = [System.IO.Path]::GetExtension($blobName).ToLower()
            Write-StatusMessage "Found backup file: $blobName (Type: $fileExtension)" -Type Info -Indent 3
            Write-LogMessage -LogFile $LogFile -Message "Found backup file: $blobName (Type: $fileExtension)" -Type Info
            
            # For BACPAC files with Azure SQL Database (PaaS), we can use direct import
            if ($fileExtension -eq ".bacpac" -and $deploymentType -eq "AzurePaaS") {
                Write-StatusMessage "Will use direct import from Azure Storage for BACPAC file" -Type Info -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Will use direct import from Azure Storage for BACPAC file" -Type Info
                
                # Generate a SAS token with read permission that expires in a few hours
                $sasToken = New-SasTokenFromStorageKey -StorageAccount $Row.Storage_Account `
                    -StorageKey $Row.Storage_Access_Key `
                    -ContainerName $Row.Storage_Container `
                    -ExpiryTime (Get-Date).AddHours(4)
                    
                if (-not $sasToken) {
                    $errorMessage = "Failed to generate SAS token for storage access"
                    Write-StatusMessage $errorMessage -Type Error -Indent 3
                    Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                    return $false
                }
                
                # Construct the URL with SAS token
                $bacpacUrl = "https://$($Row.Storage_Account).blob.core.windows.net/$($Row.Storage_Container)/$blobName`?$sasToken"
                $useDirectImport = $true
                
                # Log URL (redact SAS token for security)
                $urlForLog = "https://$($Row.Storage_Account).blob.core.windows.net/$($Row.Storage_Container)/$blobName`?[SAS_TOKEN_REDACTED]"
                Write-LogMessage -LogFile $LogFile -Message "Direct import URL prepared: $urlForLog" -Type Info
            }
            else {
                # For other scenarios (BAK files or non-PaaS deployments), we need to download the file
                Write-StatusMessage "Will download backup file from Azure Storage first" -Type Info -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Will download backup file from Azure Storage first" -Type Info
                
                # Update local backup path to match the file extension
                $localBackupDir = Split-Path -Path $localBackupPath -Parent
                $localBackupFileName = [System.IO.Path]::GetFileNameWithoutExtension($localBackupPath) + $fileExtension
                $localBackupPath = Join-Path -Path $localBackupDir -ChildPath $localBackupFileName
                
                Write-StatusMessage "Updated local backup path: $localBackupPath" -Type Info -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Updated local backup path: $localBackupPath" -Type Info
                
                # Download the file (works for both BACPAC and BAK)
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
        }
        else {
            # File exists locally, determine file type
            $fileExtension = [System.IO.Path]::GetExtension($localBackupPath).ToLower()
            $message = "Using existing local backup file: $localBackupPath (Type: $fileExtension)"
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
                
                if ($fileExtension -eq ".bacpac") {
                    if ($useDirectImport -and $bacpacUrl) {
                        # Direct import from URL
                        Write-StatusMessage "Importing BACPAC directly from Azure Storage..." -Type Info -Indent 4
                        Write-LogMessage -LogFile $LogFile -Message "Using direct import from Azure Storage" -Type Info
                        
                        $importParams = @{
                            BacpacSource   = $bacpacUrl
                            ServerFQDN     = $dstServerFQDN
                            DatabaseName   = $Row.Database_Name
                            Username       = $Row.DST_SQL_Admin
                            Password       = $Row.DST_SQL_Password
                            SqlPackagePath = $SqlPackagePath
                            LogFile        = $LogFile
                            FromStorageUrl = $true
                        }
                        
                        $importSuccess = Import-BacpacToSqlDatabase @importParams
                    }
                    else {
                        # Traditional import from local file
                        Write-StatusMessage "Importing BACPAC from local file..." -Type Info -Indent 4
                        Write-LogMessage -LogFile $LogFile -Message "Using local file import" -Type Info
                        
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
                else {
                    $errorMessage = "Azure SQL Database (PaaS) only supports BACPAC files. Found: $fileExtension"
                    Write-StatusMessage $errorMessage -Type Error -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                    $importSuccess = $false
                }
            }
            
            "AzureMI" {
                Write-StatusMessage "Using Azure SQL Managed Instance import method" -Type Info -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Using Azure SQL Managed Instance import method" -Type Info

                if ($useDirectImport -and $bacpacUrl) {
                    # Direct import from URL
                    Write-StatusMessage "Importing BACPAC directly from Azure Storage..." -Type Info -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message "Using direct import from Azure Storage" -Type Info
        
                    $importParams = @{
                        BacpacSource   = $bacpacUrl
                        ServerFQDN     = $dstServerFQDN
                        DatabaseName   = $Row.Database_Name
                        Username       = $Row.DST_SQL_Admin
                        Password       = $Row.DST_SQL_Password
                        SqlPackagePath = $SqlPackagePath
                        LogFile        = $LogFile
                        FromStorageUrl = $true
                    }
        
                    $importSuccess = Import-BacpacToSqlDatabase @importParams
                }
                else {
                    # Traditional import from local file
                    Write-StatusMessage "Importing BACPAC from local file..." -Type Info -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message "Using local file import" -Type Info
        
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

            "AzureIaaS" {
                Write-StatusMessage "Using Azure SQL IaaS VM import method" -Type Info -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Using Azure SQL IaaS VM import method" -Type Info
                
                if ($fileExtension -eq ".bak") {
                    Write-StatusMessage "Importing BAK file to Azure SQL IaaS VM..." -Type Info -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message "Using BAK import method for Azure SQL IaaS VM" -Type Info
        
                    $importParams = @{
                        BakSource    = $localBackupPath
                        ServerFQDN   = $dstServerFQDN
                        DatabaseName = $Row.Database_Name
                        Username     = $Row.DST_SQL_Admin
                        Password     = $Row.DST_SQL_Password
                        LogFile      = $LogFile
                        Replace      = $true
                    }
        
                    # Add optional file location parameters if specified in the CSV
                    if ($Row.PSObject.Properties.Name -contains 'DataFileLocation' -and 
                        -not [string]::IsNullOrEmpty($Row.DataFileLocation)) {
                        $importParams['DataFileLocation'] = $Row.DataFileLocation
                        Write-LogMessage -LogFile $LogFile -Message "Using custom data file location: $($Row.DataFileLocation)" -Type Info
                    }
        
                    if ($Row.PSObject.Properties.Name -contains 'LogFileLocation' -and 
                        -not [string]::IsNullOrEmpty($Row.LogFileLocation)) {
                        $importParams['LogFileLocation'] = $Row.LogFileLocation
                        Write-LogMessage -LogFile $LogFile -Message "Using custom log file location: $($Row.LogFileLocation)" -Type Info
                    }
        
                    # For IaaS, we don't need storage parameters as it uses local file restore
                    $importSuccess = Import-BakToSqlDatabase @importParams
                }
                elseif ($fileExtension -eq ".bacpac") {
                    Write-StatusMessage "Importing BACPAC file to Azure SQL IaaS VM..." -Type Info -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message "Using BACPAC import method for Azure SQL IaaS VM" -Type Info
        
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
                    $errorMessage = "Unsupported file format for Azure SQL IaaS VM: $fileExtension. Supported formats: .bak, .bacpac"
                    Write-StatusMessage $errorMessage -Type Error -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                    $importSuccess = $false
                }
            }
            
            default {
                # Default to AzurePaaS method for backward compatibility
                Write-StatusMessage "Unknown deployment type '$deploymentType'. Using default Azure SQL Database (PaaS) import method" -Type Warning -Indent 3
                Write-LogMessage -LogFile $LogFile -Message "Unknown deployment type '$deploymentType'. Using default Azure SQL Database (PaaS) import method" -Type Warning
                
                if ($fileExtension -eq ".bacpac") {
                    if ($useDirectImport -and $bacpacUrl) {
                        # Direct import from URL
                        Write-StatusMessage "Importing BACPAC directly from Azure Storage..." -Type Info -Indent 4
                        Write-LogMessage -LogFile $LogFile -Message "Using direct import from Azure Storage" -Type Info
                        
                        $importParams = @{
                            BacpacSource   = $bacpacUrl
                            ServerFQDN     = $dstServerFQDN
                            DatabaseName   = $Row.Database_Name
                            Username       = $Row.DST_SQL_Admin
                            Password       = $Row.DST_SQL_Password
                            SqlPackagePath = $SqlPackagePath
                            LogFile        = $LogFile
                            FromStorageUrl = $true
                        }
                        
                        $importSuccess = Import-BacpacToSqlDatabase @importParams
                    }
                    else {
                        # Traditional import from local file
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
                else {
                    $errorMessage = "Default Azure SQL Database (PaaS) method only supports BACPAC files. Found: $fileExtension"
                    Write-StatusMessage $errorMessage -Type Error -Indent 4
                    Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
                    $importSuccess = $false
                }
            }
        }
        
        if (-not $importSuccess) {
            $errorMessage = "Failed to import backup file to destination database"
            Write-StatusMessage $errorMessage -Type Error -Indent 2
            Write-LogMessage -LogFile $LogFile -Message $errorMessage -Type Error
            return $false
        }
        
        # Step 3: Cleanup local file after successful import (based on Remove_Tempfile setting)
        # Only clean up if we actually downloaded the file (not for direct import)
        if (-not $useDirectImport -and (Test-Path $localBackupPath)) {
            $removeTempFile = $true  # Default to true for backward compatibility
            if ($Row.PSObject.Properties.Name -contains 'Remove_Tempfile') {
                $removeTempFile = [bool]::Parse($Row.Remove_Tempfile)
            }
            
            if ($removeTempFile) {
                try {
                    Remove-Item -Path $localBackupPath -Force
                    $message = "Cleaned up local backup file"
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
                $message = "Local backup file preserved: $localBackupPath"
                Write-StatusMessage $message -Type Info -Indent 2
                Write-LogMessage -LogFile $LogFile -Message $message -Type Info
            }
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
