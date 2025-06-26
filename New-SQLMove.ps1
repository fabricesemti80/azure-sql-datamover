[CmdletBinding()]
param(
    [string]$CsvPath = ".\input\input.csv",
    [string]$SqlPackagePath = "sqlpackage.exe"
)

Begin {
    # Import the module from the same directory as the script
    $moduleFile = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "SQLMove.psm1"
    Import-Module $moduleFile -Force

    # Check prerequisites
    if (-not (Test-Prerequisites -SqlPackagePath $SqlPackagePath -CsvPath $CsvPath)) {
        Write-StatusMessage "Prerequisites check failed. Exiting script." -Type Error
        exit 1
    }

    # Read the CSV file
    $csvData = Import-Csv -Path $CsvPath
    Write-StatusMessage "Loaded $($csvData.Count) operation(s) from CSV file." -Type Info
}

Process {
    # Process each line in the CSV
    $totalRows = $csvData.Count
    $currentRow = 0
    
    foreach ($row in $csvData) {
        $currentRow++
        $operationId = $row.Operation_ID
        
        Write-StatusMessage "=======================================================" -Type Header
        Write-StatusMessage "Processing Operation [$currentRow/$totalRows]: $operationId" -Type Header
        Write-StatusMessage "=======================================================" -Type Header

        # Parse boolean flags
        $exportAction = [bool]::Parse($row.Export_Action)
        $importAction = [bool]::Parse($row.Import_Action)

        Write-StatusMessage "Export Action: $exportAction" -Type Info -Indent 1
        Write-StatusMessage "Import Action: $importAction" -Type Info -Indent 1

        # Skip if both actions are false
        if (-not $exportAction -and -not $importAction) {
            Write-StatusMessage "Both Export and Import actions are disabled. Skipping operation." -Type Warning -Indent 1
            continue
        }

        # Calculate FQDNs
        $srcServerFQDN = Get-ServerFQDN -ServerName $row.SRC_server
        $dstServerFQDN = Get-ServerFQDN -ServerName $row.DST_server

        Write-StatusMessage "Source Server: $($row.SRC_server) -> $srcServerFQDN" -Type Info -Indent 1
        Write-StatusMessage "Destination Server: $($row.DST_server) -> $dstServerFQDN" -Type Info -Indent 1
        Write-StatusMessage "Database: $($row.Database_Name)" -Type Info -Indent 1

        # Validate required fields based on actions
        if (-not (Test-RequiredFields -Row $row -ExportAction $exportAction -ImportAction $importAction)) {
            Write-StatusMessage "Required field validation failed. Skipping operation." -Type Error -Indent 1
            continue
        }

        # Perform pre-flight checks
        Write-StatusMessage "Performing pre-flight checks..." -Type Action -Indent 1
        
        $preflightSuccess = $true

        # Check source server access if export is enabled
        if ($exportAction) {
            if (-not (Test-SqlServerAccess -ServerFQDN $srcServerFQDN -DatabaseName $row.Database_Name -Username $row.SRC_SQL_Admin -Password $row.SRC_SQL_Password -Operation "source")) {
                $preflightSuccess = $false
            }
        }

        # Check destination server access if import is enabled
        if ($importAction) {
            if (-not (Test-SqlServerAccess -ServerFQDN $dstServerFQDN -DatabaseName $row.Database_Name -Username $row.DST_SQL_Admin -Password $row.DST_SQL_Password -Operation "destination")) {
                $preflightSuccess = $false
            }
        }

        # Check storage access if either action is enabled
        if ($exportAction -or $importAction) {
            if (-not (Test-StorageAccess -StorageAccount $row.Storage_Account -StorageContainer $row.Storage_Container -StorageKey $row.Storage_Access_Key)) {
                $preflightSuccess = $false
            }
        }

        # Check disk space if export is enabled
        if ($exportAction) {
            $localBackupDir = Split-Path -Path $row.Local_Backup_File_Path -Parent
            if (-not (Test-DiskSpace -Path $localBackupDir -RequiredSpaceGB 10)) {
                $preflightSuccess = $false
            }
        }

        if (-not $preflightSuccess) {
            Write-StatusMessage "Pre-flight checks failed. Skipping operation." -Type Error -Indent 1
            continue
        }

        Write-StatusMessage "Pre-flight checks completed successfully." -Type Success -Indent 1

        # Execute Export Action
        if ($exportAction) {
            Write-StatusMessage "Starting Export Operation..." -Type Action -Indent 1
            
            $exportSuccess = Export-DatabaseOperation -Row $row -SqlPackagePath $SqlPackagePath
            
            if (-not $exportSuccess) {
                Write-StatusMessage "Export operation failed. Skipping import if enabled." -Type Error -Indent 1
                continue
            }
        }

        # Execute Import Action
        if ($importAction) {
            Write-StatusMessage "Starting Import Operation..." -Type Action -Indent 1
            
            $importSuccess = Import-DatabaseOperation -Row $row -SqlPackagePath $SqlPackagePath
            
            if (-not $importSuccess) {
                Write-StatusMessage "Import operation failed." -Type Error -Indent 1
                continue
            }
        }

        Write-StatusMessage "Operation $operationId completed successfully." -Type Success
    }
}

End {
    Write-StatusMessage "🎉 All database operations completed." -Type Success
}
