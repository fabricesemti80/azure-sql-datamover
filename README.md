# SQL Data Mover Module

A comprehensive PowerShell module for automating database migration operations between Azure SQL Database (PaaS), Azure SQL Managed Instance (MI), and SQL Server on Azure Virtual Machines (IaaS).

## Overview

The SQL Data Mover module provides robust functionality for:
- Exporting databases to BACPAC or BAK files.
- Uploading backup files to Azure Storage.
- Downloading backup files from Azure Storage.
- Importing databases from backup files.
- Supporting Azure SQL PaaS, Managed Instance, and IaaS deployments.
- Automating remote operations on IaaS VMs using PowerShell Remoting.

## Supported Deployment Types

| Deployment Type | Export Format   | Import Format   | Notes                                                 |
| --------------- | --------------- | --------------- | ----------------------------------------------------- |
| **AzurePaaS**   | BACPAC          | BACPAC          | Azure SQL Database                                    |
| **AzureMI**     | BACPAC, BAK     | BACPAC, BAK     | Azure SQL Managed Instance                            |
| **AzureIaaS**   | BACPAC, BAK     | BACPAC, BAK     | SQL Server on Azure VM (requires PowerShell Remoting) |

## Using the Module

Use the `New-SQLMove.ps1` script to execute database operations by providing a path to a CSV configuration file.

```powershell
.\New-SQLMove.ps1 -CsvPath ".\input\input.csv" -SqlPackagePath "C:\Program Files\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe" -LogsFolder ".\logs"
```

### Parameters

- **CsvPath**: Path to the CSV file containing database operation details (default: `.\input\input.csv`).
- **SqlPackagePath**: Full path to the `SqlPackage.exe` executable (default: `sqlpackage.exe`). It's recommended to provide the full path.
- **LogsFolder**: Path to the folder where log files will be stored (default: `.\logs`).

## CSV Configuration

The module is driven by a CSV file that defines the operations to be performed.

### Required Fields

| Field                | Description                                      | Required For      |
| -------------------- | ------------------------------------------------ | ----------------- |
| `Operation_ID`       | A unique identifier for the operation.           | All               |
| `Type`               | Deployment type (`AzurePaaS`, `AzureMI`, `AzureIaaS`). | All               |
| `Database_Name`      | The name of the database.                        | All               |
| `Local_Folder`       | Local folder for temporary files (on the machine running the script or the remote IaaS server). | All               |
| `Storage_Account`    | The name of the Azure Storage account.           | All               |
| `Storage_Container`  | The name of the storage container.               | All               |
| `Storage_Access_Key` | The access key for the storage account.          | All               |
| `SRC_server`         | The name of the source server.                   | Export            |
| `SRC_SQL_Admin`      | The username for the source SQL admin.           | Export            |
| `SRC_SQL_Password`   | The password for the source SQL admin.           | Export            |
| `DST_server`         | The name of the destination server.              | Import            |
| `DST_SQL_Admin`      | The username for the destination SQL admin.      | Import            |
| `DST_SQL_Password`   | The password for the destination SQL admin.      | Import            |
| `PS_User`            | The username for PowerShell Remoting.            | `AzureIaaS`       |
| `PS_Password`        | The password for PowerShell Remoting.            | `AzureIaaS`       |
| `Export_Action`      | Enable the export operation (`true`/`false`).    | Optional          |
| `Import_Action`      | Enable the import operation (`true`/`false`).    | Optional          |
| `Remove_Tempfile`    | Clean up temporary files after the operation (`true`/`false`). | Optional          |

## Example CSV

```csv
Operation_ID,Type,SRC_server,SRC_SQL_Admin,SRC_SQL_Password,DST_server,DST_SQL_Admin,DST_SQL_Password,Database_Name,Local_Folder,Storage_Account,Storage_Container,Storage_Access_Key,Export_Action,Import_Action,Remove_Tempfile,PS_User,PS_Password
001,AzureMI,sqlmi-source.1234abcd,sqladmin,password123,sqlmi-target.5678efgh,sqladmin,password123,AdventureWorks,C:\Temp,mystorageacct,mycontainer,storagekey123==,True,True,False,,
002,AzurePaaS,sql-source,sqladmin,password123,sql-target,sqladmin,password123,WideWorld,C:\Temp,mystorageacct,mycontainer,storagekey123==,True,True,False,,
003,AzureIaaS,iaas-vm-source,sqladmin,password123,iaas-vm-target,sqladmin,password123,LegacyDB,D:\SQLBackups,mystorageacct,mycontainer,storagekey123==,True,True,True,vmadmin,vmpassword123
```

## Prerequisites

- PowerShell 5.1 or later.
- **Az.Storage** PowerShell module.
- **SqlPackage.exe** (part of SQL Server Data Tools - SSDT).
- **PowerShell Remoting (WinRM)** must be configured on both the control machine and the target IaaS VMs for `AzureIaaS` operations.
- Write access to the local temporary folder.
- Network access to source/destination SQL servers and Azure Storage.

### Installation

```powershell
# Install the Azure Storage module
Install-Module -Name Az.Storage -Scope CurrentUser -Force -Repository PSGallery

# To enable PowerShell Remoting (run on all machines)
Enable-PSRemoting -Force
```

## Operation Flow

1.  **Initialization & Validation**:
    -   The script checks for prerequisites like `SqlPackage.exe` and the `Az.Storage` module.
    -   It validates the CSV file, ensuring all required fields for the specified operations are present.
    -   It performs pre-flight checks to test connectivity to SQL servers and Azure Storage.

2.  **Export** (if `Export_Action` is `true`):
    -   **AzurePaaS/AzureMI**: Exports the database to a `.bacpac` file locally, then uploads it to Azure Storage.
    -   **AzureIaaS**: Executes a `BACKUP DATABASE` command remotely on the source VM to create a `.bak` file. This file is then copied from the VM to the local machine and uploaded to Azure Storage.

3.  **Import** (if `Import_Action` is `true`):
    -   The script finds the latest relevant backup file (`.bacpac` or `.bak`) in Azure Storage based on the `Operation_ID` and `Database_Name`.
    -   The backup file is downloaded from storage to a local temporary path.
    -   **AzurePaaS/AzureMI**: Imports the database from the `.bacpac` file. For Managed Instance, it can also restore from a `.bak` file by first uploading it to storage and then using `RESTORE DATABASE FROM URL`.
    -   **AzureIaaS**: The downloaded backup file is copied to the destination VM, and a `RESTORE DATABASE` command is executed remotely.

4.  **Cleanup**:
    -   If `Remove_Tempfile` is `true`, temporary backup files are deleted from the local machine and/or remote VMs after the operation.

## Logging

The module generates detailed logs for each session and operation in the specified logs folder:
-   **Session Log**: `session_YYYYMMDD_HHMMSS.log` - Contains a high-level summary of the entire script execution.
-   **Operation Log**: `{Operation_ID}_{Database_Name}_YYYYMMDD_HHMMSS.log` - Contains detailed, step-by-step logs for each individual database operation.

## Key Functions

-   `Export-DatabaseOperation`: Orchestrates the export process.
-   `Import-DatabaseOperation`: Orchestrates the import process.
-   `Export-SqlDatabaseToBacpac`: Exports a database to a `.bacpac` file using `SqlPackage.exe`.
-   `Export-SqlDatabaseToBak`: Creates a `.bak` file using a remote SQL command (for IaaS).
-   `Import-BacpacToSqlDatabase` / `Import-BacpacToSqlManagedInstance`: Imports a `.bacpac` file.
-   `Import-BakToSqlDatabase`: Restores a database from a `.bak` file, supporting both local and remote (URL) restores.
-   `Copy-FileToRemote` / `Copy-FileFromRemote`: Handles file transfers to and from IaaS VMs.
-   `Test-Prerequisites`, `Test-SqlServerAccess`, `Test-StorageAccess`: Perform validation and pre-flight checks.

## Limitations

-   Requires a Windows environment with PowerShell 5.1+.
-   Operations are single-threaded and processed sequentially.
-   Temporary files require sufficient local disk space (and on remote VMs for IaaS).

## Best Practices

1.  Use unique `Operation_ID`s for each distinct migration task to ensure correct backup files are used.
2.  Test the process with smaller, non-production databases first.
3.  Ensure adequate disk space is available in the `Local_Folder` on all relevant machines.
4.  Review the operation logs carefully to monitor status and troubleshoot failures.
5.  In a production environment, use secure methods for managing credentials, such as Azure Key Vault, instead of storing them in the CSV.
6.  Regularly rotate storage account keys and update the CSV file accordingly.

## Support

For issues or questions, please refer to the following:
-   Check the session and operation log files for detailed error messages.
-   Verify the CSV configuration, ensuring all paths, names, and credentials are correct.
-   Ensure all prerequisites are met and services (SQL Server, Storage, WinRM) are accessible.
-   Contact: [Fabrice Semti] - [fsemti@linkfinancial.eu or fabrice.semti@gmail.com]
