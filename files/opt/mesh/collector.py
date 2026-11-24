#!/usr/bin/env python3
"""
BelMax Mesh Collector
- принимает JSON от агентов (POST /api/mesh-data)
- хранит один файл на ноду: ./mesh-data/<node_id>.json
- отдаёт направленный граф для визуализатора (GET /api/graph)
"""

import json
import os
import re
import tempfile
import threading
from datetime import datetime

from flask import Flask, request, jsonify, send_from_directory

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.environ.get("DATA_DIR", "/tmp/mesh-data")
BIND_ADDR = os.environ.get("BIND_ADDR", "0.0.0.0")
COLLECTOR_PORT = int(os.environ.get("COLLECTOR_PORT", "8080"))
STALE_AFTER = int(os.environ.get("STALE_AFTER", "90"))   # сек без данных -> узел/линк "протух"

os.makedirs(DATA_DIR, exist_ok=True)

app = Flask(__name__)

_lock = threading.RLock()
nodes_data = {}    # node_id -> {'data': ..., 'received_at': iso, 'received_ts': float}
mac_to_node = {}   # mac (lowercase) -> node_id

LEGACY_RE = re.compile(r"^(?P<node>.+)_(?P<ts>\d{9,})\.json$")
STATIC_EXT = {".html", ".js", ".css", ".map", ".png", ".svg", ".ico", ".woff", ".woff2"}


# ------------------------------------------------------------------ утилиты
def safe_name(node_id):
    """node_id -> безопасное имя файла (защита от ../ и мусора)."""
    name = re.sub(r"[^A-Za-z0-9_.-]", "_", str(node_id or "unknown"))[:64]
    return name.strip("._-") or "unknown"


def band_of(iface):
    """Диапазон по имени mesh-интерфейса (ваша плата: phy0=2.4G, phy1=5G)."""
    iface = iface or "?"
    if iface.startswith("phy0"):
        return "2.4G"
    if iface.startswith("phy1"):
        return "5G"
    return iface


def atomic_write_json(path, payload):
    """Временный файл + os.replace: читатель никогда не увидит недописанный json."""
    fd, tmp = tempfile.mkstemp(dir=DATA_DIR, prefix=".tmp-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise


def prune_data_dir():
    """Удаляет старые <node>_<timestamp>.json и мусор; остаётся по одному файлу на ноду."""
    keep = {safe_name(n) + ".json" for n in nodes_data}
    for name in os.listdir(DATA_DIR):
        path = os.path.join(DATA_DIR, name)
        if not os.path.isfile(path):
            continue
        if name.startswith(".tmp-"):
            try:
                os.remove(path)
            except OSError:
                pass
            continue
        if not name.endswith(".json") or name in keep:
            continue
        if LEGACY_RE.match(name):          # legacy-формат с timestamp в имени
            try:
                os.remove(path)
            except OSError:
                pass


def remember(node_id, payload, received_ts=None):
    ts = received_ts if received_ts is not None else datetime.now().timestamp()
    nodes_data[node_id] = {
        "data": payload,
        "received_at": datetime.fromtimestamp(ts).isoformat(timespec="seconds"),
        "received_ts": ts,
    }
    for mac in payload.get("local_macs") or []:
        if not mac:
            continue
        mac = str(mac).lower()
        prev = mac_to_node.get(mac)
        if prev and prev != node_id:
            print(f"[warn] MAC {mac} переехал {prev} -> {node_id} (дубликат MAC в сети?)")
        mac_to_node[mac] = node_id


def load_snapshots():
    """При старте поднимаем последние снимки с диска (и мигрируем legacy-имена)."""
    best = {}
    for name in sorted(os.listdir(DATA_DIR)):
        if not name.endswith(".json") or name.startswith(".tmp-"):
            continue
        path = os.path.join(DATA_DIR, name)
        try:
            with open(path, encoding="utf-8") as f:
                payload = json.load(f)
            mtime = os.path.getmtime(path)
        except Exception:
            continue
        if not isinstance(payload, dict) or "node_id" not in payload:
            continue                      # чужие json в каталоге не трогаем
        if not any(k in payload for k in ("mesh_peers", "mesh_paths", "local_macs")):
            continue
        m = LEGACY_RE.match(name)
        node_id = safe_name(payload.get("node_id") or (m.group("node") if m else name[:-5]))
        if node_id not in best or mtime > best[node_id][0]:
            best[node_id] = (mtime, payload)

    for node_id, (mtime, payload) in best.items():
        payload["node_id"] = node_id
        remember(node_id, payload, received_ts=mtime)
        atomic_write_json(os.path.join(DATA_DIR, node_id + ".json"), payload)
    prune_data_dir()
    if best:
        print(f"[init] загружено снимков: {len(best)} -> {sorted(best)}")


# ------------------------------------------------------------------ статика
@app.route("/")
def index():
    return send_from_directory(BASE_DIR, "mesh-viewer.html")


@app.route("/<path:filename>")
def static_files(filename):
    ext = os.path.splitext(filename)[1].lower()
    if ext not in STATIC_EXT:
        return jsonify(status="error", message="forbidden"), 403
    return send_from_directory(BASE_DIR, filename)


# ------------------------------------------------------------------ приём
@app.route("/api/mesh-data", methods=["POST"])
def receive_mesh_data():
    payload = request.get_json(force=True, silent=True)   # force: busybox wget шлёт без Content-Type
    if not isinstance(payload, dict):
        return jsonify(status="error", message="invalid JSON"), 400

    node_id = safe_name(payload.get("node_id"))
    payload["node_id"] = node_id
    try:
        with _lock:
            remember(node_id, payload)
            atomic_write_json(os.path.join(DATA_DIR, node_id + ".json"), payload)
            prune_data_dir()
    except Exception as e:
        return jsonify(status="error", message=str(e)), 500

    print(f"[{datetime.now():%H:%M:%S}] + {node_id}: "
          f"{len(payload.get('mesh_peers') or [])} peer(s), "
          f"{len(payload.get('mesh_paths') or [])} path(s)")
    return jsonify(status="ok", node_id=node_id), 200


# ------------------------------------------------------------------ граф
@app.route("/api/graph", methods=["GET"])
def get_graph():
    with _lock:
        snapshot = dict(nodes_data)
        mapping = dict(mac_to_node)

    now = datetime.now().timestamp()
    nodes, edges, unknown = [], [], {}

    for node_id, rec in snapshot.items():
        d = rec["data"]
        age = int(max(0, now - rec["received_ts"]))
        ifaces = sorted({p.get("interface") for p in (d.get("mesh_peers") or []) if p.get("interface")})
        nodes.append({"data": {
            "id": node_id,
            "label": node_id,
            "ifaces": ifaces,
            "age": age,
            "stale": age > STALE_AFTER,
            "timestamp": d.get("timestamp"),
            "received_at": rec["received_at"],
        }})

    for node_id, rec in snapshot.items():
        age = int(max(0, now - rec["received_ts"]))
        for peer in rec["data"].get("mesh_peers") or []:
            if peer.get("plink") != "ESTAB":
                continue
            peer_mac = str(peer.get("peer_mac") or peer.get("mac") or "").lower()
            if not peer_mac:
                continue

            target = mapping.get(peer_mac)
            if target is None:
                # узел ещё не присылал своих local_macs -> стабильный placeholder по MAC
                target = "?" + peer_mac[-8:]
                unknown[target] = peer_mac

            iface = peer.get("interface") or "?"
            edges.append({"data": {
                "id": f"{node_id}-->{target}:{iface}",   # направление + интерфейс в ID
                "source": node_id,
                "target": target,
                "interface": iface,
                "band": band_of(iface),
                "signal": peer.get("signal"),
                "throughput": peer.get("throughput"),
                "metric": peer.get("metric"),
                "age": age,
                "stale": age > STALE_AFTER,
            }})

    for target, mac in unknown.items():
        nodes.append({"data": {"id": target, "label": target, "mac": mac,
                               "unknown": True, "ifaces": [], "age": 0, "stale": False}})

    return jsonify(elements={"nodes": nodes, "edges": edges},
                   stale_after=STALE_AFTER,
                   generated_at=datetime.now().isoformat(timespec="seconds"))


@app.route("/api/topology", methods=["GET"])
def get_topology():
    with _lock:
        return jsonify(nodes=list(nodes_data), data=nodes_data, total=len(nodes_data))


@app.route("/api/health", methods=["GET"])
def health():
    with _lock:
        return jsonify(status="running", nodes_count=len(nodes_data),
                       nodes=list(nodes_data), mac_map_size=len(mac_to_node),
                       data_dir=DATA_DIR,
                       files=sorted(f for f in os.listdir(DATA_DIR) if f.endswith(".json")))


load_snapshots()

if __name__ == "__main__":
    print("=" * 60)
    print(f"BelMax Mesh Collector  ->  http://localhost:{COLLECTOR_PORT}")
    print(f"Данные: {DATA_DIR} (по одному файлу на ноду)")
    print("=" * 60)
    app.run(host=BIND_ADDR, port=COLLECTOR_PORT, debug=False, threaded=True)