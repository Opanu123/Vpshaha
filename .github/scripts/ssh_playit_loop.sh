#!/bin/bash
set -e

# -------------------------
# Git Setup
# -------------------------
git config --global user.name "Auto Bot"
git config --global user.email "auto@bot.com"
mkdir -p links

git pull --rebase origin main || true

# -------------------------
# Playit Setup
# -------------------------
mkdir -p ~/.config/playit
PLAYIT_FILE=~/.config/playit/.playit.toml

# Download latest Playit agent
curl -L -o playit https://github.com/playit-cloud/playit-agent/releases/latest/download/playit_linux_amd64
chmod +x playit

# Try to restore .playit.toml from Filebase
aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/.playit.toml $PLAYIT_FILE 2>/dev/null || true

# If it doesn't exist, claim a new tunnel
if [ ! -f "$PLAYIT_FILE" ]; then
    echo "[Playit] .playit.toml not found. Claiming new tunnel..."
    nohup ./playit &
    sleep 5
    ./playit claim --yes
    sleep 5
    # Upload new .playit.toml to Filebase
    aws --endpoint-url=https://s3.filebase.com s3 cp $PLAYIT_FILE s3://$FILEBASE_BUCKET/.playit.toml
    echo "[Playit] New tunnel claimed and uploaded to Filebase."
else
    echo "[Playit] Restored .playit.toml from Filebase."
    nohup ./playit &
fi

echo "[Playit] Agent started with config $(cat $PLAYIT_FILE 2>/dev/null || echo 'not found')"

# -------------------------
# Loop: tmate + backup
# -------------------------
LOOP=0
while true; do
    echo "[Loop] Starting iteration $LOOP at $(date -u)"

    # Kill old tmate
    pkill tmate || true

    # Start new tmate session
    tmate -S /tmp/tmate.sock new-session -d
    sleep 5
    TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}')
    echo "$TMATE_SSH" > links/ssh.txt

    git pull --rebase origin main || true
    git add links/ssh.txt
    git commit -m "Updated SSH link $(date -u)" || true
    git push origin main || true

    echo "[SSH] New SSH link pushed: $TMATE_SSH"

    # Backup every 30 mins (every 2 loops)
    if (( LOOP % 2 == 0 )); then
        echo "[Backup] Starting backup at $(date -u)"

        # Server backup
        cd server || mkdir -p server && cd server
        zip -r ../mcbackup.zip . >/dev/null
        cd ..

        # Upload backup with retry
        n=0
        until [ $n -ge 3 ]; do
            aws --endpoint-url=https://s3.filebase.com s3 cp mcbackup.zip s3://$FILEBASE_BUCKET/mcbackup.zip && break
            echo "[Backup] Upload failed. Retry in 30s..."
            sleep 30
            n=$((n+1))
        done
        [ $n -eq 3 ] && echo "[Backup] Failed to upload after 3 attempts!" || echo "[Backup] Uploaded server backup."

        # Upload Playit config
        aws --endpoint-url=https://s3.filebase.com s3 cp $PLAYIT_FILE s3://$FILEBASE_BUCKET/.playit.toml || echo "[Playit] Backup failed!"
        echo "[Playit] Config backed up to Filebase"
    fi

    LOOP=$((LOOP + 1))
    echo "[Loop] Sleeping 15 minutes..."
    sleep 900
done
