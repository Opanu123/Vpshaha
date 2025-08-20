#!/bin/bash
set -e

# Git setup
git config --global user.name "Auto Bot"
git config --global user.email "auto@bot.com"
mkdir -p links
git fetch origin main
git reset --hard origin/main

# Playit agent
AGENT_BIN="./playit-linux-amd64"
if [ ! -f "$AGENT_BIN" ]; then
    wget -q https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64 -O "$AGENT_BIN"
    chmod +x "$AGENT_BIN"
fi

# Restore Playit config
mkdir -p ~/.config/playit_gg
aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/playit.toml ~/.config/playit_gg/playit.toml || echo "[Playit] No saved config yet"

# Restore claim link
if [ ! -f links/playit_claim.txt ]; then
    aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/playit_claim.txt links/playit_claim.txt || echo "[Playit] No saved claim link yet"
fi

# Start Playit agent with 3 tunnels
pkill -f playit-linux-amd64 || true
nohup $AGENT_BIN \
  --tunnel "minecraft-bedrock:19132" \
  --tunnel "tcp:22" \
  --tunnel "tcp:7681" \
  > playit.log 2>&1 &
sleep 15

# Refresh tmate SSH every 15 minutes
(
while true; do
    pkill tmate || true
    rm -f /tmp/tmate.sock
    tmate -S /tmp/tmate.sock new-session -d
    tmate -S /tmp/tmate.sock wait tmate-ready 30 || true

    TMATE_SSH=""
    while [ -z "$TMATE_SSH" ]; do
        sleep 2
        TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}' || true)
    done

    echo "$TMATE_SSH" > links/ssh.txt
    echo "[INFO] Refreshed SSH: $TMATE_SSH"

    git fetch origin main
    git reset --hard origin/main
    git add links/ssh.txt
    git commit -m "Updated SSH link $(date -u)" || true
    git push origin main || true

    sleep 900
done
) &

# Backup Minecraft + Playit every 6 hours
while true; do
    echo "[Backup] Starting backup at $(date -u)"

    if [ -d server ]; then
        cd server
        zip -r ../mcbackup.zip . >/dev/null
        cd ..
        n=0
        until [ $n -ge 3 ]; do
            aws --endpoint-url=https://s3.filebase.com s3 cp mcbackup.zip s3://$FILEBASE_BUCKET/mcbackup.zip && break
            sleep 30
            n=$((n+1))
        done
        echo "[Backup] Minecraft server backup done."
    fi

    if [ -f ~/.config/playit_gg/playit.toml ]; then
        aws --endpoint-url=https://s3.filebase.com s3 cp ~/.config/playit_gg/playit.toml s3://$FILEBASE_BUCKET/playit.toml || echo "[Playit] Backup failed"
    fi

    echo "[INFO] Sleeping for 6 hours..."
    sleep 21600
done
