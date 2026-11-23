#!/bin/sh
# Mesh topology monitoring agent

ENABLED=$(uci get belmax.mesh_monitor.enabled 2>/dev/null)
if [ "$ENABLED" != "1" ]; then
    exit 0
fi

COLLECTOR_URL=$(uci get belmax.mesh_monitor.collector_url 2>/dev/null)
INTERVAL=$(uci get belmax.mesh_monitor.interval 2>/dev/null)
INTERVAL=${INTERVAL:-30}

case "$COLLECTOR_URL" in
    http://*|https://*) ;;
    *) COLLECTOR_URL="http://$COLLECTOR_URL" ;;
esac

if [ -z "$COLLECTOR_URL" ]; then
    echo "[ERROR] Collector URL not configured" >&2
    exit 1
fi

NODE_HOSTNAME=$(uci get system.@system[0].hostname)
TIMESTAMP=$(date +%s)
MESH_IFACES="phy0-mesh0 phy1-mesh0"

# 1. Собираем собственные MAC-адреса меш-интерфейсов
LOCAL_MACS=""
for MESH_IF in $MESH_IFACES; do
    MAC=$(iw dev $MESH_IF info 2>/dev/null | awk '/addr/ {print $2}')
    if [ -n "$MAC" ]; then
        [ -n "$LOCAL_MACS" ] && LOCAL_MACS="$LOCAL_MACS,"
        LOCAL_MACS="${LOCAL_MACS}\"$MAC\""
    fi
done

# 2. Генерируем трафик для обновления mpath
MY_IP=$(ip -4 addr show br-lan | awk '/inet / {print $2}' | cut -d/ -f1)
NEIGHBOR_IP=$(ip neigh show dev br-lan | awk '/192\.168\.5\./ && !/FAILED/ && !/INCOMPLETE/ {print $1}' | grep -v "$MY_IP" | head -1)
[ -n "$NEIGHBOR_IP" ] && ping -c 2 -W 1 "$NEIGHBOR_IP" >/dev/null 2>&1

# 3. Парсим пиры
DUMP_STATIONS=""
for MESH_IF in $MESH_IFACES; do
    if iw dev $MESH_IF info >/dev/null 2>&1; then
        DUMP_STATIONS="${DUMP_STATIONS}
===INTERFACE:${MESH_IF}===
$(iw dev $MESH_IF station dump 2>/dev/null)"
    fi
done

PEERS_JSON=$(echo "$DUMP_STATIONS" | awk '
    /^===INTERFACE:/ { 
        split($0, a, ":"); split(a[2], b, "="); iface = b[1]; next 
    }
    /^Station / { 
        # Выводим предыдущую станцию, если все поля заполнены
        if (mac != "" && signal != "" && plink != "" && tp != "" && metric != "") {
            if (count > 0) printf ","
            printf "{\"peer_mac\":\"%s\",\"interface\":\"%s\",\"signal\":%s,\"plink\":\"%s\",\"throughput\":%s,\"metric\":%s}", mac, iface, signal, plink, tp, metric
            count++
        }
        mac=$2; signal=""; plink=""; tp=""; metric=""
        next 
    }
    /^[[:space:]]*signal:/ { signal=$2; next }
    /^[[:space:]]*mesh plink:/ { plink=$3; next }
    /^[[:space:]]*expected throughput:/ { gsub(/Mbps/,"",$3); tp=$3; next }
    /^[[:space:]]*mesh airtime link metric:/ { metric=$5; next }
    END {
        # Выводим последнюю станцию
        if (mac != "" && signal != "" && plink != "" && tp != "" && metric != "") {
            if (count > 0) printf ","
            printf "{\"peer_mac\":\"%s\",\"interface\":\"%s\",\"signal\":%s,\"plink\":\"%s\",\"throughput\":%s,\"metric\":%s}", mac, iface, signal, plink, tp, metric
        }
    }
')

# 4. Парсим пути (mpath)
DUMP_MPATH=""
for MESH_IF in $MESH_IFACES; do
    if iw dev $MESH_IF info >/dev/null 2>&1; then
        DUMP_MPATH="${DUMP_MPATH}
===INTERFACE:${MESH_IF}===
$(iw dev $MESH_IF mpath dump 2>/dev/null)"
    fi
done

PATHS_JSON=$(echo "$DUMP_MPATH" | awk '
    /^===INTERFACE:/ { 
        split($0, a, ":"); split(a[2], b, "="); iface = b[1]; next 
    }
    /^[0-9a-fA-F]{2}:/ && NF>=11 {
        if (count > 0) printf ","
        printf "{\"dest\":\"%s\",\"next_hop\":\"%s\",\"metric\":%s,\"hop_count\":%s,\"interface\":\"%s\"}", $1, $2, $5, $11, iface
        count++
    }
')

# 5. Формируем итоговый JSON
JSON_DATA=$(cat <<EOF
{
  "node_id": "$NODE_HOSTNAME",
  "timestamp": $TIMESTAMP,
  "local_macs": [$LOCAL_MACS],
  "mesh_peers": [${PEERS_JSON}],
  "mesh_paths": [${PATHS_JSON}]
}
EOF
)

# 6. Вывод для отладки
echo "$JSON_DATA"

# 7. Отправка на коллектор
if command -v curl >/dev/null 2>&1; then
    curl -s -X POST -H "Content-Type: application/json" -d "$JSON_DATA" "$COLLECTOR_URL" >/dev/null 2>&1
    [ $? -eq 0 ] && echo "[OK] Sent to collector" >&2 || echo "[ERROR] Failed to send" >&2
elif command -v wget >/dev/null 2>&1; then
    echo "$JSON_DATA" | wget --header="Content-Type: application/json" --post-data="$(cat)" -q -O - "$COLLECTOR_URL" >/dev/null 2>&1
    [ $? -eq 0 ] && echo "[OK] Sent to collector (wget)" >&2 || echo "[ERROR] Failed to send (wget)" >&2
else
    echo "[WARN] Neither curl nor wget found, data not sent" >&2
fi