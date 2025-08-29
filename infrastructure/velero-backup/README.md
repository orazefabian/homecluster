# Usage

## Manual Backup

To manually trigger a backup:

```bash
velero backup create manual-backup-$(date +%s) --include-namespaces halo
```

## Restore from Backup

To restore from a backup:

```bash
velero restore create --from-backup backup-name
```

## List Backups

```bash
velero backup get
```

## Monitoring

You can monitor backup progress with:

```bash
velero backup describe backup-name
velero backup logs backup-name
```
