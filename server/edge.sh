#!/bin/bash
# InnVin: общий вход 443 на сервере. Запуск от root: SERVER=msk bash edge.sh
#   443 (публичный) → nginx stream смотрит имя сайта (SNI):
#     свои домены (server/web-domains.txt: *.sslip.io, nahodki14.ru, …) → сайты nginx (127.0.0.1:8443, с настоящим IP клиента)
#     остальное  → VPN Xray (127.0.0.1:443), если он есть; иначе тоже сайты
# Новый домен — одна строка в server/web-domains.txt (домен вместе со всеми поддоменами).
# stream.conf ставится с проверкой nginx -t: при ошибке возвращается прежний файл, reload не делается, выход с ошибкой.
# Повторный запуск безопасен. После пуша с изменением edge.sh или web-domains.txt запускается сам (install.sh --refresh).
set -e
DOMAINS_FILE=${DOMAINS_FILE:-$(dirname "$(readlink -f "$0")")/web-domains.txt}
[ -f "$DOMAINS_FILE" ] || { echo "edge: нет списка доменов $DOMAINS_FILE" >&2; exit 1; }
# строки списка → записи map: домен и все его поддомены. Пустые строки и # — пропуск; кривой домен — ошибка.
MAP_WEB=""; DOMAINS_LIST=""
while read -r d _ || [ -n "${d:-}" ]; do
  d=${d%%#*}; d=${d,,}; [ -n "$d" ] || continue
  [[ "$d" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] || { echo "edge: неверный домен «$d» в $DOMAINS_FILE" >&2; exit 1; }
  MAP_WEB+="        ~(^|\\.)${d//./\\.}\$  innvin_web;"$'\n'
  DOMAINS_LIST+="${DOMAINS_LIST:+, }$d"
done < "$DOMAINS_FILE"
[ -n "$MAP_WEB" ] || { echo "edge: список доменов $DOMAINS_FILE пуст" >&2; exit 1; }
: "${SERVER:?укажите SERVER=msk (имя сервера латиницей)}"
export DEBIAN_FRONTEND=noninteractive
IP=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<NF;i++) if($i=="src") print $(i+1)}')
IP6=$(ip -6 addr show scope global | awk '/inet6/{print $2}' | cut -d/ -f1 | head -1)
SLUG=${IP//./-}

mkdir -p /etc/innvin
cat > /etc/innvin/server.env <<EOF
# Паспорт сервера InnVin (читают скрипты проектов)
SERVER=$SERVER
PUBLIC_IP=$IP
PUBLIC_IP6=$IP6
SLUG=$SLUG
EOF

dpkg -s libnginx-mod-stream >/dev/null 2>&1 || apt-get install -y -qq libnginx-mod-stream >/dev/null

# сайты по https слушают только внутри; снаружи их отдаёт stream на 443
# nginx до 1.25.1 (Ubuntu 24.04 — 1.24) включает http2 в строке listen, новее — директивой «http2 on»
NV=$(nginx -v 2>&1 | grep -o '[0-9][0-9.]*' | head -1)
if [ "$(printf '%s\n1.25.1\n' "$NV" | sort -V | head -1)" = 1.25.1 ]; then H2=""; H2ON="http2 on;"; else H2=" http2"; H2ON=""; fi
cat > /etc/nginx/snippets/innvin-ssl-listen.conf <<EOF
# InnVin: https-сайт. Снаружи — порт 443 через stream (/etc/nginx/stream.conf).
listen 127.0.0.1:8443 ssl proxy_protocol$H2;
$H2ON
set_real_ip_from 127.0.0.1;
real_ip_header proxy_protocol;
ssl_protocols TLSv1.2 TLSv1.3;
EOF
cat > /etc/nginx/snippets/innvin-to-https.conf <<'EOF'
# InnVin: с http на https
location / { return 301 https://$host$request_uri; }
EOF

# неизвестное имя на 8443 — отказ без сертификата
cat > /etc/nginx/sites-available/innvin-default-ssl <<EOF
# InnVin: https-запрос к неизвестному имени — отказ
server {
    listen 127.0.0.1:8443 ssl proxy_protocol$H2 default_server;
    ssl_reject_handshake on;
}
EOF
ln -sf /etc/nginx/sites-available/innvin-default-ssl /etc/nginx/sites-enabled/innvin-default-ssl

# VPN на 443 есть, если Xray слушает 127.0.0.1:443
VPN=innvin_web
ss -tlnH 'sport = :443' | grep -q '127.0.0.1:443' && VPN=innvin_vpn
[ "${FORCE_VPN:-}" = 1 ] && VPN=innvin_vpn
L6=""; [ -n "$IP6" ] && L6="        listen [$IP6]:443;"
SC=/etc/nginx/stream.conf
cat > "$SC.new" <<EOF
# InnVin: общий вход 443 ($SERVER). Создан edge.sh — правки делать там (GitServerZapros, server/edge.sh).
# Свои домены и их поддомены → сайты (127.0.0.1:8443): $DOMAINS_LIST
# Список — server/web-domains.txt; остальное → $VPN
stream {
    map \$ssl_preread_server_name \$innvin_443 {
${MAP_WEB}        default        $VPN;
    }
    upstream innvin_web { server 127.0.0.1:8443; }
    upstream innvin_vpn { server 127.0.0.1:443; }
    server {
        listen $IP:443;
$L6
        ssl_preread on;
        proxy_pass \$innvin_443;
        proxy_protocol on;
        proxy_connect_timeout 5s;
    }
}
EOF
# поставить новый stream.conf с проверкой; при ошибке — вернуть прежний и выйти, без reload
HAD=0; [ -f "$SC" ] && { cp -p "$SC" "$SC.prev"; HAD=1; }
mv "$SC.new" "$SC"
INC=0
if ! grep -q '^include /etc/nginx/stream.conf;' /etc/nginx/nginx.conf; then
  cp -p /etc/nginx/nginx.conf /etc/nginx/nginx.conf.prev; INC=1
  sed -i '/^include \/etc\/nginx\/modules-enabled/a include /etc/nginx/stream.conf;' /etc/nginx/nginx.conf
fi
if ! nginx -t -q; then
  if [ $HAD = 1 ]; then mv "$SC.prev" "$SC"; else rm -f "$SC"; fi
  if [ $INC = 1 ]; then mv /etc/nginx/nginx.conf.prev /etc/nginx/nginx.conf; fi
  echo "edge: nginx -t не прошёл — возвращён прежний $SC, nginx не перезагружен" >&2
  exit 1
fi
rm -f "$SC.prev" /etc/nginx/nginx.conf.prev
if [ "${APPLY:-1}" = 1 ]; then systemctl reload nginx; fi
echo "edge: $SERVER $IP ${IP6:-} · 443 по умолчанию → $VPN"
