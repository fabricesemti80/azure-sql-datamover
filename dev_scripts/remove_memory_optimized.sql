USE [WideWorldImporters]; -- Default database name

-- Check what memory-optimized objects exist
SELECT 
    t.name AS table_name,
    t.durability_desc,
    fg.name AS filegroup_name
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id
INNER JOIN sys.data_spaces ds ON i.data_space_id = ds.data_space_id
INNER JOIN sys.filegroups fg ON ds.data_space_id = fg.data_space_id
WHERE t.is_memory_optimized = 1;

-- Check for memory-optimized filegroups
SELECT 
    name,
    type_desc,
    is_default
FROM sys.filegroups 
WHERE type_desc = 'MEMORY_OPTIMIZED_DATA_FILEGROUP';
