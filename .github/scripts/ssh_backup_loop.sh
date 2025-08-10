#!/bin/bash
set -e

git config --global user.name "Auto Bot"
git config --global user.email "auto@bot.com"
mkdir -p links

git pull --rebase origin main || true

LOOP=0
while true; do
  pkill tmate || true

  tmate -S /tmp/tmate.sock new-session -d
  sleep 5
  TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}')

  mkdir -p links
  echo "$TMATE_SSH" > links/ssh.txt

  git pull --rebase origin main || true
  git add links/ssh.txt
  git commit -m "Updated SSH link $(date -u)" || true
  git push origin main || true

  echo "[SSH] New SSH link pushed at $(date -u): $TMATE_SSH"

  if (( LOOP % 2 == 0 )); then
    echo "[Backup] Starting backup at $(date -u)"

    # Minecraft backup
    if [ -d server ]; then
      cd server || exit 1
      zip -r ../mcbackup.zip . >/dev/null
      cd ..
    else
      echo "Minecraft server folder 'server' not found!"
    fi

    # Prepare tailscale backup folder with correct permissions
    sudo mkdir -p /tmp/tailscale_backup_data
    sudo cp /var/lib/tailscale/tailscaled.state /tmp/tailscale_backup_data/ || echo "No tailscaled.state to backup"
    sudo chown -R $USER:$USER /tmp/tailscale_backup_data

    cd /tmp
    zip -r full_backup.zip tailscale_backup_data || echo "No tailscale data to zip"

    # Upload Minecraft backup with retries
    n=0
    until [ $n -ge 3 ]; do
      aws --endpoint-url=https://s3.filebase.com s3 cp mcbackup.zip s3://$FILEBASE_BUCKET/mcbackup.zip && break
      echo "[Backup] Minecraft upload failed. Retry in 30s..."
      sleep 30
      n=$((n+1))
    done

    if [ $n -eq 3 ]; then
      echo "[Backup] Failed to upload Minecraft backup after 3 attempts!"
    else
      echo "[Backup] Uploaded Minecraft backup to Filebase at $(date -u)"
    fi

    # Upload Tailscale backup with retries
    m=0
    until [ $m -ge 3 ]; do
      aws --endpoint-url=https://s3.filebase.com s3 cp full_backup.zip s3://$FILEBASE_BUCKET/tailscaled_backup.zip && break
      echo "[Backup] Tailscale upload failed. Retry in 30s..."
      sleep 30
      m=$((m+1))
    done

    if [ $m -eq 3 ]; then
      echo "[Backup] Failed to upload Tailscale backup after 3 attempts!"
    else
      echo "[Backup] Uploaded Tailscale backup to Filebase at $(date -u)"
    fi
  fi

  LOOP=$((LOOP + 1))
  echo "[Loop] Sleeping 15 minutes before next refresh..."
  sleep 900
done
