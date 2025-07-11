[CmdletBinding()]
param(
    [string]$CsvPath = ".\input\input.csv",
    [string]$SqlPackagePath = "sqlpackage.exe",
    [string]$LogsFolder = ".\logs"
)

Begin {
    # Import the module from the same directory as the script
    $moduleFile = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "SQLMove.psm1"
    Import-Module $moduleFile -Force

    # Initialize logging
    Initialize-Logging -LogsFolder $LogsFolder

    # Check prerequisites
    if (-not (Test-Prerequisites -SqlPackagePath $SqlPackagePath -CsvPath $CsvPath)) {
        Write-StatusMessage "Prerequisites check failed. Exiting script." -Type Error
        exit 1
    }

    # Read the CSV file
    $csvData = Import-Csv -Path $CsvPath
    Write-StatusMessage "Loaded $($csvData.Count) operation(s) from CSV file." -Type Info
    
    # Start total script execution stopwatch
    $totalScriptStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    # Initialize arrays to store operation durations for summary
    $exportDurations = @()
    $importDurations = @()
    $operationDurations = @()
}

Process {
    # Process each line in the CSV
    $totalRows = $csvData.Count
    $currentRow = 0
    
    foreach ($row in $csvData) {
        $currentRow++
        $operationId = $row.Operation_ID
        $databaseName = $row.Database_Name
        $operationStartTime = Get-Date
        $operationStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Initialize operation-specific logging
        $logFile = Initialize-OperationLogging -OperationId $operationId -DatabaseName $databaseName -StartTime $operationStartTime -LogsFolder $LogsFolder
        
        Write-StatusMessage "=======================================================" -Type Header
        Write-StatusMessage "Processing Operation [$currentRow/$totalRows]: $operationId" -Type Header
        Write-StatusMessage "Log file: $logFile" -Type Info
        Write-StatusMessage "=======================================================" -Type Header

        # Log operation start
        Write-LogMessage -LogFile $logFile -Message "=== OPERATION START ===" -Type Header
        Write-LogMessage -LogFile $logFile -Message "Operation ID: $operationId" -Type Info
        Write-LogMessage -LogFile $logFile -Message "Database Name: $databaseName" -Type Info
        Write-LogMessage -LogFile $logFile -Message "Start Time: $($operationStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Type Info

        # Parse boolean flags
        $exportAction = [bool]::Parse($row.Export_Action)
        $importAction = [bool]::Parse($row.Import_Action)
        
        # Parse Remove_Tempfile flag (default to true if not specified)
        $removeTempFile = $true
        if ($row.PSObject.Properties.Name -contains 'Remove_Tempfile') {
            $removeTempFile = [bool]::Parse($row.Remove_Tempfile)
        }

        # Get deployment type (default to AzurePaaS if not specified)
        $deploymentType = if ([string]::IsNullOrEmpty($row.Type)) { "AzurePaaS" } else { $row.Type }

        Write-StatusMessage "Export Action: $exportAction" -Type Info -Indent 1
        Write-StatusMessage "Import Action: $importAction" -Type Info -Indent 1
        Write-StatusMessage "Remove Temp File: $removeTempFile" -Type Info -Indent 1
        Write-StatusMessage "Deployment Type: $deploymentType" -Type Info -Indent 1
        
        Write-LogMessage -LogFile $logFile -Message "Export Action: $exportAction" -Type Info
        Write-LogMessage -LogFile $logFile -Message "Import Action: $importAction" -Type Info
        Write-LogMessage -LogFile $logFile -Message "Remove Temp File: $removeTempFile" -Type Info
        Write-LogMessage -LogFile $logFile -Message "Deployment Type: $deploymentType" -Type Info

        # Skip if both actions are false
        if (-not $exportAction -and -not $importAction) {
            $message = "Both Export and Import actions are disabled. Skipping operation."
            Write-StatusMessage $message -Type Warning -Indent 1
            Write-LogMessage -LogFile $logFile -Message $message -Type Warning
            Write-LogMessage -LogFile $logFile -Message "=== OPERATION SKIPPED ===" -Type Header
            continue
        }

        # Calculate FQDNs
        $srcServerFQDN = Get-ServerFQDN -ServerName $row.SRC_server -DeploymentType $deploymentType
        $dstServerFQDN = Get-ServerFQDN -ServerName $row.DST_server -DeploymentType $deploymentType

        Write-StatusMessage "Source Server: $($row.SRC_server) -> $srcServerFQDN" -Type Info -Indent 1
        Write-StatusMessage "Destination Server: $($row.DST_server) -> $dstServerFQDN" -Type Info -Indent 1
        Write-StatusMessage "Database: $databaseName" -Type Info -Indent 1

        Write-LogMessage -LogFile $logFile -Message "Source Server: $($row.SRC_server) -> $srcServerFQDN" -Type Info
        Write-LogMessage -LogFile $logFile -Message "Destination Server: $($row.DST_server) -> $dstServerFQDN" -Type Info

        # Validate required fields based on actions
        if (-not (Test-RequiredFields -Row $row -ExportAction $exportAction -ImportAction $importAction -LogFile $logFile)) {
            $message = "Required field validation failed. Skipping operation."
            Write-StatusMessage $message -Type Error -Indent 1
            Write-LogMessage -LogFile $logFile -Message $message -Type Error
            Write-LogMessage -LogFile $logFile -Message "=== OPERATION FAILED - VALIDATION ===" -Type Header
            continue
        }

        # Perform pre-flight checks
        Write-StatusMessage "Performing pre-flight checks..." -Type Action -Indent 1
        Write-LogMessage -LogFile $logFile -Message "Starting pre-flight checks..." -Type Action
        
        $preflightSuccess = $true

        # Check source server access if export is enabled
        if ($exportAction) {
            if (-not (Test-SqlServerAccess -ServerFQDN $srcServerFQDN -DatabaseName $databaseName -Username $row.SRC_SQL_Admin -Password $row.SRC_SQL_Password -Operation "source" -LogFile $logFile -DeploymentType $deploymentType)) {
                $preflightSuccess = $false
            }
        }

        # Check destination server access if import is enabled
        if ($importAction) {
            if (-not (Test-SqlServerAccess -ServerFQDN $dstServerFQDN -DatabaseName $databaseName -Username $row.DST_SQL_Admin -Password $row.DST_SQL_Password -Operation "destination" -LogFile $logFile -DeploymentType $deploymentType)) {
                $preflightSuccess = $false
            }
        }

        # Check storage access if either action is enabled
        if ($exportAction -or $importAction) {
            if (-not (Test-StorageAccess -StorageAccount $row.Storage_Account -StorageContainer $row.Storage_Container -StorageKey $row.Storage_Access_Key -LogFile $logFile)) {
                $preflightSuccess = $false
            }
        }

        # Check disk space if export is enabled
        if ($exportAction) {
            if (-not (Test-DiskSpace -Path $row.Local_Folder -RequiredSpaceGB 10 -LogFile $logFile)) {
                $preflightSuccess = $false
            }
        }

        if (-not $preflightSuccess) {
            $message = "Pre-flight checks failed. Skipping operation."
            Write-StatusMessage $message -Type Error -Indent 1
            Write-LogMessage -LogFile $logFile -Message $message -Type Error
            Write-LogMessage -LogFile $logFile -Message "=== OPERATION FAILED - PREFLIGHT ===" -Type Header
            continue
        }

        Write-StatusMessage "Pre-flight checks completed successfully." -Type Success -Indent 1
        Write-LogMessage -LogFile $logFile -Message "Pre-flight checks completed successfully." -Type Success

        # Execute Export Action
        if ($exportAction) {
            Write-StatusMessage "Starting Export Operation..." -Type Action -Indent 1
            Write-LogMessage -LogFile $logFile -Message "=== EXPORT OPERATION START ===" -Type Header
            $exportStartTime = Get-Date
            $exportSuccess = Export-DatabaseOperation -Row $row -SqlPackagePath $SqlPackagePath -LogFile $logFile -StartTime $exportStartTime
            
            if (-not $exportSuccess) {
                $message = "Export operation failed. Skipping import if enabled."
                Write-StatusMessage $message -Type Error -Indent 1
                Write-LogMessage -LogFile $logFile -Message $message -Type Error
                Write-LogMessage -LogFile $logFile -Message "=== OPERATION FAILED - EXPORT ===" -Type Header
                continue
            }
            
            Write-LogMessage -LogFile $logFile -Message "=== EXPORT OPERATION COMPLETED ===" -Type Header
        }

        # Execute Import Action
        if ($importAction) {
            Write-StatusMessage "Starting Import Operation..." -Type Action -Indent 1
            Write-LogMessage -LogFile $logFile -Message "=== IMPORT OPERATION START ===" -Type Header
            $importStartTime = Get-Date
            $importSuccess = Import-DatabaseOperation -Row $row -SqlPackagePath $SqlPackagePath -LogFile $logFile -StartTime $importStartTime
            
            if (-not $importSuccess) {
                $message = "Import operation failed."
                Write-StatusMessage $message -Type Error -Indent 1
                Write-LogMessage -LogFile $logFile -Message $message -Type Error
                Write-LogMessage -LogFile $logFile -Message "=== OPERATION FAILED - IMPORT ===" -Type Header
                continue
            }
            
            Write-LogMessage -LogFile $logFile -Message "=== IMPORT OPERATION COMPLETED ===" -Type Header
        }

        $operationStopwatch.Stop()
        $operationEndTime = Get-Date
        $operationDuration = New-TimeSpan -Start $operationStartTime -End $operationEndTime
        $operationDurationFormatted = "{0:hh\:mm\:ss}" -f $operationDuration
        
        # Store operation duration for summary
        $operationDurations += [PSCustomObject]@{
            OperationId = $operationId
            DatabaseName = $databaseName
            Duration = $operationDuration
        }
        
        Write-StatusMessage "Operation $operationId completed successfully in $operationDurationFormatted." -Type Success
        Write-LogMessage -LogFile $logFile -Message "Operation completed successfully." -Type Success
        Write-LogMessage -LogFile $logFile -Message "End Time: $($operationEndTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Type Info
        Write-LogMessage -LogFile $logFile -Message "Total Duration: $operationDurationFormatted" -Type Info
        Write-LogMessage -LogFile $logFile -Message "=== OPERATION COMPLETED SUCCESSFULLY ===" -Type Header
    }
}

End {
    $totalScriptStopwatch.Stop()
    $totalScriptDuration = $totalScriptStopwatch.Elapsed
    $totalScriptDurationFormatted = "{0:hh\:mm\:ss}" -f $totalScriptDuration
    
    Write-StatusMessage "🎉 All database operations completed." -Type Success
    Write-StatusMessage "=======================================================" -Type Header
    Write-StatusMessage "Operation Summary" -Type Header
    Write-StatusMessage "=======================================================" -Type Header
    
    # Calculate total export and import durations if applicable
    # Note: Since we don't have direct access to export/import durations from the functions,
    # we will summarize total operation durations instead.
    if ($operationDurations.Count -gt 0) {
        $totalOperationTime = New-Object System.TimeSpan
        foreach ($op in $operationDurations) {
            $totalOperationTime = $totalOperationTime.Add($op.Duration)
        }
        $totalOperationTimeFormatted = "{0:hh\:mm\:ss}" -f $totalOperationTime
        
        Write-StatusMessage "Total Operations Processed: $($operationDurations.Count)" -Type Info
        Write-StatusMessage "Total Operation Time: $totalOperationTimeFormatted" -Type Info
        
        # List individual operation durations
        Write-StatusMessage "Individual Operation Durations:" -Type Info
        foreach ($op in $operationDurations) {
            $opDurationFormatted = "{0:hh\:mm\:ss}" -f $op.Duration
            Write-StatusMessage "  - Operation $($op.OperationId) ($($op.DatabaseName)): $opDurationFormatted" -Type Info
        }
    } else {
        Write-StatusMessage "No operations were processed." -Type Warning
    }
    
    Write-StatusMessage "Total Script Execution Time: $totalScriptDurationFormatted" -Type Info
    Write-StatusMessage "=======================================================" -Type Header
}
