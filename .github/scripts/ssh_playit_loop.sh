#!/bin/bash
set -e

# ------------------------------
# Setup Git for SSH & links
# ------------------------------
git config --global user.name "Auto Bot"
git config --global user.email "auto@bot.com"
mkdir -p links

git fetch origin main
git reset --hard origin/main

# ------------------------------
# Restore Playit config if exists
# ------------------------------
mkdir -p ~/.config/playit
aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/playit.toml ~/.config/playit/playit.toml || echo "No saved config yet"

# ------------------------------
# Restore Playit claim link (only if missing)
# ------------------------------
if [ ! -f links/playit_claim.txt ]; then
    aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/playit_claim.txt links/playit_claim.txt || echo "No saved claim link yet"
fi

# ------------------------------
# Loop forever
# ------------------------------
LOOP=0
while true; do
  echo "[INFO] Loop #$LOOP starting at $(date -u)"

  # ------------------------------
  # Start/Restart Playit agent
  # ------------------------------
  pkill -f playit-linux-amd64 || true

  TMP_BINARY="playit-linux-amd64.new"
  wget -q https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64 -O "$TMP_BINARY"
  chmod +x "$TMP_BINARY"
  mv "$TMP_BINARY" playit-linux-amd64

  nohup ./playit-linux-amd64 > playit.log 2>&1 &

  # Wait for Playit output
  sleep 15

  # ------------------------------
  # Detect and save claim link (ONLY ONCE)
  # ------------------------------
  if [ ! -s links/playit_claim.txt ]; then
      claim_url=$(grep -o 'https://playit.gg/claim/[A-Za-z0-9]*' playit.log | head -n 1)
      if [ -n "$claim_url" ]; then
          echo "$claim_url" > links/playit_claim.txt
          echo "[INFO] Claim link saved: $claim_url"

          # Upload once to Filebase
          aws --endpoint-url=https://s3.filebase.com s3 cp links/playit_claim.txt s3://$FILEBASE_BUCKET/playit_claim.txt || echo "Failed to backup claim link"
      fi
  else
      echo "[INFO] playit_claim.txt already exists. Skipping update."
  fi

  # ------------------------------
  # Save Playit config to Filebase
  # ------------------------------
  if [ -f ~/.config/playit/playit.toml ]; then
      cp ~/.config/playit/playit.toml .playit.toml
      aws --endpoint-url=https://s3.filebase.com s3 cp ~/.config/playit/playit.toml s3://$FILEBASE_BUCKET/playit.toml || echo "Failed to backup playit.toml"
  fi

  # ------------------------------
  # Start/Restart tmate SSH
  # ------------------------------
  pkill tmate || true
  tmate -S /tmp/tmate.sock new-session -d
  tmate -S /tmp/tmate.sock wait tmate-ready 30 || true
  sleep 3
  TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}')
  echo "$TMATE_SSH" > links/ssh.txt

  # ------------------------------
  # Push updated links to repo
  # ------------------------------
  git fetch origin main
  git reset --hard origin/main
  git add links/ssh.txt links/playit_claim.txt
  git commit -m "Updated SSH & Playit claim link $(date -u)" || true
  git push origin main || true

  # ------------------------------
  # Backup Minecraft server every 30 mins (every 2 loops)
  # ------------------------------
  if (( LOOP % 2 == 0 )); then
    echo "[Backup] Starting backup at $(date -u)"
    if [ -d server ]; then
      cd server
      zip -r ../mcbackup.zip . >/dev/null
      cd ..
      n=0
      until [ $n -ge 3 ]; do
        aws --endpoint-url=https://s3.filebase.com s3 cp mcbackup.zip s3://$FILEBASE_BUCKET/mcbackup.zip && break
        echo "[Backup] Upload failed. Retry in 30s..."
        sleep 30
        n=$((n+1))
      done
      echo "[Backup] Minecraft server backup done."
    fi
  fi

  LOOP=$((LOOP + 1))
  echo "[INFO] Sleeping 15 minutes before next refresh..."
  sleep 900
done
