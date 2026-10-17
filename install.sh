#!/bin/bash
# GitServerZapros: установка (один раз) — git clone https://github.com/InnVin/GitServerZapros /opt/gsz && bash /opt/gsz/install.sh
# --refresh — обновить службы после изменений (запускается сам после обновления GitServerZapros).
set -e
G=/opt/gsz
REFRESH=${1:-}

if [ "$REFRESH" != "--refresh" ]; then
  id gsz >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin gsz
  mkdir -p /etc/gsz /var/lib/gsz/triggers
  chown gsz:gsz /var/lib/gsz/triggers
  if [ ! -f /etc/gsz/env ]; then
    echo "GSZ_SECRET=$(openssl rand -hex 24)" > /etc/gsz/env
    chown root:gsz /etc/gsz/env; chmod 640 /etc/gsz/env
  fi
fi

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

if [ "$REFRESH" != "--refresh" ]; then
  NG=/etc/nginx/sites-available/dkp-https
  cp $G/nginx-gsz.conf /etc/nginx/snippets/gsz.conf
  if ! grep -q 'snippets/gsz.conf' $NG; then
    cp $NG $NG.bak-gsz
    sed -i '0,/location \/ { return 302/s//include snippets\/gsz.conf;\n\n    location \/ { return 302/' $NG
  fi
  if nginx -t 2>/dev/null; then systemctl reload nginx
  else [ -f $NG.bak-gsz ] && cp $NG.bak-gsz $NG; echo "nginx: ошибка, конфиг возвращён"; exit 1; fi

  sleep 1
  echo
  systemctl is-active gsz-receiver gsz-poll.timer
  echo
  echo "Вебхук для КАЖДОГО репозитория (GitHub → Settings → Webhooks → Add webhook):"
  echo "  Payload URL:  https://dkp.194-58-38-8.sslip.io/gsz/hook"
  echo "  Content type: application/json"
  echo "  Secret:       $(cut -d= -f2 /etc/gsz/env)"
fi
