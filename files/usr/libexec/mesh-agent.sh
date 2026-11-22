#!/bin/sh
# Агент мониторинга меш-топологии

MESH_IF="phy1-mesh0"
NODE_HOSTNAME=$(uci get system.@system[0].hostname)
TIMESTAMP=$(date +%s)

# Генерируем трафик, чтобы наполнить mpath
MY_IP=$(ip -4 addr show br-lan | awk '/inet / {print $2}' | cut -d/ -f1)
NEIGHBOR_IP=$(ip neigh show dev br-lan | awk '/192\.168\.5\./ && !/FAILED/ && !/INCOMPLETE/ {print $1}' | grep -v "$MY_IP" | head -1)

if [ -n "$NEIGHBOR_IP" ]; then
    ping -c 2 -W 1 "$NEIGHBOR_IP" >/dev/null 2>&1
fi

# Парсинг станции
STATION_DUMP=$(iw dev $MESH_IF station dump 2>/dev/null)

MAC=$(echo "$STATION_DUMP" | awk '/^Station / {print $2; exit}')
SIGNAL=$(echo "$STATION_DUMP" | awk '/^[[:space:]]*signal:/ {print $2; exit}')
PLINK=$(echo "$STATION_DUMP" | awk '/^[[:space:]]*mesh plink:/ {print $3; exit}')
THROUGHPUT=$(echo "$STATION_DUMP" | awk '/^[[:space:]]*expected throughput:/ {print $3; exit}' | sed 's/Mbps//')
METRIC=$(echo "$STATION_DUMP" | awk '/^[[:space:]]*mesh airtime link metric:/ {print $5; exit}')

# Парсинг mpath
MPATH_JSON=$(iw dev $MESH_IF mpath dump 2>/dev/null | awk 'NR>1 && NF>=11 {
    printf "{\"dest\":\"%s\",\"next_hop\":\"%s\",\"metric\":%s,\"hop_count\":%s}", $1, $2, $5, $11
}' | sed 's/}{/},{/g')

# Итоговый JSON
cat <<EOF
{
  "node_id": "$NODE_HOSTNAME",
  "timestamp": $TIMESTAMP,
  "mesh_interface": "$MESH_IF",
  "mesh_peers": [
    {
      "mac": "$MAC",
      "signal": $SIGNAL,
      "plink": "$PLINK",
      "throughput": $THROUGHPUT,
      "metric": $METRIC
    }
  ],
  "mesh_paths": [$MPATH_JSON]
}
EOF