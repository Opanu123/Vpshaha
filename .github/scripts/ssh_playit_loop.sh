#!/bin/bash
set -e

# =========================
# Git Setup
# =========================
git config --global user.name "Auto Bot"
git config --global user.email "auto@bot.com"
mkdir -p links

# Initial pull to avoid push rejection
git pull --rebase origin main || true

# =========================
# Playit Setup
# =========================
AGENT_BIN="./playit-linux-amd64"

# Download Playit if missing
if [ ! -f "$AGENT_BIN" ]; then
  echo "[Playit] Downloading agent..."
  curl -L -o playit-linux-amd64 https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64
  chmod +x playit-linux-amd64
fi

# Restore .playit.toml from Filebase if available
mkdir -p ~/.config/playit
aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/playit.toml ~/.config/playit/playit.toml || true

# Start Playit agent
pkill -f playit-linux-amd64 || true
nohup $AGENT_BIN > playit.log 2>&1 &
sleep 10

# Claim if not already claimed
if [ ! -f ~/.config/playit/playit.toml ]; then
    echo "[Playit] No config found, claiming new tunnel..."
    claim_url=$($AGENT_BIN --claim-token 2>&1 | grep -o 'https://playit.gg/claim/[A-Za-z0-9]*' | head -n1)

    if [ -n "$claim_url" ]; then
        echo "$claim_url" > links/playit_claim.txt
        git add links/playit_claim.txt
        git commit -m "Playit claim link $(date -u)" || true
        git push origin main || true

        aws --endpoint-url=https://s3.filebase.com s3 cp links/playit_claim.txt s3://$FILEBASE_BUCKET/playit_claim.txt || true
        echo "[Playit] Claim link saved: $claim_url"
    else
        echo "[Playit] Failed to get claim URL, check logs."
    fi

    echo "[Playit] Waiting for you to claim at: $claim_url"
    for i in {1..60}; do
        if [ -f ~/.config/playit/playit.toml ]; then
            aws --endpoint-url=https://s3.filebase.com s3 cp ~/.config/playit/playit.toml s3://$FILEBASE_BUCKET/playit.toml || echo "[Playit] Failed to backup .toml"
            echo "[Playit] Tunnel claimed and config uploaded."
            break
        fi
        sleep 5
    done
fi

# =========================
# Main Loop
# =========================
LOOP=0
while true; do
  # Kill old tmate if exists
  pkill tmate || true

  # Start new tmate session
  tmate -S /tmp/tmate.sock new-session -d
  sleep 5
  TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}')

  echo "$TMATE_SSH" > links/ssh.txt

  # Git pull → add → commit → push
  git pull --rebase origin main || true
  git add links/ssh.txt
  git commit -m "Updated SSH link $(date -u)" || true
  git push origin main || true

  echo "[SSH] New SSH link pushed at $(date -u): $TMATE_SSH"

  # Backup every 30 mins (every 2 loops)
  if (( LOOP % 2 == 0 )); then
    echo "[Backup] Starting backup at $(date -u)"
    cd server || exit 1
    zip -r ../mcbackup.zip . >/dev/null
    cd ..

    # Upload with retry
    n=0
    until [ $n -ge 3 ]; do
      aws --endpoint-url=https://s3.filebase.com s3 cp mcbackup.zip s3://$FILEBASE_BUCKET/mcbackup.zip && break
      echo "[Backup] Upload failed. Retry in 30s..."
      sleep 30
      n=$((n+1))
    done

    if [ $n -eq 3 ]; then
      echo "[Backup] Failed to upload after 3 attempts!"
    else
      echo "[Backup] Uploaded to Filebase at $(date -u)"
    fi
  fi

  LOOP=$((LOOP + 1))
  echo "[Loop] Sleeping 15 minutes before next refresh..."
  sleep 900
done
