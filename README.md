# SQL Data Mover Module

A PowerShell module for automating database migration operations between Azure SQL Database (PaaS) and Azure SQL Managed Instance environments.

## Overview

The SQL Data Mover module provides functionality for:
- Exporting databases to BACPAC files
- Uploading backup files to Azure Storage
- Downloading backup files from Azure Storage
- Importing databases from backup files
- Supporting Azure SQL PaaS and Managed Instance deployments

## Supported Deployment Types

| Deployment Type | Export Format | Import Format | Notes                      |
| --------------- | ------------- | ------------- | -------------------------- |
| **AzurePaaS**   | BACPAC        | BACPAC        | Azure SQL Database         |
| **AzureMI**     | BACPAC        | BACPAC        | Azure SQL Managed Instance |

## Using the Module

Use the `New-SQLMove.ps1` script to execute database operations:

```powershell
.\New-SQLMove.ps1 -CsvPath ".\input\input.csv" -SqlPackagePath "sqlpackage.exe" -LogsFolder ".\logs"
```

### Parameters

- **CsvPath**: Path to the CSV file containing database operation details (default: `.\input\input.csv`)
- **SqlPackagePath**: Path to the SqlPackage.exe executable (default: `sqlpackage.exe`)
- **LogsFolder**: Path to store log files (default: `.\logs`)

## CSV Configuration

The module requires a CSV file with the following fields:

### Required Fields

| Field                | Description                          | Required For |
| -------------------- | ------------------------------------ | ------------ |
| `Operation_ID`       | Unique identifier for the operation  | All          |
| `Type`               | Deployment type (AzurePaaS/AzureMI)  | All          |
| `Database_Name`      | Name of the database                 | All          |
| `Local_Folder`       | Local folder for temporary files     | All          |
| `Storage_Account`    | Azure Storage account name           | All          |
| `Storage_Container`  | Storage container name               | All          |
| `Storage_Access_Key` | Storage account access key           | All          |
| `SRC_server`         | Source server name                   | Export       |
| `SRC_SQL_Admin`      | Source SQL admin username            | Export       |
| `SRC_SQL_Password`   | Source SQL admin password            | Export       |
| `DST_server`         | Destination server name              | Import       |
| `DST_SQL_Admin`      | Destination SQL admin username       | Import       |
| `DST_SQL_Password`   | Destination SQL admin password       | Import       |
| `Export_Action`      | Enable export operation (true/false) | Optional     |
| `Import_Action`      | Enable import operation (true/false) | Optional     |
| `Remove_Tempfile`    | Clean up temp files (true/false)     | Optional     |

## Example CSV

```csv
Operation_ID,Type,SRC_server,SRC_SQL_Admin,SRC_SQL_Password,DST_server,DST_SQL_Admin,DST_SQL_Password,Database_Name,Local_Folder,Storage_Account,Storage_Container,Storage_Access_Key,Export_Action,Import_Action,Remove_Tempfile
001,AzureMI,sqlmi-source.1234abcd,sqladmin,password123,sqlmi-target.5678efgh,sqladmin,password123,AdventureWorks,C:\Temp,mystorageacct,mycontainer,storagekey123==,True,True,False
002,AzurePaas,sql-source,sqladmin,password123,sql-target,sqladmin,password123,WideWorld,C:\Temp,mystorageacct,mycontainer,storagekey123==,True,True,False
```

## Prerequisites

- PowerShell 5.1 or later
- Az.Storage PowerShell module
- SqlPackage.exe (from SQL Server Data Tools)
- Write access to local temporary folder
- Access to source/destination SQL servers
- Access to Azure Storage account

### Installation

```powershell
# Install Azure Storage module
Install-Module -Name Az.Storage -Scope CurrentUser -Force
```

## Operation Flow

1. **Validation**
   - Checks prerequisites
   - Validates CSV fields
   - Verifies access permissions

2. **Export** (if enabled)
   - Exports database to BACPAC
   - Uploads to Azure Storage
   - Cleans up temporary files (if configured)

3. **Import** (if enabled)
   - Downloads BACPAC from storage
   - Imports to destination
   - Cleans up temporary files (if configured)

## Logging

The module creates detailed logs in the specified logs folder:
- Session log: `session_YYYYMMDD_HHMMSS.log`
- Operation log: `{Operation_ID}_{Database_Name}_YYYYMMDD_HHMMSS.log`

## Common Issues

| Issue                 | Solution                                                    |
| --------------------- | ----------------------------------------------------------- |
| SqlPackage not found  | Verify SqlPackage.exe path or install SQL Server Data Tools |
| Storage access denied | Check storage account key and permissions                   |
| Connection timeout    | Verify server names and firewall rules                      |
| Insufficient space    | Ensure adequate space in Local_Folder                       |

## Module Structure

- `New-SQLMove.ps1`: Main script
- `SQLMove.psm1`: Core module functions
- `input/input.csv`: Operation configuration
- `logs/`: Log file directory

## Key Functions

- Export-DatabaseOperation
- Import-DatabaseOperation
- Test-Prerequisites
- Test-SqlServerAccess
- Test-StorageAccess
- Initialize-Logging

## Limitations

- Supports only BACPAC format
- Requires Windows environment
- Single-threaded operation
- Temporary files require local storage

## Best Practices

1. Use unique Operation_IDs
2. Test with small databases first
3. Monitor available disk space
4. Review logs for operation status
5. Secure credentials in production
6. Regular storage key rotation

## Support

For issues or questions:
- Check the log files
- Verify CSV configuration
- Ensure prerequisites are met
- Test connectivity to all services
- Contact: [Fabrice Semti] - [ fsemti@linkfinancial.eu or fabrice.semti@gmail.com]
