#!/usr/bin/env python3
"""
Kubernetes Secrets Backup Script for CronJob
Simplified version designed to run inside K8s cluster
"""

import os
import sys
import yaml
import subprocess
import argparse
from datetime import datetime
from pathlib import Path

def run_kubectl_command(command):
    """Execute kubectl command and return the output"""
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True, check=True)
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Error executing kubectl command: {e}")
        print(f"Command: {command}")
        print(f"Error output: {e.stderr}")
        return None

def get_all_secrets():
    """Get all secrets from all namespaces"""
    print("Fetching all secrets from cluster...")
    
    command = "kubectl get secrets --all-namespaces -o yaml"
    output = run_kubectl_command(command)
    
    if not output:
        print("Failed to fetch secrets")
        return []
    
    try:
        secrets_data = yaml.safe_load(output)
        return secrets_data.get('items', [])
    except yaml.YAMLError as e:
        print(f"Error parsing YAML output: {e}")
        return []

def should_skip_secret(secret_name, secret_type):
    """Check if secret should be skipped based on name or type"""
    skip_prefixes = [
        'default-token-',
        'sh.helm.release.',
        'longhorn-grpc-tls',
        'memberlist',
        'metallb-webhook-cert',
        'secrets-backup-'  # Skip our own backup job secrets
    ]
    
    skip_types = [
        'kubernetes.io/service-account-token',
        'helm.sh/release.v1'
    ]
    
    if secret_type in skip_types:
        return True
    
    for prefix in skip_prefixes:
        if secret_name.startswith(prefix):
            return True
    
    return False

def clean_secret_for_backup(secret):
    """Clean secret data for backup by removing runtime fields"""
    clean_secret = secret.copy()
    metadata = clean_secret.get('metadata', {})
    
    runtime_fields = [
        'uid', 'resourceVersion', 'generation', 'creationTimestamp', 
        'managedFields', 'selfLink'
    ]
    
    for field in runtime_fields:
        metadata.pop(field, None)
    
    annotations = metadata.get('annotations', {})
    annotations_to_remove = []
    for key in annotations:
        if key.startswith(('meta.helm.sh/', 'kubectl.kubernetes.io/')):
            annotations_to_remove.append(key)
    
    for key in annotations_to_remove:
        del annotations[key]
    
    if not annotations:
        metadata.pop('annotations', None)
    
    clean_secret.pop('status', None)
    return clean_secret

def cleanup_old_backups(backup_path, keep_count=5):
    """Keep only the most recent backup directories"""
    backup_dirs = []
    for item in backup_path.iterdir():
        if item.is_dir() and item.name.startswith('secrets_backup_'):
            backup_dirs.append(item)
    
    backup_dirs.sort(key=lambda x: x.name, reverse=True)
    
    # Remove old backups beyond keep_count
    for old_backup in backup_dirs[keep_count:]:
        print(f"Removing old backup: {old_backup.name}")
        import shutil
        shutil.rmtree(old_backup)

def main():
    parser = argparse.ArgumentParser(description="Backup Kubernetes secrets (K8s CronJob version)")
    parser.add_argument("backup_dir", help="Directory to store backup files")
    parser.add_argument("--namespace", "-n", action="append", help="Namespace(s) to backup")
    parser.add_argument("--keep-backups", type=int, default=5, help="Number of backup directories to keep (default: 5)")
    
    args = parser.parse_args()
    
    # Use service account token for authentication (mounted automatically in pod)
    print("Kubernetes Secrets Backup Tool (CronJob Version)")
    print(f"Backup directory: {args.backup_dir}")
    
    if args.namespace:
        print(f"Filtering namespaces: {', '.join(args.namespace)}")
    else:
        print("Backing up secrets from all namespaces")
    
    print("-" * 50)
    
    # Create backup directory
    backup_path = Path(args.backup_dir)
    backup_path.mkdir(parents=True, exist_ok=True)
    
    # Create timestamp subdirectory
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    timestamped_backup_dir = backup_path / f"secrets_backup_{timestamp}"
    timestamped_backup_dir.mkdir(exist_ok=True)
    
    secrets = get_all_secrets()
    
    if not secrets:
        print("No secrets found or failed to fetch secrets")
        sys.exit(1)
    
    backed_up_count = 0
    skipped_count = 0
    
    print(f"\nProcessing {len(secrets)} secrets...")
    
    for secret in secrets:
        metadata = secret.get('metadata', {})
        secret_name = metadata.get('name', 'unknown')
        namespace = metadata.get('namespace', 'default')
        secret_type = secret.get('type', 'unknown')
        
        # Apply namespace filter if specified
        if args.namespace and namespace not in args.namespace:
            continue
        
        # Check if we should skip this secret
        if should_skip_secret(secret_name, secret_type):
            print(f"  Skipping: {namespace}/{secret_name} (type: {secret_type})")
            skipped_count += 1
            continue
        
        # Clean the secret for backup
        clean_secret = clean_secret_for_backup(secret)
        
        # Create filename
        filename = f"{namespace}_{secret_name}.yaml"
        filepath = timestamped_backup_dir / filename
        
        try:
            with open(filepath, 'w') as f:
                yaml.dump(clean_secret, f, default_flow_style=False, sort_keys=True)
            print(f"  Backed up: {namespace}/{secret_name} -> {filename}")
            backed_up_count += 1
        except Exception as e:
            print(f"  Error backing up {namespace}/{secret_name}: {e}")
            continue
    
    print(f"\nBackup completed!")
    print(f"Secrets backed up: {backed_up_count}")
    print(f"Secrets skipped: {skipped_count}")
    print(f"Backup location: {timestamped_backup_dir}")
    
    # Create/update latest symlink
    latest_link = backup_path / "latest"
    if latest_link.exists() or latest_link.is_symlink():
        latest_link.unlink()
    latest_link.symlink_to(timestamped_backup_dir.name)
    print(f"Latest backup symlink: {latest_link}")
    
    # Cleanup old backups
    cleanup_old_backups(backup_path, args.keep_backups)
    
    print("Backup job completed successfully!")

if __name__ == "__main__":
    main()