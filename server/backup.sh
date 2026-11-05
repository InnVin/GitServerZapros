#!/bin/bash
# InnVin: копия данных проектов одним архивом tar.gz в stdout. На сервере — /usr/local/sbin/innvin-backup (ставит install.sh).
#   ssh msk innvin-backup > innvin-ГГГГ-ММ-ДД.tar.gz      (каждый день делает ПК владельца: pc/backup-msk.ps1)
# Состав: базы SQLite (целостная копия .backup, службы не останавливаются) FamilyTree и DKP, копии DKP,
# данные Квартплаты и Мелочей, Автоподбор (отчёты, настройки, фото; видео не входит). LaF (тестовый стенд) и
# секреты из /etc не входят. Внутри — MANIFEST.txt: дата, сервер, размеры, sha256 каждого файла.
# Восстановить: tar -xzf innvin-ДАТА.tar.gz → папка innvin-ДАТА/var/lib/... — вернуть нужное в /var/lib/<проект>/
# (служба проекта остановлена, владелец файлов — как был), затем запустить службу.
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
put /var/lib/snack/data
put /var/lib/avto/reports
put /var/lib/avto/photos --exclude='*.mp4' --exclude='*.MP4' --exclude='*.mov' --exclude='*.MOV' --exclude='*.webm' --exclude='*.WEBM'
put /var/lib/avto/prefs.json
put /var/lib/avto/config.json
db /var/lib/avto/dkp/dkp.db
put /var/lib/avto/dkp/backups

{
  echo "InnVin — копия данных проектов"
  echo "Дата:   $(date -u '+%F %H:%M UTC') ($(TZ=Europe/Moscow date '+%H:%M') МСК)"
  echo "Сервер: $SERVER $PUBLIC_IP ($(hostname))"
  echo "Файлов: $(find "$R" -type f | wc -l), всего $(du -sh --apparent-size "$R" | cut -f1)"
  echo
  echo "Размеры по проектам:"
  for p in familytree dkp kvartplata snack avto; do
    if [ -d "$R/var/lib/$p" ]; then printf '  %-12s %s\n' "$p" "$(du -sh --apparent-size "$R/var/lib/$p" | cut -f1)"; fi
  done
  echo
  echo "Файлы (sha256, байт, путь):"
  (cd "$R" && find . -type f -printf '%P\0' | sort -z | while IFS= read -r -d '' f; do
     printf '%s  %s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$(stat -c %s "$f")" "$f"; done)
} > "$T/MANIFEST.txt"
mv "$T/MANIFEST.txt" "$R/MANIFEST.txt"

tar -C "$T" -czf - "$NAME"
