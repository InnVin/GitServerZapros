#!/bin/bash
# GitServerZapros: установка (один раз) — git clone https://github.com/InnVin/GitServerZapros /opt/gsz && bash /opt/gsz/install.sh
# --refresh — обновить службы после изменений (запускается сам после обновления GitServerZapros).
# Секрет /etc/gsz/env создаётся, если его нет. На второй сервер заранее кладётся тот же файл: один секрет для всех вебхуков.
# Адрес сервера — из /etc/innvin/server.env (пишет server/edge.sh). Секрет не печатается.
set -e
G=/opt/gsz
REFRESH=${1:-}

id gsz >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin gsz
install -d -m 750 -o root -g gsz /etc/gsz
install -d -m 755 /var/lib/gsz /var/lib/gsz/status /var/lib/gsz/www
install -d -m 755 -o gsz -g gsz /var/lib/gsz/triggers
[ -f /etc/gsz/env ] || ( umask 077; echo "GSZ_SECRET=$(openssl rand -hex 24)" > /etc/gsz/env )
chown root:gsz /etc/gsz/env; chmod 640 /etc/gsz/env

chmod +x $G/deploy.sh
cp $G/systemd/* /etc/systemd/system/
systemctl daemon-reload

# отметка и слежение для каждого проекта из списка (новые проекты подключаются здесь сами)
for n in $(node -e 'for (const v of Object.values(require(process.argv[1]))) console.log(v.name)' $G/projects.json); do
  [ -f /var/lib/gsz/triggers/$n ] || install -o gsz -g gsz -m 644 /dev/null /var/lib/gsz/triggers/$n
  systemctl enable --now gsz-deploy@$n.path >/dev/null 2>&1
done
systemctl enable --now gsz-poll.timer >/dev/null 2>&1
systemctl enable gsz-receiver >/dev/null 2>&1
systemctl restart gsz-receiver

# старое автообновление DKP больше не нужно
for u in dkp-autopull.timer dkp-autopull.path; do systemctl disable --now $u >/dev/null 2>&1 || true; done

# nginx: /gsz/hook (сниппет, его подключает сайт dkp-https из DKP) и страница /status на IP (projects.d).
# Ставится только при изменении, с проверкой nginx -t; при ошибке возвращается прежний файл.
RELOAD=0
put_ng() { # put_ng <файл в репо> <файл nginx>
  cmp -s "$1" "$2" && return 0
  [ -f "$2" ] && cp "$2" "$2.prev"
  cp "$1" "$2"
  if nginx -t 2>/dev/null; then rm -f "$2.prev"; RELOAD=1; return 0; fi
  if [ -f "$2.prev" ]; then mv "$2.prev" "$2"; else rm -f "$2"; fi
  echo "nginx: ошибка в $2 — возвращён прежний"; return 1
}
put_ng $G/nginx-gsz.conf /etc/nginx/snippets/gsz.conf || true
if [ -d /etc/nginx/projects.d ]; then put_ng $G/nginx-status.conf /etc/nginx/projects.d/gsz-status.conf || true; fi
if [ $RELOAD = 1 ]; then systemctl reload nginx; fi

node $G/status.mjs || echo "страница состояния: ошибка"

if [ "$REFRESH" != "--refresh" ]; then
  SLUG="<IP-через-дефисы>"; PUBLIC_IP="<IP>"
  [ -f /etc/innvin/server.env ] && . /etc/innvin/server.env
  sleep 1
  echo
  systemctl is-active gsz-receiver gsz-poll.timer
  grep -qs 'snippets/gsz.conf' /etc/nginx/sites-enabled/dkp-https || echo "Внимание: сайт dkp-https (DKP) ещё не установлен — вебхук пока не дойдёт"
  echo
  echo "Вебхук этого сервера (каждый репозиторий из projects.json, событие push, application/json):"
  echo "  https://dkp.$SLUG.sslip.io/gsz/hook"
  echo "Секрет общий для всех серверов — в /etc/gsz/env (здесь не выводится)."
  echo "Состояние выкладки: http://$PUBLIC_IP/status"
fi
