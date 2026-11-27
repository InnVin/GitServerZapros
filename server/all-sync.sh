#!/bin/bash
# InnVin: раз в сутки (15:00 UTC) кладёт свежие ключи и конфиги сервера в приватный репозиторий InnVin/ALL.
# Ставит install.sh в /usr/local/sbin/innvin-all-sync; запускает таймер innvin-all-sync.timer (после пропуска — через 10 минут после старта сервера).
# Проекты и базы не копирует (их забирает innvin-backup). В репозитории GitServerZapros секретов нет: ключ GitHub — только на сервере (/root/.ssh/all_deploy, запись только в InnVin/ALL).
# Защита: замок (второй экземпляр не стартует), лимит времени, низкий приоритет; ошибка — запись в журнал, повтор завтра. Пуш: нет изменений — нет коммита.
set -uo pipefail
umask 077
W=/var/lib/innvin-all-sync
REPO=$W/repo
SUB="_СЕРВЕР/Москва-195.133.10.220"
LOG=$W/last.log
mkdir -p "$W"
exec 9>"$W/lock"; flock -n 9 || { echo "уже идёт"; exit 0; }
exec > >(tee "$LOG") 2>&1
echo "== $(date -u '+%F %T') UTC"
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=20"
export GIT_TERMINAL_PROMPT=0

# 1. Узкий клон: только нужные папки, без истории и крупных файлов
if [ ! -d "$REPO/.git" ]; then
  rm -rf "$REPO"
  git clone --depth 1 --filter=blob:none --sparse git@github-all:InnVin/ALL.git "$REPO" || { echo "ОШИБКА: клон"; exit 1; }
  git -C "$REPO" sparse-checkout set "$SUB/секреты" "$SUB/конфиги" || exit 1
else
  git -C "$REPO" fetch -q --depth 1 origin main && git -C "$REPO" reset -q --hard origin/main || { echo "ОШИБКА: обновление клона"; exit 1; }
fi
git -C "$REPO" config user.name "innvin-all-sync"
git -C "$REPO" config user.email "all-sync@innvin.local"
git -C "$REPO" config core.quotepath false

S="$REPO/$SUB/секреты"
C="$REPO/$SUB/конфиги"
mkdir -p "$S" "$C"

# 2. Секреты: список фиксирован; нет файла — пропуск
SECRETS=(/etc/avto /etc/dkp /etc/gsz /etc/kvartplata /etc/pointeresam14 /etc/innvin
         /opt/nahodki14/.env /opt/nahodki14/data/secrets.json /etc/x-ui/install-result.env
         /root/.ssh/authorized_keys /var/lib/pointeresam14/vapid.json /var/lib/pointeresam14/zone.key /var/lib/dairy/auth.json)
for p in "${SECRETS[@]}"; do
  [ -e "$p" ] || continue
  mkdir -p "$S$(dirname "$p")"
  rsync -a --delete "$p" "$S$(dirname "$p")/"
done
# база панели 3x-ui — целостная копия
if [ -f /etc/x-ui/x-ui.db ]; then
  mkdir -p "$S/etc/x-ui"; rm -f "$S/etc/x-ui/x-ui.db"
  sqlite3 /etc/x-ui/x-ui.db ".backup '$S/etc/x-ui/x-ui.db'" || echo "x-ui.db: копия не вышла"
fi

# 3. Конфиги: nginx, службы, скрипты, cron, памятка сервера (симлинки как есть)
CONF=(/etc/nginx/sites-available /etc/nginx/snippets /etc/nginx/nginx.conf /etc/nginx/stream.conf /etc/nginx/projects.d
      /usr/local/sbin /usr/local/bin /etc/cron.d /root/README-СЕРВЕР.md /root/.ssh/config)
for p in "${CONF[@]}"; do
  [ -e "$p" ] || continue
  mkdir -p "$C$(dirname "$p")"
  rsync -a --delete --no-links "$p" "$C$(dirname "$p")/"
done
mkdir -p "$C/etc/systemd/system"
rsync -a --delete --no-links --include='*.service' --include='*.timer' --include='*.path' --exclude='*' /etc/systemd/system/ "$C/etc/systemd/system/"
{ echo "снято: $(date -u '+%F %T') UTC"; systemctl list-units --type=service --state=running --no-pager --plain | awk '{print $1}' | grep '\.service$'; ss -tlnp | awk '{print $4}'; df -h / | tail -1; free -m | sed -n 2p; git -C /opt/gsz log --oneline -1; } > "$C/инвентаризация.txt"
# контроль размера: слишком большое — не пушить
if [ "$(du -sm "$REPO/$SUB" | cut -f1)" -gt 20 ]; then echo "ОШИБКА: папка больше 20 МБ — пуш остановлен"; exit 1; fi

# 4. Коммит и пуш, только если есть изменения
cd "$REPO"
git add -A -f -- "$SUB/секреты" "$SUB/конфиги"
if git diff --cached --quiet; then echo "без изменений"; exit 0; fi
git commit -q -m "сервер Москва: ключи и конфиги $(date -u +%F)"
git push -q origin HEAD:main && echo "отправлено: $(git rev-parse --short HEAD)" || { echo "ОШИБКА: пуш"; exit 1; }
