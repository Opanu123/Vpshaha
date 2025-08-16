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
# Ensure Playit agent binary exists
# ------------------------------
AGENT_BIN="./playit-linux-amd64"
if [ ! -f "$AGENT_BIN" ]; then
    echo "[Playit] Downloading agent..."
    wget -q https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64 -O "$AGENT_BIN"
    chmod +x "$AGENT_BIN"
fi

# ------------------------------
# Restore Playit config
# ------------------------------
mkdir -p ~/.config/playit
aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/playit.toml ~/.config/playit/playit.toml || echo "[Playit] No saved config yet"

# ------------------------------
# Restore previous claim link
# ------------------------------
if [ ! -f links/playit_claim.txt ]; then
    aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/playit_claim.txt links/playit_claim.txt || echo "[Playit] No saved claim link yet"
fi

# ------------------------------
# Start Playit agent
# ------------------------------
pkill -f playit-linux-amd64 || true
nohup $AGENT_BIN > playit.log 2>&1 &
echo "[Playit] Agent started"

# ------------------------------
# Background loop: Refresh tmate SSH every 15 minutes
# ------------------------------
(
while true; do
    echo "[TMATE] Refreshing SSH link at $(date -u)"
    pkill tmate || true
    tmate -S /tmp/tmate.sock new-session -d
    tmate -S /tmp/tmate.sock wait tmate-ready 30 || true
    sleep 5
    TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}')
    echo "$TMATE_SSH" > links/ssh.txt

    git fetch origin main
    git reset --hard origin/main
    git add links/ssh.txt
    git commit -m "Updated SSH link $(date -u)" || true
    git push origin main || true

    sleep 900  # 15 minutes
done
) &

# ------------------------------
# Main loop: Backup Minecraft server + Playit config every 30 minutes
# ------------------------------
LOOP=0
while true; do
    if (( LOOP % 2 == 0 )); then
        echo "[Backup] Starting backup at $(date -u)"

        # Backup Minecraft server
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

        # Backup Playit config
        if [ -f ~/.config/playit/playit.toml ]; then
            aws --endpoint-url=https://s3.filebase.com s3 cp ~/.config/playit/playit.toml s3://$FILEBASE_BUCKET/playit.toml || echo "[Playit] Backup failed"
        fi
    fi

    LOOP=$((LOOP + 1))
    sleep 900  # 15 minutes (backups happen every 2 loops = 30 mins)
done
