#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# GAIA GATE PI — Turn this device into a living gate
# 
# The organism radiates. This gate absorbs. Pull, don't push.
# 
# Usage:
#   curl -sf http://192.168.4.244:8080/data/gaia-gate-pi.sh | bash
#
# Or from WAN:
#   curl -sfk https://primals.eco/data/gaia-gate-pi.sh | bash
# ═══════════════════════════════════════════════════════════════
set -e

EASTGATE_LAN="192.168.4.244"
FORGEJO="http://${EASTGATE_LAN}:3000"
GAIA_DATA="${HOME}/.local/share/gaia/data"
GAIA_BIN="${HOME}/.local/bin"

echo "═══════════════════════════════════════════"
echo "  GAIA GATE PI — Joining the organism"
echo "═══════════════════════════════════════════"
echo ""

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    aarch64|arm64) TARGET="aarch64-unknown-linux-musl" ;;
    x86_64)        TARGET="x86_64-unknown-linux-musl" ;;
    armv7l)        TARGET="armv7-unknown-linux-musleabihf" ;;
    *)             echo "Unknown arch: $ARCH"; exit 1 ;;
esac
echo "  Architecture: $ARCH → $TARGET"

# Create directories
mkdir -p "$GAIA_DATA" "$GAIA_BIN"

# Step 1: Pull the heart (verify connectivity)
echo ""
echo "[1/5] Pulling heart from eastGate..."
HEART=$(curl -sf "http://${EASTGATE_LAN}:8080/data/heart-pull.json" 2>/dev/null)
if [ -z "$HEART" ]; then
    HEART=$(curl -sfk "https://primals.eco/data/heart-pull.json" 2>/dev/null)
fi
if [ -z "$HEART" ]; then
    echo "  CANNOT reach eastGate! Aborting."
    exit 1
fi
echo "$HEART" > "$GAIA_DATA/heart-pull.json"
MOR=$(echo "$HEART" | python3 -c "import json,sys; print(json.load(sys.stdin)['heartbeat']['mor_pct'])" 2>/dev/null || echo "?")
echo "  Heart received — MOR ${MOR}%"

# Step 2: Clone the organism from Forgejo
echo ""
echo "[2/5] Cloning gaia-seed from Forgejo..."
if [ ! -d "$HOME/gaia-seed" ]; then
    git clone "${FORGEJO}/ecoPrimal/gaia-seed.git" "$HOME/gaia-seed" 2>/dev/null || \
    git clone "https://github.com/ecoPrimal/gaia-seed.git" "$HOME/gaia-seed"
    echo "  Seed cloned."
else
    cd "$HOME/gaia-seed" && git pull --no-edit 2>/dev/null
    echo "  Seed updated."
fi

# Step 3: Set up heart-pull cron
echo ""
echo "[3/5] Installing heart-pull cron..."
cat > /tmp/gaia-heart-pull.sh << 'HPULL'
#!/bin/bash
GAIA_DATA="${HOME}/.local/share/gaia/data"
mkdir -p "$GAIA_DATA"
HEART=$(curl -sf http://192.168.4.244:8080/data/heart-pull.json 2>/dev/null || curl -sfk https://primals.eco/data/heart-pull.json 2>/dev/null)
if [ -n "$HEART" ]; then
    echo "$HEART" > "$GAIA_DATA/heart-pull.json"
    curl -sf http://192.168.4.244:8080/data/heartbeat.json > "$GAIA_DATA/heartbeat.json" 2>/dev/null
    curl -sf http://192.168.4.244:8080/data/now.json > "$GAIA_DATA/now.json" 2>/dev/null
    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    MOR=$(echo "$HEART" | python3 -c "import json,sys; print(json.load(sys.stdin)['heartbeat']['mor_pct'])" 2>/dev/null || echo "?")
    echo "$TS pulled heart — MOR $MOR%" >> "$GAIA_DATA/heart-pull.log"
    tail -1000 "$GAIA_DATA/heart-pull.log" > "$GAIA_DATA/heart-pull.log.tmp" && mv "$GAIA_DATA/heart-pull.log.tmp" "$GAIA_DATA/heart-pull.log"
fi
HPULL
chmod +x /tmp/gaia-heart-pull.sh
sudo cp /tmp/gaia-heart-pull.sh /opt/gaia-heart-pull.sh 2>/dev/null || cp /tmp/gaia-heart-pull.sh "$GAIA_BIN/gaia-heart-pull.sh"

CRON_SCRIPT=$(which gaia-heart-pull.sh 2>/dev/null || echo "${GAIA_BIN}/gaia-heart-pull.sh")
[ -f /opt/gaia-heart-pull.sh ] && CRON_SCRIPT="/opt/gaia-heart-pull.sh"
EXISTING=$(crontab -l 2>/dev/null | grep -c "gaia-heart-pull")
if [ "$EXISTING" -eq 0 ]; then
    (crontab -l 2>/dev/null; echo "*/2 * * * * $CRON_SCRIPT") | crontab -
fi
echo "  Heart-pull cron active (every 2 min)"

# Step 4: Generate gate identity
echo ""
echo "[4/5] Generating gate identity..."
HOSTNAME=$(hostname)
GATE_ID=$(echo -n "${HOSTNAME}-$(date +%s)" | sha256sum | cut -c1-16)
cat > "$GAIA_DATA/gate-identity.json" << EOF
{
  "gate": "$HOSTNAME",
  "gate_id": "$GATE_ID",
  "arch": "$ARCH",
  "target": "$TARGET",
  "joined": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "eastgate": "$EASTGATE_LAN",
  "role": "gate-pi",
  "heart_pull": true
}
EOF
echo "  Gate: $HOSTNAME ($GATE_ID)"

# Step 5: Report in
echo ""
echo "[5/5] First heartbeat..."
/opt/gaia-heart-pull.sh 2>/dev/null || "$GAIA_BIN/gaia-heart-pull.sh" 2>/dev/null
echo "  $(tail -1 "$GAIA_DATA/heart-pull.log" 2>/dev/null || echo 'Heart beating')"

echo ""
echo "═══════════════════════════════════════════"
echo "  GATE ALIVE — $HOSTNAME is part of Gaia"
echo "═══════════════════════════════════════════"
echo ""
echo "  Heart-pull: every 2 minutes"
echo "  Data: $GAIA_DATA"
echo "  Seed: $HOME/gaia-seed"
echo ""
echo "  To see the heartbeat:"
echo "    cat $GAIA_DATA/heart-pull.log"
echo ""
echo "  To check organism state:"
echo "    cat $GAIA_DATA/heart-pull.json | python3 -m json.tool"
