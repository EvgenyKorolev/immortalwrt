#!/bin/sh
# Mesh topology monitoring agent

NODE_HOSTNAME=$(uci get system.@system[0].hostname)
TIMESTAMP=$(date +%s)

# Generating traffic to populate mpath
MY_IP=$(ip -4 addr show br-lan | awk '/inet / {print $2}' | cut -d/ -f1)
NEIGHBOR_IP=$(ip neigh show dev br-lan | awk '/192\.168\.5\./ && !/FAILED/ && !/INCOMPLETE/ {print $1}' | grep -v "$MY_IP" | head -1)

if [ -n "$NEIGHBOR_IP" ]; then
    ping -c 2 -W 1 "$NEIGHBOR_IP" >/dev/null 2>&1
fi

MESH_IFACES="phy0-mesh0 phy1-mesh0"
PEERS_JSON=""
PATHS_JSON=""

for MESH_IF in $MESH_IFACES; do
    # Checking whether the interface exists
    if ! iw dev $MESH_IF info >/dev/null 2>&1; then
        continue
    fi

    # Parsing the station for the current interface
    STATION_DUMP=$(iw dev $MESH_IF station dump 2>/dev/null)
    
    MAC=$(echo "$STATION_DUMP" | awk '/^Station / {print $2; exit}')
    SIGNAL=$(echo "$STATION_DUMP" | awk '/^[[:space:]]*signal:/ {print $2; exit}')
    PLINK=$(echo "$STATION_DUMP" | awk '/^[[:space:]]*mesh plink:/ {print $3; exit}')
    THROUGHPUT=$(echo "$STATION_DUMP" | awk '/^[[:space:]]*expected throughput:/ {print $3; exit}' | sed 's/Mbps//')
    METRIC=$(echo "$STATION_DUMP" | awk '/^[[:space:]]*mesh airtime link metric:/ {print $5; exit}')

    # Add the peer to the JSON (if found)
    if [ -n "$MAC" ]; then
        [ -n "$PEERS_JSON" ] && PEERS_JSON="$PEERS_JSON,"
        PEERS_JSON="${PEERS_JSON}{\"mac\":\"$MAC\",\"signal\":$SIGNAL,\"plink\":\"$PLINK\",\"throughput\":$THROUGHPUT,\"metric\":$METRIC,\"interface\":\"$MESH_IF\"}"
    fi

    # Parsing mpath for the current interface
    MPATH=$(iw dev $MESH_IF mpath dump 2>/dev/null | awk 'NR>1 && NF>=11 {
        printf "{\"dest\":\"%s\",\"next_hop\":\"%s\",\"metric\":%s,\"hop_count\":%s,\"interface\":\"'"$MESH_IF"'\"}", $1, $2, $5, $11
    }' | sed 's/}{/},{/g')

    if [ -n "$MPATH" ]; then
        [ -n "$PATHS_JSON" ] && PATHS_JSON="$PATHS_JSON,$MPATH" || PATHS_JSON="$MPATH"
    fi
done

# Constructing JSON
JSON_DATA=$(cat <<EOF
{
  "node_id": "$NODE_HOSTNAME",
  "timestamp": $TIMESTAMP,
  "mesh_peers": [$PEERS_JSON],
  "mesh_paths": [$PATHS_JSON]
}
EOF
)

# Output to the console (for debugging)
echo "$JSON_DATA"

# Sending to the collector (if curl is installed)
if command -v curl >/dev/null 2>&1; then
    curl -s -X POST -H "Content-Type: application/json" -d "$JSON_DATA" "$COLLECTOR_URL" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "[OK] Sent to collector" >&2
    else
        echo "[ERROR] Failed to send to collector" >&2
    fi
elif command -v wget >/dev/null 2>&1; then
    # Alternative using wget (if curl is unavailable)
    echo "$JSON_DATA" | wget --header="Content-Type: application/json" --post-data="$(cat)" -q -O - "$COLLECTOR_URL" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "[OK] Sent to collector (wget)" >&2
    else
        echo "[ERROR] Failed to send to collector (wget)" >&2
    fi
else
    echo "[WARN] Neither curl nor wget found, data not sent" >&2
fi