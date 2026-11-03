#!/bin/bash
# InnVin: общий вход 443 на сервере. Запуск от root: SERVER=msk bash edge.sh
#   443 (публичный) → nginx stream смотрит имя сайта (SNI):
#     *.sslip.io → сайты nginx (127.0.0.1:8443, с настоящим IP клиента)
#     остальное  → VPN Xray (127.0.0.1:443), если он есть; иначе тоже сайты
# Повторный запуск безопасен.
set -e
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
cat > /etc/nginx/stream.conf <<EOF
# InnVin: общий вход 443 ($SERVER). Создан edge.sh — правки делать там.
# *.sslip.io → сайты (127.0.0.1:8443); остальное → $VPN
stream {
    map \$ssl_preread_server_name \$innvin_443 {
        ~\.sslip\.io\$  innvin_web;
        default        $VPN;
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
grep -q '^include /etc/nginx/stream.conf;' /etc/nginx/nginx.conf || sed -i '/^include \/etc\/nginx\/modules-enabled/a include /etc/nginx/stream.conf;' /etc/nginx/nginx.conf

nginx -t -q
if [ "${APPLY:-1}" = 1 ]; then systemctl reload nginx; fi
echo "edge: $SERVER $IP ${IP6:-} · 443 по умолчанию → $VPN"
