# SQL Data Mover Module

A PowerShell module for automating database migration operations between different SQL Server platforms, with support for Azure SQL Database (PaaS), Azure SQL Managed Instance, and Azure SQL IaaS VMs.

## Overview

The SQL Data Mover module provides comprehensive functionality for:
- Exporting databases to BACPAC or BAK files
- Uploading backup files to Azure Storage
- Downloading backup files from Azure Storage
- Importing databases from backup files
- Supporting multiple Azure SQL deployment types

## Supported Deployment Types

| Deployment Type | Export Format | Import Format | Notes                      |
| --------------- | ------------- | ------------- | -------------------------- |
| **AzurePaaS**   | BACPAC        | BACPAC        | Azure SQL Database         |
| **AzureMI**     | BACPAC/BAK    | BACPAC/BAK    | Azure SQL Managed Instance |
| **AzureIaaS**   | BACPAC/BAK    | BACPAC/BAK    | SQL Server on Azure VMs    |

## Using the Module

The recommended way to use this module is through the `New-SQLMove.ps1` script, which provides a simplified interface to the module functionality.

```powershell
.\New-SQLMove.ps1 -CsvPath ".\input\input.csv" -SqlPackagePath "sqlpackage.exe" -LogsFolder ".\logs"
```

### Parameters

- **CsvPath**: Path to the CSV file containing database operation details (default: `.\input\input.csv`)
- **SqlPackagePath**: Path to the SqlPackage.exe executable (default: `sqlpackage.exe`)
- **LogsFolder**: Path to store log files (default: `.\logs`)

## CSV Configuration

The module requires a properly formatted CSV file with the following fields:

### Required Fields

| Field                | Description                         | Example              |
| -------------------- | ----------------------------------- | -------------------- |
| `Operation_ID`       | Unique identifier for the operation | `001`, `002`         |
| `Database_Name`      | Name of the database                | `WideWorldImporters` |
| `Storage_Account`    | Azure Storage account name          | `mystorageaccount`   |
| `Storage_Container`  | Storage container name              | `backups`            |
| `Storage_Access_Key` | Storage account access key          | `base64key...`       |

### Export-Specific Fields

| Field                    | Description                 | Example                |
| ------------------------ | --------------------------- | ---------------------- |
| `SRC_server`             | Source server name          | `sql-server-01`        |
| `SRC_SQL_Admin`          | Source SQL admin username   | `sqladmin`             |
| `SRC_SQL_Password`       | Source SQL admin password   | `P@ssw0rd123`          |
| `Local_Backup_File_Path` | Local path for backup files | `C:\Backups\db.bacpac` |

### Import-Specific Fields

| Field              | Description                    | Example       |
| ------------------ | ------------------------------ | ------------- |
| `DST_server`       | Destination server name        | `sql-mi-01`   |
| `DST_SQL_Admin`    | Destination SQL admin username | `sqladmin`    |
| `DST_SQL_Password` | Destination SQL admin password | `P@ssw0rd123` |

### Optional Fields

| Field             | Description              | Default     | Example                |
| ----------------- | ------------------------ | ----------- | ---------------------- |
| `Type`            | Deployment type          | `AzurePaaS` | `AzureMI`, `AzureIaaS` |
| `Remove_Tempfile` | Clean up local files     | `true`      | `false`                |
| `Export_Action`   | Perform export operation | `true`      | `false`                |
| `Import_Action`   | Perform import operation | `true`      | `false`                |

## Prerequisites

### Software Requirements
- **PowerShell 5.1** or later
- **Azure PowerShell Module** (`Az.Storage`)
- **SqlPackage.exe** (from SQL Server Data Tools)
- **SQL Server Management Objects** (for SQL operations)

### Installation Commands

```powershell
# Install Azure PowerShell module
Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force

# Install specific storage module
Install-Module -Name Az.Storage -Scope CurrentUser -Force

# Verify SqlPackage.exe location
Get-Command SqlPackage.exe -ErrorAction SilentlyContinue
```

### Permissions Required
- **Source Database**: `db_datareader`, `db_datawriter`, `db_ddladmin`
- **Destination Database**: `db_owner` or equivalent
- **Azure Storage**: Read/Write access to storage account
- **Local System**: Write access to temporary directories

## Example Usage

1. Create a CSV file with your database operation details (see example in `dev_scripts/example_input.csv`)
2. Run the script:

```powershell
.\New-SQLMove.ps1 -CsvPath ".\input\input.csv"
```

3. Monitor the console output and log files for operation status

## Workflow Overview

1. **Validation**: The script validates prerequisites and required fields in the CSV
2. **Pre-flight Checks**: Connectivity to SQL servers and storage is verified
3. **Export**: If enabled, databases are exported to local files then uploaded to Azure Storage
4. **Import**: If enabled, databases are imported from local files (downloaded from storage if needed)
5. **Cleanup**: Temporary files are removed if configured

## Troubleshooting

Common issues and solutions:

- **SqlPackage Not Found**: Ensure the SqlPackage.exe path is correct
- **Storage Access Denied**: Verify the storage account key is valid
- **Connection Timeout**: Check firewall rules and connectivity
- **Insufficient Disk Space**: Ensure enough space for temporary files

For detailed logging, check the log files generated in the specified log folder.

## Logging

The module creates detailed logs in the specified logs folder:
- Session-level logs for overall operations
- Operation-specific logs for each database operation

Log messages include timestamps, message types (Info, Action, Success, Error), and detailed operation information.

## Advanced Usage

### Memory-Optimized Objects Handling

When working with databases containing memory-optimized objects in Azure SQL Managed Instance:

1. **Business Critical tier**: Can directly restore databases with memory-optimized objects
2. **General Purpose tier**: Requires special handling:
   - May need an intermediate server to remove memory-optimized objects
   - Consider upgrading to Business Critical tier if memory-optimized objects are required

### Security Best Practices

- **Never hardcode credentials** in CSV files for production environments
- **Store CSV files securely** with appropriate access controls
- **Consider using environment variables** or secure credential stores
- **Rotate storage keys** regularly
- **Remove temporary files** after operations complete

### Parallel Processing

For environments with many databases, consider running multiple operations in parallel:

```powershell
$csvData = Import-Csv -Path ".\input\input.csv"
$jobs = @()

foreach ($row in $csvData) {
    $scriptBlock = {
        param($csvRow, $sqlPackagePath, $logsFolder)
        # Import required module
        Import-Module .\SQLMove.psm1
        
        # Process the row
        $operationId = $csvRow.Operation_ID
        $databaseName = $csvRow.Database_Name
        $logFile = Join-Path -Path $logsFolder -ChildPath "${operationId}_${databaseName}.log"
        
        # Process export/import as needed
        # ... (additional processing code)
    }
    
    $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $row, "sqlpackage.exe", ".\logs"
    $jobs += $job
}

# Wait for all jobs to complete
$jobs | Wait-Job | Receive-Job
$jobs | Remove-Job
```

## Performance Considerations

### File Size Guidelines

| Database Size | Recommended Approach    | Notes                               |
| ------------- | ----------------------- | ----------------------------------- |
| < 1 GB        | Direct BACPAC           | Fast for small databases            |
| 1-10 GB       | BACPAC with monitoring  | Can take 15-60 minutes              |
| 10-100 GB     | BAK file preferred      | Faster than BACPAC for large DBs    |
| > 100 GB      | BAK with parallel tasks | Consider splitting large operations |

### Optimization Tips

1. **Use BAK files for large databases** (faster than BACPAC)
2. **Enable compression** for BAK exports
3. **Use SSD storage** for temporary files
4. **Schedule during off-peak hours**
5. **Monitor network bandwidth** during transfers
6. **Clean up temporary files** to save space

## Module Structure

The module consists of two main components:

1. **SQLMove.psm1**: The core module containing all functions
2. **New-SQLMove.ps1**: The main script that uses the module functions

### Core Functions

- **Test-Prerequisites**: Validates required tools and access
- **Test-RequiredFields**: Validates CSV configuration
- **Test-SqlServerAccess**: Tests database connectivity
- **Test-StorageAccess**: Tests Azure Storage connectivity
- **Export-DatabaseOperation**: Main export orchestration function
- **Import-DatabaseOperation**: Main import orchestration function
- **Get-ServerFQDN**: Constructs proper Azure SQL FQDNs
- **Initialize-Logging**: Sets up logging infrastructure
- **Write-LogMessage**: Writes messages to log files
- **Write-StatusMessage**: Provides formatted console output

## Limitations

- Requires Windows environment for SqlPackage.exe
- Large databases may take significant time to process
- Memory-optimized objects require special handling in General Purpose tier
- Temporary files require sufficient disk space

## Support and Maintenance

For issues, feature requests, or contributions:
- File issues in the project repository
- Include detailed error logs and configuration details
- Provide CSV samples (with sensitive data removed)

## Version History

| Version | Date       | Changes                                      |
| ------- | ---------- | -------------------------------------------- |
| 1.0.0   | 2024-05-01 | Initial release                              |
| 1.1.0   | TBD        | Planned: Enhanced memory-optimized handling  |
| 1.2.0   | TBD        | Planned: Improved error handling and logging |

## Example Scenarios

### Scenario 1: PaaS to PaaS Migration

Migrating a database from one Azure SQL Database server to another:

```csv
Operation_ID,Type,SRC_server,SRC_SQL_Admin,SRC_SQL_Password,DST_server,DST_SQL_Admin,DST_SQL_Password,Database_Name,Local_Backup_File_Path,Storage_Account,Storage_Container,Storage_Access_Key,Export_Action,Import_Action,Remove_Tempfile
001,AzurePaaS,sql-paas-source,sqladmin,SourcePassword,sql-paas-target,sqladmin,TargetPassword,CustomerDB,C:\Temp\CustomerDB.bacpac,storageaccount,migrations,StorageKey123,true,true,true
```

### Scenario 2: On-premises to Managed Instance

Migrating from an on-premises SQL Server to Azure SQL Managed Instance:

```csv
Operation_ID,Type,SRC_server,SRC_SQL_Admin,SRC_SQL_Password,DST_server,DST_SQL_Admin,DST_SQL_Password,Database_Name,Local_Backup_File_Path,Storage_Account,Storage_Container,Storage_Access_Key,Export_Action,Import_Action,Remove_Tempfile
002,AzureMI,on-prem-sql.contoso.local,sa,OnPremPassword,sqlmi-target.database.windows.net,sqladmin,MIPassword,InventoryDB,C:\Temp\InventoryDB.bak,storageaccount,migrations,StorageKey123,true,true,true
```

### Scenario 3: Export Only for Backup

Creating a backup of an Azure SQL Database without importing:

```csv
Operation_ID,Type,SRC_server,SRC_SQL_Admin,SRC_SQL_Password,DST_server,DST_SQL_Admin,DST_SQL_Password,Database_Name,Local_Backup_File_Path,Storage_Account,Storage_Container,Storage_Access_Key,Export_Action,Import_Action,Remove_Tempfile
003,AzurePaaS,sql-paas-prod,sqladmin,ProdPassword,,,,,C:\Backups\WeeklyBackup.bacpac,storageaccount,backups,StorageKey123,true,false,false
```

### Scenario 4: Import from Existing Backup

Importing a database from an existing backup in Azure Storage:

```csv
Operation_ID,Type,SRC_server,SRC_SQL_Admin,SRC_SQL_Password,DST_server,DST_SQL_Admin,DST_SQL_Password,Database_Name,Local_Backup_File_Path,Storage_Account,Storage_Container,Storage_Access_Key,Export_Action,Import_Action,Remove_Tempfile
004,AzurePaaS,,,,,sql-paas-target,sqladmin,TargetPassword,SalesDB,C:\Temp\SalesDB.bacpac,storageaccount,backups,StorageKey123,false,true,true
```

## Integration Examples

### Azure DevOps Pipeline Integration

```yaml
# azure-pipelines.yml
trigger:
- main

pool:
  vmImage: 'windows-latest'

steps:
- task: AzurePowerShell@5
  inputs:
    azureSubscription: 'Your-Azure-Connection'
    ScriptType: 'FilePath'
    ScriptPath: '$(System.DefaultWorkingDirectory)/New-SQLMove.ps1'
    ScriptArguments: '-CsvPath "$(System.DefaultWorkingDirectory)/migration-config.csv" -LogsFolder "$(Build.ArtifactStagingDirectory)/logs"'
    azurePowerShellVersion: 'LatestVersion'

- task: PublishBuildArtifacts@1
  inputs:
    PathtoPublish: '$(Build.ArtifactStagingDirectory)/logs'
    ArtifactName: 'migration-logs'
    publishLocation: 'Container'
```

### PowerShell Universal Dashboard Integration

```powershell
New-UDDashboard -Title "SQL Database Migration Dashboard" -Content {
    New-UDRow -Columns {
        New-UDColumn -Size 12 -Content {
            New-UDCard -Title "Database Migration Operations" -Content {
                New-UDForm -Content {
                    New-UDTextbox -Id "sourceServer" -Label "Source Server"
                    New-UDTextbox -Id "destServer" -Label "Destination Server"
                    New-UDTextbox -Id "databaseName" -Label "Database Name"
                    New-UDCheckbox -Id "exportAction" -Label "Export Database" -Checked
                    New-UDCheckbox -Id "importAction" -Label "Import Database" -Checked
                } -OnSubmit {
                    # Generate CSV content
                    $csvContent = @"
Operation_ID,Type,SRC_server,SRC_SQL_Admin,SRC_SQL_Password,DST_server,DST_SQL_Admin,DST_SQL_Password,Database_Name,Local_Backup_File_Path,Storage_Account,Storage_Container,Storage_Access_Key,Export_Action,Import_Action,Remove_Tempfile
$(New-Guid).ToString().Substring(0,8),AzurePaaS,$($EventData.sourceServer),sqladmin,StoredSecurePassword,$($EventData.destServer),sqladmin,StoredSecurePassword,$($EventData.databaseName),C:\Temp\$($EventData.databaseName).bacpac,storageaccount,migrations,StorageKey123,$($EventData.exportAction.ToString().ToLower()),$($EventData.importAction.ToString().ToLower()),true
"@
                    # Save CSV to temp file
                    $csvPath = "C:\Temp\migration-$(Get-Date -Format 'yyyyMMddHHmmss').csv"
                    $csvContent | Out-File -FilePath $csvPath
                    
                    # Run migration script
                    Start-Process -FilePath "powershell.exe" -ArgumentList "-File C:\Scripts\New-SQLMove.ps1 -CsvPath `"$csvPath`" -LogsFolder `"C:\Temp\Logs`""
                    
                    Show-UDToast -Message "Migration job started" -Duration 5000
                }
            }
        }
    }
}
```

## Scheduled Automation

For regular database migrations or backups, you can create a scheduled task:

```powershell
# Create scheduled task to run the SQL Move script
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\SQLMove\New-SQLMove.ps1" -CsvPath "C:\Scripts\SQLMove\daily-backup.csv"'
$trigger = New-ScheduledTaskTrigger -Daily -At 2am
$principal = New-ScheduledTaskPrincipal -UserId "DOMAIN\ServiceAccount" -LogonType Password
Register-ScheduledTask -TaskName "SQL-Daily-Backup" -Action $action -Trigger $trigger -Principal $principal -Description "Daily SQL database backup using SQL Move module"
```

## FAQ

### How do I handle sensitive information in CSV files?

Consider these approaches:
1. Use environment variables and reference them in your script
2. Use a secure credential store like Azure Key Vault
3. Use encrypted CSV files and decrypt at runtime
4. For scheduled tasks, use the Windows Credential Manager

### Can I use the module with Azure Private Endpoints?

Yes, the module works with private endpoints. Ensure:
1. The machine running the script has network connectivity to the private endpoints
2. DNS resolution is correctly configured for private endpoints
3. The storage account and SQL servers are configured with private endpoints

### How do I monitor the progress of a long-running operation?

1. Monitor the log files in real-time using `Get-Content -Path $logFile -Wait`
2. Set up email notifications upon completion
3. Use the `-Verbose` parameter with the script for detailed console output

### How can I extend the module for custom scenarios?

1. Import the module directly: `Import-Module .\SQLMove.psm1`
2. Use individual functions like `Export-DatabaseOperation` with custom parameters
3. Create your own wrapper script with additional pre/post processing

## Related Resources

- [Azure SQL Database Documentation](https://docs.microsoft.com/en-us/azure/azure-sql/database/)
- [Azure SQL Managed Instance Documentation](https://docs.microsoft.com/en-us/azure/azure-sql/managed-instance/)
- [SqlPackage Documentation](https://docs.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage)
- [Azure Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/)

---

This module is maintained by the Fabrice Semti (fabrice.semti@gmail.com).

Last updated: June 2025
