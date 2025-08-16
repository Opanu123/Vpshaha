#!/bin/bash
set -e

mkdir -p links ~/.config/playit

# ------------------------------
# Restore Playit config if exists
# ------------------------------
aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/playit.toml ~/.config/playit/playit.toml || echo "[Playit] No saved config yet"

# ------------------------------
# Restore previous claim link
# ------------------------------
if [ ! -f links/playit_claim.txt ]; then
    aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/playit_claim.txt links/playit_claim.txt || echo "[Playit] No saved claim link yet"
fi

# ------------------------------
# Ensure Playit agent binary exists
# ------------------------------
AGENT_BIN="./playit-linux-amd64"
if [ ! -f "$AGENT_BIN" ]; then
    wget -q https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64 -O "$AGENT_BIN"
    chmod +x "$AGENT_BIN"
fi

# ------------------------------
# Claim new tunnel if config missing
# ------------------------------
if [ ! -f ~/.config/playit/playit.toml ]; then
    echo "[Playit] Generating new claim URL..."
    CLAIM_URL=$($AGENT_BIN claim generate | tail -n1)
    echo "[Playit] Open this in browser to claim: $CLAIM_URL"
    echo "$CLAIM_URL" > links/playit_claim.txt

    # Wait until you claim in browser manually
    echo "[Playit] Waiting 30s for manual claim..."
    sleep 30

    echo "[Playit] Exchanging claim URL..."
    $AGENT_BIN claim exchange $CLAIM_URL
    echo "[Playit] Claim exchange done."

    # Backup .toml and claim link
    aws --endpoint-url=https://s3.filebase.com s3 cp ~/.config/playit/playit.toml s3://$FILEBASE_BUCKET/playit.toml || echo "[Playit] Backup .toml failed"
    aws --endpoint-url=https://s3.filebase.com s3 cp links/playit_claim.txt s3://$FILEBASE_BUCKET/playit_claim.txt || echo "[Playit] Backup claim link failed"
fi

# ------------------------------
# Start Playit agent
# ------------------------------
pkill -f playit-linux-amd64 || true
nohup $AGENT_BIN > playit.log 2>&1 &

# ------------------------------
# Background loop: tmate SSH refresh
# ------------------------------
(
while true; do
    pkill tmate || true
    tmate -S /tmp/tmate.sock new-session -d
    tmate -S /tmp/tmate.sock wait tmate-ready 30 || true
    TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}')
    echo "$TMATE_SSH" > links/ssh.txt
    git fetch origin main
    git reset --hard origin/main
    git add links/ssh.txt
    git commit -m "Updated SSH link $(date -u)" || true
    git push origin main || true
    sleep 900
done
) &

# ------------------------------
# Main loop: Minecraft backup + Playit config backup
# ------------------------------
LOOP=0
while true; do
    if (( LOOP % 2 == 0 )); then
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
        fi

        # Backup Playit config
        if [ -f ~/.config/playit/playit.toml ]; then
            aws --endpoint-url=https://s3.filebase.com s3 cp ~/.config/playit/playit.toml s3://$FILEBASE_BUCKET/playit.toml || echo "[Playit] Backup failed"
        fi
    fi
    LOOP=$((LOOP + 1))
    sleep 900
done
