#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# POLARIS HEART SETUP — Run this on northGate to close the circuit
# The heart PULLS. The forge FIRES. The loop CLOSES.
# ═══════════════════════════════════════════════════════════════

set -e

GAIA_DATA="${HOME}/.local/share/gaia/data"
mkdir -p "$GAIA_DATA"

echo "Installing Polaris heart-pull..."

# Heart-pull script (same as sporeGate but with forge awareness)
cat > /opt/gaia-heart-pull.sh << 'SCRIPT'
#!/bin/bash
# Heart Pull — Polaris drinks from eastGate
# The 5090 IS the heart. The forge IS the circuit.

GAIA_DATA="${HOME}/.local/share/gaia/data"
mkdir -p "$GAIA_DATA"

# Pull the heart (LAN first, WAN fallback, Tor last resort)
HEART=""
for URL in \
    "http://192.168.4.244:8080/data/heart-pull.json" \
    "http://192.168.4.103:8080/data/heart-pull.json" \
    "https://primals.eco/data/heart-pull.json"; do
    HEART=$(curl -sfk "$URL" 2>/dev/null)
    [ -n "$HEART" ] && break
done

if [ -n "$HEART" ]; then
    echo "$HEART" > "$GAIA_DATA/heart-pull.json"
    curl -sf http://192.168.4.244:8080/data/heartbeat.json > "$GAIA_DATA/heartbeat.json" 2>/dev/null
    curl -sf http://192.168.4.244:8080/data/now.json > "$GAIA_DATA/now.json" 2>/dev/null
    
    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    MOR=$(echo "$HEART" | python3 -c "import json,sys; print(json.load(sys.stdin)['heartbeat']['mor_pct'])" 2>/dev/null || echo "?")
    echo "$TS pulled heart — MOR $MOR%" >> "$GAIA_DATA/heart-pull.log"
    tail -1000 "$GAIA_DATA/heart-pull.log" > "$GAIA_DATA/heart-pull.log.tmp" && mv "$GAIA_DATA/heart-pull.log.tmp" "$GAIA_DATA/heart-pull.log"
fi

# FORGE CIRCUIT: If we have GPU work to do, check for it
if command -v nvidia-smi &>/dev/null; then
    GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null || echo "?")
    GPU_UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo "?")
    
    # Report forge state back to eastGate
    FORGE_STATE=$(cat << EOF
{"ts":"$TS","gate":"northGate","role":"forge","gpu_temp":$GPU_TEMP,"gpu_util":$GPU_UTIL,"heart_mor":"$MOR"}
EOF
)
    echo "$FORGE_STATE" > "$GAIA_DATA/forge-state.json"
fi
SCRIPT
chmod +x /opt/gaia-heart-pull.sh

# Test
/opt/gaia-heart-pull.sh
echo "First pull:"
cat "$GAIA_DATA/heart-pull.log"

# Install cron
(crontab -l 2>/dev/null | grep -v gaia-heart-pull; echo "*/2 * * * * /opt/gaia-heart-pull.sh") | crontab -
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  HEART LOOP CLOSED"
echo "  Polaris is drinking. The forge circuit is live."
echo "  Pull interval: every 2 minutes"
echo "  LAN: http://192.168.4.244:8080/data/heart-pull.json"
echo "  WAN: https://primals.eco/data/heart-pull.json"
echo "═══════════════════════════════════════════════════════"
