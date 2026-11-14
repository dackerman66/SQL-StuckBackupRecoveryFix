/* ============================================================================
   SQL Server: Fix a database stuck in "(Restoring...)"
   ----------------------------------------------------------------------------
   Run each step separately in SSMS, in order. Read the notes before each one.
   Replace these placeholders throughout:
       YourDbName             -> the name of the stuck database
       C:\Path\To\Backup.bak  -> the full path to your .bak file
   ============================================================================ */


/* ----------------------------------------------------------------------------
   STEP 1: Is a restore still running?
   If this returns a row, the restore is still in progress. WAIT for it.
   If it returns nothing, continue to Step 2.
---------------------------------------------------------------------------- */
SELECT session_id,
       command,
       percent_complete,
       estimated_completion_time / 60000 AS est_minutes_left
FROM sys.dm_exec_requests
WHERE command LIKE 'RESTORE%';


/* ----------------------------------------------------------------------------
   STEP 2: Is the database part of log shipping, mirroring, or an
   Availability Group?
   Secondaries in those setups are SUPPOSED to stay in Restoring.
   If your database appears in any result below, STOP: running WITH RECOVERY
   will break the HA relationship.
   "Invalid object" errors just mean the feature isn't set up; that's fine.
---------------------------------------------------------------------------- */
-- Log shipping secondary?
SELECT secondary_database FROM msdb.dbo.log_shipping_secondary_databases;

-- Mirroring?
SELECT DB_NAME(database_id) AS db, mirroring_role_desc
FROM sys.database_mirroring
WHERE mirroring_guid IS NOT NULL;

-- Availability Group?
SELECT DB_NAME(database_id) AS db FROM sys.dm_hadr_database_replica_states;


/* ----------------------------------------------------------------------------
   STEP 3: Try bringing it online.
   This works when the last restore simply used WITH NORECOVERY.
   WARNING: once this succeeds, no further log backups can be applied.
---------------------------------------------------------------------------- */
RESTORE DATABASE [YourDbName] WITH RECOVERY;

/* If Step 3 fails because the database is in use, run this instead: */
-- USE master;
-- ALTER DATABASE [YourDbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
-- RESTORE DATABASE [YourDbName] WITH RECOVERY;
-- ALTER DATABASE [YourDbName] SET MULTI_USER;

/* If Step 3 fails with:
       Msg 4333 "The database cannot be recovered because the log was not restored"
   an earlier restore was interrupted (often a bad or partial .bak download).
   Continue to Step 4 to redo the restore from the full backup. */


/* ----------------------------------------------------------------------------
   STEP 4: Find which backup file was used.
   restore_type: D = full, I = differential, L = log
---------------------------------------------------------------------------- */
SELECT TOP 10
    rh.restore_date,
    rh.restore_type,
    rh.[replace],
    rh.[recovery],
    rh.user_name,
    bmf.physical_device_name
FROM msdb.dbo.restorehistory rh
JOIN msdb.dbo.backupset bs         ON rh.backup_set_id = bs.backup_set_id
JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
WHERE rh.destination_database_name = 'YourDbName'
ORDER BY rh.restore_date DESC;

/* TIP: If the .bak came from a download (SFTP, etc.), re-download it in
   BINARY mode and confirm the file size matches the source before Step 5. */


/* ----------------------------------------------------------------------------
   STEP 5: Verify the backup file is readable.
   The line that matters is: "The backup set on file 1 is valid."
   Warnings about paths that don't exist (from the server where the backup was
   made) are normal and can be ignored.
---------------------------------------------------------------------------- */
RESTORE VERIFYONLY FROM DISK = 'C:\Path\To\Backup.bak';


/* ----------------------------------------------------------------------------
   STEP 6: Restore from the full backup and bring it online.
   REPLACE overwrites the stuck database. Don't close the query window while
   this runs, or the restore will stop partway.
---------------------------------------------------------------------------- */
USE master;
RESTORE DATABASE [YourDbName]
FROM DISK = 'C:\Path\To\Backup.bak'
WITH REPLACE, RECOVERY, STATS = 10;

ALTER DATABASE [YourDbName] SET MULTI_USER;

/* If Step 6 errors about a directory lookup or invalid path, the backup's
   original file locations don't exist here. Get the details with: */
-- Where the database's files live on this server now:
-- SELECT name AS logical_name, physical_name
-- FROM sys.master_files WHERE database_id = DB_ID('YourDbName');

-- Logical file names inside the backup:
-- RESTORE FILELISTONLY FROM DISK = 'C:\Path\To\Backup.bak';

/* ...then add a MOVE clause for each file: */
-- RESTORE DATABASE [YourDbName]
-- FROM DISK = 'C:\Path\To\Backup.bak'
-- WITH REPLACE, RECOVERY, STATS = 10,
--      MOVE 'logical_data_name' TO 'D:\SQLData\YourDbName.mdf',
--      MOVE 'logical_log_name'  TO 'D:\SQLLogs\YourDbName_log.ldf';


/* ----------------------------------------------------------------------------
   STEP 7: Confirm it's back.
   You should see ONLINE and MULTI_USER. Refresh the Databases folder in SSMS.
---------------------------------------------------------------------------- */
SELECT name, state_desc, user_access_desc
FROM sys.databases
WHERE name = 'YourDbName';
