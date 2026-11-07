#!/bin/bash
# InnVin: копия данных проектов одним архивом tar.gz в stdout. На сервере — /usr/local/sbin/innvin-backup (ставит install.sh).
#   ssh msk innvin-backup > innvin-ГГГГ-ММ-ДД.tar.gz      (каждый день делает ПК владельца: pc/backup-msk.ps1)
# Состав: базы SQLite (целостная копия .backup, службы не останавливаются) FamilyTree и DKP, копии DKP,
# данные Квартплаты и Мелочей, Автоподбор (отчёты, настройки, фото; видео не входит), LaF: база MongoDB laf
# (свежий mongodump --archive --gzip; не вышел — последний архив laf-backup из /opt/laf/backups) и фото
# /opt/laf/data/uploads. Нет LaF или mongodump — шаг пропускается. Секреты не входят: /etc, /opt/laf/.env,
# /opt/laf/data/secrets.json, ключи. Внутри — MANIFEST.txt: дата, сервер, размеры, sha256 каждого файла.
# Восстановить: tar -xzf innvin-ДАТА.tar.gz → папка innvin-ДАТА/var/lib/... — вернуть нужное в /var/lib/<проект>/
# (служба проекта остановлена, владелец файлов — как был), затем запустить службу. LaF — см. README («Копия данных»).
set -euo pipefail
umask 077
[ "$(id -u)" = 0 ] || { echo "innvin-backup: запускать от root" >&2; exit 1; }
SERVER=?; PUBLIC_IP=?
[ -f /etc/innvin/server.env ] && . /etc/innvin/server.env
NAME=innvin-$(date +%F)
T=$(mktemp -d /var/tmp/innvin-backup.XXXXXX)
trap 'rm -rf "$T"' EXIT
R=$T/$NAME
mkdir -p "$R"

db() {   # db <файл SQLite>: целостная копия
  [ -f "$1" ] || return 0
  mkdir -p "$R$(dirname "$1")"
  sqlite3 "$1" ".backup '$R$1'"
}
put() {  # put <файл или папка> [исключения rsync...]: снимок жёсткими ссылками (без лишнего места), копия — если ссылки нельзя
  local src=$1; shift
  [ -e "$src" ] || return 0
  mkdir -p "$R$(dirname "$src")"
  if [ -d "$src" ]; then rsync -a --link-dest="$src/" "$@" "$src/" "$R$src/"
  else rsync -a --link-dest="$(dirname "$src")/" "$src" "$R$(dirname "$src")/"; fi
}

db /var/lib/familytree/familytree.db
db /var/lib/familytree/hub.db
db /var/lib/dkp/dkp.db
put /var/lib/dkp/backups
put /var/lib/kvartplata/data.json
put /var/lib/family
put /var/lib/snack/data
put /var/lib/avto/reports
put /var/lib/avto/photos --exclude='*.mp4' --exclude='*.MP4' --exclude='*.mov' --exclude='*.MOV' --exclude='*.webm' --exclude='*.WEBM'
put /var/lib/avto/prefs.json
put /var/lib/avto/config.json
db /var/lib/avto/dkp/dkp.db
put /var/lib/avto/dkp/backups

# LaF (MongoDB). Настройки — из /opt/laf/.env (только MONGO_URI и DATA_DIR; сам файл в копию не входит).
# mongodump пишет поток прямо в файл — памяти почти не берёт; ошибки не печатаются (в них может быть адрес базы с паролем).
LAF_DB=""
laf() {
  local env=/opt/laf/.env uri="" data="" out=$R/opt/laf/mongo last
  [ -d /opt/laf ] || return 0
  if [ -f "$env" ]; then
    uri=$(grep -E '^MONGO_URI=' "$env" | tail -1 | cut -d= -f2- || true)
    data=$(grep -E '^DATA_DIR=' "$env" | tail -1 | cut -d= -f2- || true)
  fi
  uri=${uri:-mongodb://127.0.0.1:27017/laf}; data=${data:-/opt/laf/data}
  mkdir -p "$out"
  if command -v mongodump >/dev/null 2>&1 \
     && timeout 600 mongodump --uri="$uri" --archive="$out/laf.archive.gz" --gzip --quiet >/dev/null 2>&1; then
    LAF_DB="свежий mongodump"
  else
    rm -f "$out/laf.archive.gz"
    last=$(ls -1t /opt/laf/backups/laf-*.archive.gz 2>/dev/null | head -1 || true)
    if [ -n "$last" ]; then
      cp -p "$last" "$out/laf.archive.gz"; LAF_DB="последний laf-backup: $(basename "$last")"
    else
      rmdir "$out" 2>/dev/null || true; LAF_DB="нет (mongodump не прошёл, архивов laf-backup нет)"
    fi
    echo "innvin-backup: LaF — mongodump не прошёл, база: $LAF_DB" >&2
  fi
  # фото; secrets.json лежит рядом в $data и сюда не попадает
  if [ -d "$data/uploads" ]; then
    mkdir -p "$R/opt/laf/data"
    rsync -a --link-dest="$data/uploads/" "$data/uploads/" "$R/opt/laf/data/uploads/"
  fi
}
laf || echo "innvin-backup: LaF пропущен (ошибка копирования)" >&2

{
  echo "InnVin — копия данных проектов"
  echo "Дата:   $(date -u '+%F %H:%M UTC') ($(TZ=Europe/Moscow date '+%H:%M') МСК)"
  echo "Сервер: $SERVER $PUBLIC_IP ($(hostname))"
  echo "Файлов: $(find "$R" -type f | wc -l), всего $(du -sh --apparent-size "$R" | cut -f1)"
  echo
  echo "Размеры по проектам:"
  for p in familytree dkp kvartplata family snack avto; do
    if [ -d "$R/var/lib/$p" ]; then printf '  %-12s %s\n' "$p" "$(du -sh --apparent-size "$R/var/lib/$p" | cut -f1)"; fi
  done
  if [ -d "$R/opt/laf" ]; then printf '  %-12s %s (база: %s)\n' laf "$(du -sh --apparent-size "$R/opt/laf" | cut -f1)" "$LAF_DB"; fi
  echo
  echo "Файлы (sha256, байт, путь):"
  (cd "$R" && find . -type f -printf '%P\0' | sort -z | while IFS= read -r -d '' f; do
     printf '%s  %s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$(stat -c %s "$f")" "$f"; done)
} > "$T/MANIFEST.txt"
mv "$T/MANIFEST.txt" "$R/MANIFEST.txt"

tar -C "$T" -czf - "$NAME"
