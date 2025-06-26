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

function Get-ServerFQDN {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName
    )
    
    # If already contains .database.windows.net, return as-is
    if ($ServerName -like "*.database.windows.net") {
        return $ServerName
    }
    
    # Otherwise append .database.windows.net
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
        } else {
            Write-StatusMessage "$module module is available" -Type Success
        }
    }

    # Check sqlpackage.exe
    try {
        $null = Get-Command $SqlPackagePath -ErrorAction Stop
        Write-StatusMessage "SqlPackage.exe found at: $SqlPackagePath" -Type Success
    } catch {
        Write-StatusMessage "sqlpackage.exe not found at path: $SqlPackagePath. Please ensure SQL Server Data Tools (SSDT) is installed or specify the correct path." -Type Error
        $success = $false
    }

    # Check CSV file
    if (-not (Test-Path $CsvPath)) {
        Write-StatusMessage "CSV file not found at path: $CsvPath" -Type Error
        $success = $false
    } else {
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
        [bool]$ImportAction
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
        Write-StatusMessage "Missing required fields: $($missingFields -join ', ')" -Type Error
        return $false
    }
    
    return $true
}

function Test-DiskSpace {
    [CmdletBinding()]
    param(
        [string]$Path,
        [long]$RequiredSpaceGB
    )
    
    try {
        # Ensure directory exists
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            Write-StatusMessage "Created directory: $Path" -Type Info -Indent 2
        }
        
        $drive = Split-Path -Path $Path -Qualifier
        if (-not $drive) {
            $drive = (Get-Location).Drive.Name + ":"
        }
        
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$drive'"
        $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        
        Write-StatusMessage "Available space on $drive $freeSpaceGB GB, Required: $RequiredSpaceGB GB" -Type Info -Indent 2
        
        if ($freeSpaceGB -lt $RequiredSpaceGB) {
            Write-StatusMessage "Insufficient disk space. Available: $freeSpaceGB GB, Required: $RequiredSpaceGB GB" -Type Error
            return $false
        }
        
        return $true
    } catch {
        Write-StatusMessage "Error checking disk space: $_" -Type Warning
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
        [string]$Operation
    )
    
    try {
        Write-StatusMessage "Testing $Operation SQL Server access: $ServerFQDN" -Type Info -Indent 2
        
        # Create a simple connection test using sqlcmd if available, otherwise assume accessible
        # For now, we'll do a basic connectivity test
        $connectionString = "Server=$ServerFQDN;Database=$DatabaseName;User Id=$Username;Password=$Password;Connection Timeout=30;"
        
        # Test with a simple SQL connection
        try {
            Add-Type -AssemblyName System.Data
            $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
            $connection.Open()
            $connection.Close()
            Write-StatusMessage "$Operation server '$ServerFQDN' is accessible" -Type Success -Indent 3
            return $true
        } catch {
            Write-StatusMessage "Cannot connect to $Operation server '$ServerFQDN': $($_.Exception.Message)" -Type Error -Indent 3
            return $false
        }
    } catch {
        Write-StatusMessage "Error testing $Operation server access: $_" -Type Error -Indent 2
        return $false
    }
}

function Test-StorageAccess {
    [CmdletBinding()]
    param(
        [string]$StorageAccount,
        [string]$StorageContainer,
        [string]$StorageKey
    )
    
    try {
        Write-StatusMessage "Testing storage account access: $StorageAccount" -Type Info -Indent 2
        
        $storageContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $StorageKey -ErrorAction Stop
        
        # Test container access
        $container = Get-AzStorageContainer -Name $StorageContainer -Context $storageContext -ErrorAction Stop
        Write-StatusMessage "Storage container '$StorageContainer' is accessible" -Type Success -Indent 3
        
        return $true
    } catch {
        Write-StatusMessage "Cannot access storage account/container: $($_.Exception.Message)" -Type Error -Indent 2
        return $false
    }
}

function Export-DatabaseOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Row,
        
        [Parameter(Mandatory = $true)]
        [string]$SqlPackagePath
    )
    
    try {
        $srcServerFQDN = Get-ServerFQDN -ServerName $Row.SRC_server
        $localBackupPath = $Row.Local_Backup_File_Path
        
        # Ensure local backup directory exists
        $backupDir = Split-Path -Path $localBackupPath -Parent
        if (-not (Test-Path $backupDir)) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
            Write-StatusMessage "Created backup directory: $backupDir" -Type Info -Indent 2
        }
        
        # Step 1: Export database to local BACPAC file
        Write-StatusMessage "Exporting database to local BACPAC file..." -Type Action -Indent 2
        
        $exportSuccess = Export-SqlDatabaseToBacpac -ServerFQDN $srcServerFQDN `
            -DatabaseName $Row.Database_Name `
            -Username $Row.SRC_SQL_Admin `
            -Password $Row.SRC_SQL_Password `
            -OutputPath $localBackupPath `
            -SqlPackagePath $SqlPackagePath
        
        if (-not $exportSuccess) {
            Write-StatusMessage "Failed to export database to local file" -Type Error -Indent 2
            return $false
        }
        
        # Step 2: Upload BACPAC file to storage
        Write-StatusMessage "Uploading BACPAC file to Azure Storage..." -Type Action -Indent 2
        
        # Generate blob name with timestamp
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $blobName = "$($Row.Database_Name)_$timestamp.bacpac"
        
        $uploadSuccess = Upload-BacpacToStorage -FilePath $localBackupPath `
            -StorageAccount $Row.Storage_Account `
            -ContainerName $Row.Storage_Container `
            -StorageKey $Row.Storage_Access_Key `
            -BlobName $blobName
        
        if (-not $uploadSuccess) {
            Write-StatusMessage "Failed to upload BACPAC file to storage" -Type Error -Indent 2
            return $false
        }
        
        # Cleanup local file after successful upload
        try {
            Remove-Item -Path $localBackupPath -Force
            Write-StatusMessage "Cleaned up local BACPAC file" -Type Info -Indent 2
        } catch {
            Write-StatusMessage "Warning: Could not clean up local file: $_" -Type Warning -Indent 2
        }
        
        Write-StatusMessage "Export operation completed successfully" -Type Success -Indent 2
        return $true
        
    } catch {
        Write-StatusMessage "Error in export operation: $($_.Exception.Message)" -Type Error -Indent 2
        return $false
    }
}

function Import-DatabaseOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Row,
        
        [Parameter(Mandatory = $true)]
        [string]$SqlPackagePath
    )
    
    try {
        $dstServerFQDN = Get-ServerFQDN -ServerName $Row.DST_server
        $localBackupPath = $Row.Local_Backup_File_Path
        
        # Step 1: Download BACPAC file from storage (if not already local)
        if (-not (Test-Path $localBackupPath)) {
            Write-StatusMessage "BACPAC file not found locally, downloading from storage..." -Type Action -Indent 2
            
            # For import-only operations, we need to find the BACPAC file in storage
            # We'll use the database name to search for the most recent backup
            $blobName = Find-LatestBacpacBlob -StorageAccount $Row.Storage_Account `
                -ContainerName $Row.Storage_Container `
                -StorageKey $Row.Storage_Access_Key `
                -DatabaseName $Row.Database_Name
            
            if (-not $blobName) {
                Write-StatusMessage "No BACPAC file found in storage for database: $($Row.Database_Name)" -Type Error -Indent 2
                return $false
            }
            
            $downloadSuccess = Download-BacpacFromStorage -StorageAccount $Row.Storage_Account `
                -ContainerName $Row.Storage_Container `
                -StorageKey $Row.Storage_Access_Key `
                -BlobName $blobName `
                -LocalPath $localBackupPath
            
            if (-not $downloadSuccess) {
                Write-StatusMessage "Failed to download BACPAC file from storage" -Type Error -Indent 2
                return $false
            }
        } else {
            Write-StatusMessage "Using existing local BACPAC file: $localBackupPath" -Type Info -Indent 2
        }
        
        # Step 2: Import BACPAC file to destination database
        Write-StatusMessage "Importing BACPAC file to destination database..." -Type Action -Indent 2
        
        $importSuccess = Import-BacpacToSqlDatabase -BacpacSource $localBackupPath `
            -ServerFQDN $dstServerFQDN `
            -DatabaseName $Row.Database_Name `
            -Username $Row.DST_SQL_Admin `
            -Password $Row.DST_SQL_Password `
            -SqlPackagePath $SqlPackagePath
        
        if (-not $importSuccess) {
            Write-StatusMessage "Failed to import BACPAC file to destination database" -Type Error -Indent 2
            return $false
        }
        
        Write-StatusMessage "Import operation completed successfully" -Type Success -Indent 2
        return $true
        
    } catch {
        Write-StatusMessage "Error in import operation: $($_.Exception.Message)" -Type Error -Indent 2
        return $false
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
        [string]$SqlPackagePath
    )
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $startTime = Get-Date
        
        Write-StatusMessage "Starting BACPAC export from '$DatabaseName' on '$ServerFQDN'..." -Type Action -Indent 3
        
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
        
        $outputFile = [System.IO.Path]::GetTempFileName()
        $process = Start-Process -FilePath $SqlPackagePath -ArgumentList $exportArgs -NoNewWindow -PassThru -RedirectStandardOutput $outputFile -RedirectStandardError "$outputFile.err"
        
        # Progress monitoring
        $spinChars = '|', '/', '-', '\'
        $spinIndex = 0
        
        while (-not $process.HasExited) {
            $spinChar = $spinChars[$spinIndex]
            $spinIndex = ($spinIndex + 1) % $spinChars.Length
            $elapsedTime = $stopwatch.Elapsed
            $elapsedFormatted = "{0:hh\:mm\:ss}" -f $elapsedTime
            
            Write-Host "`r      $spinChar Exporting database... Time elapsed: $elapsedFormatted" -NoNewline
            Start-Sleep -Milliseconds 250
        }
        
        Write-Host "`r                                                                    " -NoNewline
        $stopwatch.Stop()
        
        if ($process.ExitCode -eq 0) {
            $totalTime = $stopwatch.Elapsed
            $totalTimeFormatted = "{0:hh\:mm\:ss}" -f $totalTime
            Write-StatusMessage "Export completed successfully in $totalTimeFormatted" -Type Success -Indent 3
            
            if (Test-Path $OutputPath) {
                $fileInfo = Get-Item $OutputPath
                $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
                Write-StatusMessage "BACPAC file size: $fileSizeMB MB" -Type Success -Indent 4
            }
            
            return $true
        } else {
            Write-StatusMessage "Export failed with exit code $($process.ExitCode)" -Type Error -Indent 3
            
            if (Test-Path "$outputFile.err") {
                $errorContent = Get-Content "$outputFile.err"
                if ($errorContent) {
                    Write-StatusMessage "Error details:" -Type Error -Indent 4
                    $errorContent | ForEach-Object {
                        Write-StatusMessage "$_" -Type Error -Indent 5
                    }
                }
            }
            return $false
        }
    } catch {
        Write-StatusMessage "Error during export: $($_.Exception.Message)" -Type Error -Indent 3
        return $false
    } finally {
        # Cleanup
        try {
            if (Test-Path $outputFile -ErrorAction SilentlyContinue) { Remove-Item $outputFile -ErrorAction SilentlyContinue }
            if (Test-Path "$outputFile.err" -ErrorAction SilentlyContinue) { Remove-Item "$outputFile.err" -ErrorAction SilentlyContinue }
        } catch {}
    }
}

function Import-BacpacToSqlDatabase {
    [CmdletBinding()]
    param(
        [string]$BacpacSource,
        [string]$ServerFQDN,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password,
        [string]$SqlPackagePath
    )
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $startTime = Get-Date
        
        Write-StatusMessage "Starting BACPAC import to '$DatabaseName' on '$ServerFQDN'..." -Type Action -Indent 3
        
        # Get file size for progress context
        $fileSizeMB = 0
        if (Test-Path $BacpacSource) {
            $fileInfo = Get-Item $BacpacSource
            $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
            Write-StatusMessage "Import source size: $fileSizeMB MB" -Type Info -Indent 4
        }
        
        $importArgs = @(
            "/action:import"
            "/sf:$BacpacSource"
            "/tsn:$ServerFQDN"
            "/tdn:$DatabaseName"
            "/tu:$Username"
            "/tp:$Password"
            "/p:CommandTimeout=0"
        )
        
        $outputFile = [System.IO.Path]::GetTempFileName()
        $process = Start-Process -FilePath $SqlPackagePath -ArgumentList $importArgs -NoNewWindow -PassThru -RedirectStandardOutput $outputFile -RedirectStandardError "$outputFile.err"
        
        # Progress monitoring
        $spinChars = '|', '/', '-', '\'
        $spinIndex = 0
        $lastProgressTime = [DateTime]::Now
        $progressInterval = [TimeSpan]::FromSeconds(5)
        
        while (-not $process.HasExited) {
            $spinChar = $spinChars[$spinIndex]
            $spinIndex = ($spinIndex + 1) % $spinChars.Length
            $elapsedTime = $stopwatch.Elapsed
            $elapsedFormatted = "{0:hh\:mm\:ss}" -f $elapsedTime
            
            # Show progress updates every 5 seconds
            if (([DateTime]::Now - $lastProgressTime) -ge $progressInterval) {
                if (Test-Path $outputFile) {
                    $content = Get-Content $outputFile -Tail 1 | Where-Object { $_ -match '\S' }
                    if ($content) {
                        Write-StatusMessage "$content" -Type Action -Indent 4
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
            Write-StatusMessage "Import completed successfully! 🎉" -Type Success -Indent 3
            Write-StatusMessage "Database: $DatabaseName" -Type Success -Indent 4
            Write-StatusMessage "Server: $ServerFQDN" -Type Success -Indent 4
            Write-StatusMessage "User: $Username" -Type Success -Indent 4
            Write-StatusMessage "Total time: $totalTimeFormatted" -Type Success -Indent 4
            Write-StatusMessage "Started: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Type Success -Indent 4
            Write-StatusMessage "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Type Success -Indent 4
            
            if ($fileSizeMB -gt 0 -and $totalTime.TotalSeconds -gt 0) {
                $transferRateMBps = [math]::Round($fileSizeMB / $totalTime.TotalSeconds, 2)
                Write-StatusMessage "Transfer rate: $transferRateMBps MB/sec" -Type Success -Indent 4
            }
            
            return $true
        } else {
            Write-StatusMessage "Import failed with exit code $($process.ExitCode)" -Type Error -Indent 3
            
            if (Test-Path "$outputFile.err") {
                $errorContent = Get-Content "$outputFile.err"
                if ($errorContent) {
                    Write-StatusMessage "Error details:" -Type Error -Indent 4
                    $errorContent | ForEach-Object {
                        Write-StatusMessage "$_" -Type Error -Indent 5
                    }
                }
            }
            return $false
        }
    } catch {
        Write-StatusMessage "Error importing data: $($_.Exception.Message)" -Type Error -Indent 3
        return $false
    } finally {
        # Cleanup
        try {
            if (Test-Path $outputFile -ErrorAction SilentlyContinue) { Remove-Item $outputFile -ErrorAction SilentlyContinue }
            if (Test-Path "$outputFile.err" -ErrorAction SilentlyContinue) { Remove-Item "$outputFile.err" -ErrorAction SilentlyContinue }
        } catch {}
    }
}

function Upload-BacpacToStorage {
    [CmdletBinding()]
    param(
        [string]$FilePath,
        [string]$StorageAccount,
        [string]$ContainerName,
        [string]$StorageKey,
        [string]$BlobName
    )
    
    try {
        Write-StatusMessage "Uploading BACPAC to storage..." -Type Action -Indent 3
        
        $storageContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $StorageKey
        
        $fileInfo = Get-Item $FilePath
        $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        
        Write-StatusMessage "Uploading file: $BlobName (Size: $fileSizeMB MB)" -Type Info -Indent 4
        
        $result = Set-AzStorageBlobContent -File $FilePath -Container $ContainerName -Blob $BlobName -Context $storageContext -Force
        
        if ($result) {
            Write-StatusMessage "Upload completed successfully" -Type Success -Indent 4
            Write-StatusMessage "Blob URL: $($result.ICloudBlob.Uri.AbsoluteUri)" -Type Success -Indent 4
            return $true
        } else {
            Write-StatusMessage "Upload failed" -Type Error -Indent 4
            return $false
        }
    } catch {
        Write-StatusMessage "Error uploading to storage: $($_.Exception.Message)" -Type Error -Indent 3
        return $false
    }
}

function Download-BacpacFromStorage {
    [CmdletBinding()]
    param(
        [string]$StorageAccount,
        [string]$ContainerName,
        [string]$StorageKey,
        [string]$BlobName,
        [string]$LocalPath
    )
    
    try {
        Write-StatusMessage "Downloading BACPAC from storage..." -Type Action -Indent 3
        
        $storageContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $StorageKey
        
        # Check if blob exists
        $blob = Get-AzStorageBlob -Container $ContainerName -Blob $BlobName -Context $storageContext -ErrorAction Stop
        $blobSizeMB = [math]::Round($blob.Length / 1MB, 2)
        
        Write-StatusMessage "Downloading blob: $BlobName (Size: $blobSizeMB MB)" -Type Info -Indent 4
        
        # Ensure local directory exists
        $localDir = Split-Path -Path $LocalPath -Parent
        if (-not (Test-Path $localDir)) {
            New-Item -Path $localDir -ItemType Directory -Force | Out-Null
        }
        
        Get-AzStorageBlobContent -Container $ContainerName -Blob $BlobName -Destination $LocalPath -Context $storageContext -Force | Out-Null
        
        if (Test-Path $LocalPath) {
            Write-StatusMessage "Download completed successfully" -Type Success -Indent 4
            return $true
        } else {
            Write-StatusMessage "Download failed - file not found after download" -Type Error -Indent 4
            return $false
        }
    } catch {
        Write-StatusMessage "Error downloading from storage: $($_.Exception.Message)" -Type Error -Indent 3
        return $false
    }
}

function Find-LatestBacpacBlob {
    [CmdletBinding()]
    param(
        [string]$StorageAccount,
        [string]$ContainerName,
        [string]$StorageKey,
        [string]$DatabaseName
    )
    
    try {
        Write-StatusMessage "Searching for latest BACPAC file for database: $DatabaseName" -Type Info -Indent 3
        
        $storageContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $StorageKey
        
        # Get all blobs that match the database name pattern
        $blobs = Get-AzStorageBlob -Container $ContainerName -Context $storageContext | 
                 Where-Object { $_.Name -like "$DatabaseName*.bacpac" } |
                 Sort-Object LastModified -Descending
        
        if ($blobs.Count -eq 0) {
            Write-StatusMessage "No BACPAC files found for database: $DatabaseName" -Type Warning -Indent 4
            return $null
        }
        
        $latestBlob = $blobs[0]
        Write-StatusMessage "Found latest BACPAC: $($latestBlob.Name) (Modified: $($latestBlob.LastModified))" -Type Success -Indent 4
        
        return $latestBlob.Name
    } catch {
        Write-StatusMessage "Error searching for BACPAC files: $($_.Exception.Message)" -Type Error -Indent 3
        return $null
    }
}

# # Export all functions
# Export-ModuleMember -Function Write-StatusMessage, Get-ServerFQDN, Test-Prerequisites, Test-RequiredFields, Test-DiskSpace, Test-SqlServerAccess, Test-StorageAccess, Export-DatabaseOperation, Import-DatabaseOperation, Export-SqlDatabaseToBacpac, Import-BacpacToSqlDatabase, Upload-BacpacToStorage, Download-BacpacFromStorage, Find-LatestBacpacBlob
