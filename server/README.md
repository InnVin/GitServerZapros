# Сервер InnVin с нуля

Сервер сайтов и данных один: **Москва 195.133.10.220** (Ubuntu 24.04, 1 ядро, 1 ГБ + подкачка 2 ГБ).
Любой коммит в рабочую ветку проекта сам выкладывается на него (GitServerZapros). Эти скрипты нужны, чтобы
поднять Москву на новом сервере (~1–2 часа), затем вернуть данные из ежедневной копии (см. README в корне).
Секреты со старого сервера переносятся через ПК пайпом, не печатая.
Сервер во Франции (166.88.228.60) — только личный VPN (3x-ui, Xray прямо на 443): эти скрипты и проекты туда не ставятся.

## Файлы
- `base.sh` — подкачка 2 ГБ, nginx, certbot, sqlite3, rsync, ufw (правила 22/80/443 и порты x-ui, **без включения**), Node.js 22.
- `edge.sh` — общий вход 443. Снаружи 443 держит nginx **stream** (`/etc/nginx/stream.conf`), смотрит имя сайта (SNI):
  `*.sslip.io` → https-сайты nginx на `127.0.0.1:8443` (с PROXY protocol, настоящий IP клиента), остальное → VPN Xray
  (если он слушает `127.0.0.1:443`). Пишет паспорт `/etc/innvin/server.env` (`SERVER`, `PUBLIC_IP`, `PUBLIC_IP6`, `SLUG`)
  и сниппеты `snippets/innvin-ssl-listen.conf`, `snippets/innvin-to-https.conf`, сайт-отказ `innvin-default-ssl`.
- `vpn_test.sh` — проверка VPN как клиент (VLESS Reality через свой 443). Ответ «VPN: работает» — всё в порядке.

## Порядок (от root)
```bash
bash base.sh
# VPN (x-ui) — ставит владелец; x-ui, xray, fail2ban и /etc/x-ui не трогать
SERVER=msk bash edge.sh
```
Затем проекты — по их инструкциям (`deploy/` в каждом репозитории), в таком порядке:
1. **FamilyTree** — сайт по IP (default_server на 80, подключает `/etc/nginx/projects.d/*.conf`), включает ufw — **только после «да» владельца**.
   Перед этим `ufw show added` должен содержать 22, 80, 443 и все публичные порты x-ui (`ss -tlnp | grep -E 'x-ui|xray'`).
2. **GitServerZapros** — `/opt/gsz` (`install.sh`). Секрет `/etc/gsz/env` переносится со старого сервера (или создаётся новый — тогда обновить его во всех вебхуках).
3. **DKP** (`/opt/dkp`, `deploy/install.sh`; сайт `dkp.*` принимает и вебхуки GitHub), **Автоподбор** (`/opt/avto`),
   **snack** (`/opt/snack`), **LaF** последним (`/opt/laf`, MongoDB — тяжёлый).

Приватные репозитории — deploy key **только чтение**, свой для сервера: `/root/.ssh/<имя>_deploy`, алиас `Host github-<имя>`
в `/root/.ssh/config` (клон `git@github-<имя>:InnVin/<Repo>.git`). У LaF ключ — у пользователя `laf` (`/opt/laf/.ssh`).

## Правила для https-сайтов проектов
- Не писать `listen 443`: вместо него `include snippets/innvin-ssl-listen.conf;`. Порт 80 сайта — acme-challenge
  и `include snippets/innvin-to-https.conf;`.
- Имя — `server_name <имя>.*;` (на сервере это `<имя>.<SLUG>.sslip.io`), сертификат —
  `certbot certonly --webroot -w /var/www/letsencrypt --cert-name <имя> -d <имя>.<SLUG>.sslip.io -n --agree-tos --register-unsafely-without-email --deploy-hook "systemctl reload nginx"`,
  путь `/etc/letsencrypt/live/<имя>/`.
- Адреса по IP — файл проекта в `/etc/nginx/projects.d/`.

## Проверка
- На сервере памятка `/root/README-СЕРВЕР.md`: адреса, что где лежит, журналы.
- `http://<IP>/status` — какие версии проектов выложены и совпадают ли с GitHub.
- `systemctl --failed` — пусто; `free -m`; если на сервере есть VPN за 443 — после правок nginx `bash /root/vpn_test.sh`.
- https с сервера: `curl --resolve dkp.<SLUG>.sslip.io:443:<IP> https://dkp.<SLUG>.sslip.io/`.
