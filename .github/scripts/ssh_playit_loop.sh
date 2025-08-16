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
# Ensure Playit agent exists
# ------------------------------
AGENT_BIN="./playit-linux-amd64"
if [ ! -f "$AGENT_BIN" ]; then
    echo "[Playit] Downloading agent..."
    wget -q https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64 -O "$AGENT_BIN"
    chmod +x "$AGENT_BIN"
fi

# ------------------------------
# Restore Playit config if exists
# ------------------------------
mkdir -p ~/.config/playit
aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/playit.toml ~/.config/playit/playit.toml || echo "[Playit] No saved config yet"

# ------------------------------
# Restore Playit claim link (only if missing)
# ------------------------------
if [ ! -f links/playit_claim.txt ]; then
    aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/playit_claim.txt links/playit_claim.txt || echo "[Playit] No saved claim link yet"
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
    nohup $AGENT_BIN > playit.log 2>&1 &

    sleep 15  # wait for agent to start

    # ------------------------------
    # Claim new tunnel only if config missing
    # ------------------------------
    if [ ! -f ~/.config/playit/playit.toml ]; then
        echo "[Playit] No config found, claiming new tunnel..."
        $AGENT_BIN claim --yes
        sleep 5
        if [ -f ~/.config/playit/playit.toml ]; then
            aws --endpoint-url=https://s3.filebase.com s3 cp ~/.config/playit/playit.toml s3://$FILEBASE_BUCKET/playit.toml || echo "[Playit] Failed to backup .toml"
            echo "[Playit] Tunnel claimed and config uploaded."
        fi

        # Save claim URL from log
        claim_url=$(grep -o 'https://playit.gg/claim/[A-Za-z0-9]*' playit.log | head -n1)
        if [ -n "$claim_url" ]; then
            echo "$claim_url" > links/playit_claim.txt
            aws --endpoint-url=https://s3.filebase.com s3 cp links/playit_claim.txt s3://$FILEBASE_BUCKET/playit_claim.txt || echo "[Playit] Failed to backup claim link"
            echo "[Playit] Claim link saved: $claim_url"
        fi
    fi

    # ------------------------------
    # Backup Playit config every loop
    # ------------------------------
    if [ -f ~/.config/playit/playit.toml ]; then
        aws --endpoint-url=https://s3.filebase.com s3 cp ~/.config/playit/playit.toml s3://$FILEBASE_BUCKET/playit.toml || echo "[Playit] Backup failed"
    fi

    # ------------------------------
    # Start/Restart tmate SSH
    # ------------------------------
    pkill tmate || true
    tmate -S /tmp/tmate.sock new-session -d
    tmate -S /tmp/tmate.sock wait tmate-ready 30 || true
    sleep 5
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
