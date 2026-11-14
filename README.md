# SQL-StuckBackupRecoveryFix

Step-by-step T-SQL for fixing a SQL Server database stuck in **(Restoring...)** after a backup restore.

## When to use this

Your database shows **(Restoring...)** in SSMS and won't come online, often after a scheduled or automated restore that was interrupted or used a bad/partial `.bak` file.

This is **not** for these similar-looking states:

- **In Recovery**: SQL Server is doing crash recovery after a restart. Let it finish; the SQL error log shows progress.
- **Recovery Pending**: usually missing/inaccessible files, a full disk, or permissions. Check the SQL error log.

## How to use

1. Open [`fix-stuck-restore.sql`](fix-stuck-restore.sql) in SSMS.
2. Replace `YourDbName` and `C:\Path\To\Backup.bak` with your values.
3. Run **one step at a time**, reading the notes in each step.

| Step | What it does |
|------|--------------|
| 1 | Checks whether a restore is still running (if so, wait) |
| 2 | Checks for log shipping / mirroring / Availability Groups (if so, stop) |
| 3 | Tries `RESTORE ... WITH RECOVERY` to bring it online |
| 4 | Finds the backup file the last restore used |
| 5 | Verifies the backup file with `RESTORE VERIFYONLY` |
| 6 | Re-restores from the full backup with `REPLACE, RECOVERY` |
| 7 | Confirms the database is `ONLINE` and `MULTI_USER` |

## Common error

```
Msg 4333: The database cannot be recovered because the log was not restored.
```

An earlier restore was interrupted. `WITH RECOVERY` alone won't fix it. Re-download the backup (in binary mode if using SFTP/FTP), verify it (Step 5), and restore it again (Step 6).

## ⚠️ Warnings

- `REPLACE` **overwrites** the existing database. Make sure that's what you want.
- Once `WITH RECOVERY` succeeds, you **cannot** apply further log backups.
- Do not run `WITH RECOVERY` on a log shipping, mirroring, or AG secondary unless you intend to break that relationship.
- Test on a non-production server first if you can. Use at your own risk.

## Recurring problem?

If databases keep getting stuck after a nightly restore, the root cause is usually the scheduled download-and-restore job (an incomplete download, or the job being killed mid-restore), not the databases themselves. Add a file-size check and `RESTORE VERIFYONLY` to the job before the restore runs.
