#!/bin/bash
# Проверка VPN как клиент: подключиться к своему VLESS Reality на <IP>:443 и узнать внешний IP через туннель.
# Секреты из базы x-ui не печатаются.
IP=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<NF;i++) if($i=="src") print $(i+1)}')
XRAY=$(ls /usr/local/x-ui/bin/xray-linux-* | head -1)
python3 - "$IP" > /tmp/vpn-client.json <<'PY'
import sqlite3, json, sys
ip = sys.argv[1]
c = sqlite3.connect("file:/etc/x-ui/x-ui.db?mode=ro", uri=True)
port, ss, st = c.execute("select port, stream_settings, settings from inbounds where protocol='vless' and enable=1 order by id limit 1").fetchone()
ss = json.loads(ss); st = json.loads(st); rs = ss["realitySettings"]; cl = st["clients"][0]
cfg = {
  "log": {"loglevel": "warning"},
  "inbounds": [{"listen": "127.0.0.1", "port": 10808, "protocol": "socks", "settings": {"udp": False}}],
  "outbounds": [{"protocol": "vless", "settings": {"vnext": [{"address": ip, "port": 443, "users": [{"id": cl["id"], "encryption": "none", "flow": cl.get("flow", "")}]}]},
    "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {
      "serverName": rs["serverNames"][0], "fingerprint": rs.get("settings", {}).get("fingerprint", "chrome") or "chrome",
      "publicKey": rs["settings"]["publicKey"], "shortId": (rs.get("shortIds") or [""])[0], "spiderX": "/"}}}]}
print(json.dumps(cfg))
PY
chmod 600 /tmp/vpn-client.json
$XRAY run -c /tmp/vpn-client.json >/tmp/vpn-client.log 2>&1 &
P=$!; sleep 3
OUT=$(curl -s -m 10 --socks5-hostname 127.0.0.1:10808 https://api.ipify.org)
kill $P 2>/dev/null; wait $P 2>/dev/null; rm -f /tmp/vpn-client.json
if [ "$OUT" = "$IP" ]; then echo "VPN: работает (выход через $OUT)"; else echo "VPN: НЕ работает (ответ: ${OUT:-пусто})"; tail -5 /tmp/vpn-client.log; fi
