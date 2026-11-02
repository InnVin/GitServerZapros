# Сервер InnVin с нуля

Два одинаковых сервера (Ubuntu 24.04, 1 ядро, 1 ГБ + подкачка 2 ГБ): **Москва 195.133.10.220 — основной**,
**Нидерланды 194.87.82.218 — запасной**. Любой коммит в рабочую ветку проекта сам выкладывается на оба (GitServerZapros).
Сервера друг друга по сети не видят: общие секреты переносятся через ПК пайпом, не печатая.

## Файлы
- `base.sh` — подкачка 2 ГБ, nginx, certbot, sqlite3, rsync, ufw (правила 22/80/443 и порты x-ui, **без включения**), Node.js 22.
- `edge.sh` — общий вход 443. Снаружи 443 держит nginx **stream** (`/etc/nginx/stream.conf`), смотрит имя сайта (SNI):
  `*.sslip.io` → https-сайты nginx на `127.0.0.1:8443` (с PROXY protocol, настоящий IP клиента), остальное → VPN Xray
  (если он слушает `127.0.0.1:443`, сейчас — на NL). Пишет паспорт `/etc/innvin/server.env` (`SERVER`, `PUBLIC_IP`, `PUBLIC_IP6`, `SLUG`)
  и сниппеты `snippets/innvin-ssl-listen.conf`, `snippets/innvin-to-https.conf`, сайт-отказ `innvin-default-ssl`.
- `vpn_test.sh` — проверка VPN как клиент (VLESS Reality через свой 443). Ответ «VPN: работает» — всё в порядке.

## Порядок (от root)
```bash
bash base.sh
# VPN (x-ui) — ставит владелец; x-ui, xray, fail2ban и /etc/x-ui не трогать
SERVER=msk bash edge.sh          # на NL: SERVER=nl
```
Затем проекты — по их инструкциям (`deploy/` в каждом репозитории), в таком порядке:
1. **FamilyTree** — сайт по IP (default_server на 80, подключает `/etc/nginx/projects.d/*.conf`), включает ufw.
   Перед этим `ufw show added` должен содержать 22, 80, 443 и все публичные порты x-ui (`ss -tlnp | grep -E 'x-ui|xray'`).
2. **GitServerZapros** — `/opt/gsz` (`install.sh`). Секрет `/etc/gsz/env` создаётся на первом сервере, на второй копируется.
3. **DKP** (`/opt/dkp`, `deploy/install.sh`; сайт `dkp.*` принимает и вебхуки GitHub), **Автоподбор** (`/opt/avto`),
   **snack** (`/opt/snack`), **LaF** последним (`/opt/laf`, MongoDB — тяжёлый).

Приватные репозитории — deploy key **только чтение**, на каждом сервере свой: `/root/.ssh/<имя>_deploy`, алиас `Host github-<имя>`
в `/root/.ssh/config` (клон `git@github-<имя>:InnVin/<Repo>.git`). У LaF ключ — у пользователя `laf` (`/opt/laf/.ssh`).

## Правила для https-сайтов проектов
- Не писать `listen 443`: вместо него `include snippets/innvin-ssl-listen.conf;`. Порт 80 сайта — acme-challenge
  и `include snippets/innvin-to-https.conf;`.
- Имя — `server_name <имя>.*;` (на сервере это `<имя>.<SLUG>.sslip.io`), сертификат —
  `certbot certonly --webroot -w /var/www/letsencrypt --cert-name <имя> -d <имя>.<SLUG>.sslip.io -n --agree-tos --register-unsafely-without-email --deploy-hook "systemctl reload nginx"`,
  путь `/etc/letsencrypt/live/<имя>/`.
- Адреса по IP — файл проекта в `/etc/nginx/projects.d/`.

## Проверка
- `http://<IP>/status` — какие версии проектов выложены и совпадают ли с GitHub.
- `systemctl --failed` — пусто; `free -m`; на NL после правок nginx — `bash /root/vpn_test.sh`.
- https с сервера: `curl --resolve dkp.<SLUG>.sslip.io:443:<IP> https://dkp.<SLUG>.sslip.io/`.
