#!/bin/bash
# База для серверов InnVin: swap, пакеты, Node 22, правила ufw (без включения)
set -e
export DEBIAN_FRONTEND=noninteractive
if ! swapon --show | grep -q /swapfile; then
  [ -f /swapfile ] || { fallocate -l 2G /swapfile; chmod 600 /swapfile; mkswap /swapfile >/dev/null; }
  swapon /swapfile
fi
grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
echo 'vm.swappiness=20' > /etc/sysctl.d/90-innvin.conf; sysctl -q -p /etc/sysctl.d/90-innvin.conf
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg nginx sqlite3 rsync ufw certbot git >/dev/null
if ! node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||(a===22&&b>=13)?0:1)' 2>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null
  apt-get install -y -qq nodejs >/dev/null
fi
mkdir -p /etc/nginx/projects.d /var/www/letsencrypt
# порты панели и VPN (x-ui) — чтобы включение ufw их не закрыло
ufw allow OpenSSH >/dev/null; ufw allow 'Nginx Full' >/dev/null
for p in $(ss -tlnupH | grep -E 'x-ui|xray' | awk '{print $5}' | grep -vE '^127\.|^\[::1\]' | sed 's/.*://' | sort -u); do ufw allow $p >/dev/null; done
echo "node $(node -v) · npm $(npm -v) · nginx $(nginx -v 2>&1 | cut -d/ -f2) · certbot $(certbot --version 2>&1 | cut -d' ' -f2)"
free -m | awk '/Swap/{print "swap: "$2" МБ"}'
