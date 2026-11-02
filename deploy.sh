#!/bin/bash
# GitServerZapros: обновить один проект (deploy.sh <name>) или все (deploy.sh --all).
# Поле "user" в projects.json — git выполняется от этого пользователя (папка проекта принадлежит ему).
# Проекта нет на этом сервере (нет папки) — пропуск без ошибки.
# После каждого проекта — его состояние в /var/lib/gsz/status/<name>.json и страница http://<IP>/status (status.mjs).
set -uo pipefail
G=/opt/gsz
PROJECTS=${GSZ_PROJECTS:-$G/projects.json}

names() { node -e 'for (const v of Object.values(require(process.argv[1]))) console.log(v.name)' "$PROJECTS"; }
field() { node -e 'const v=Object.values(require(process.argv[1])).find(x=>x.name===process.argv[2]); process.stdout.write(String((v||{})[process.argv[3]]||""))' "$PROJECTS" "$1" "$2"; }

# состояние: проект, ветка, коммит на сервере, дата коммита, коммит на GitHub (git ls-remote), итог
status() { # status <name> <result>
  local name=$1 result=$2 head="" cdate="" remote=""
  if [ "$result" != absent ]; then
    head=$(g rev-parse HEAD 2>/dev/null)
    cdate=$(g log -1 --format=%cI 2>/dev/null)
    remote=$(g ls-remote -q origin "refs/heads/$branch" 2>/dev/null | cut -f1)
  fi
  flock /run/gsz-status.lock node "$G/status.mjs" put "$name" "$branch" "$head" "$cdate" "$remote" "$result" \
    || echo "$name: состояние не записано"
}

deploy_one() {
  local name=$1 dir after user old new
  dir=$(field "$name" dir); branch=$(field "$name" branch); after=$(field "$name" after); user=$(field "$name" user)
  # setpriv, а не runuser: без сессии PAM — не засоряет журнал каждые 5 минут
  g() { if [ -n "$user" ]; then timeout 120 setpriv --reuid="$user" --regid="$user" --init-groups env HOME="$(getent passwd "$user" | cut -d: -f6)" git "$@"
        else timeout 120 git "$@"; fi; }
  [ -n "$dir" ] && [ -d "$dir/.git" ] || { echo "$name: нет папки $dir — пропуск"; status "$name" absent; return 0; }
  exec 9>"/run/gsz-$name.lock"; flock 9
  cd "$dir" || return 1
  g fetch -q origin "$branch" || { echo "$name: git fetch не прошёл"; status "$name" fetch; return 1; }
  old=$(g rev-parse HEAD); new=$(g rev-parse "origin/$branch")
  if [ "$old" = "$new" ]; then status "$name" same; return 0; fi
  g merge -q --ff-only "origin/$branch" || { echo "$name: не fast-forward, нужна ручная проверка"; status "$name" ff; return 1; }
  echo "$name: ${old:0:7} -> ${new:0:7}"
  local rc=ok
  if [ -n "$after" ]; then OLD=$old NEW=$new bash -c "$after" || { echo "$name: шаг после обновления с ошибкой"; rc=after; }; fi
  status "$name" "$rc"
}

if [ "${1:-}" = "--all" ]; then
  rc=0; for n in $(names); do ( deploy_one "$n" ) || rc=1; done; exit $rc
else
  deploy_one "$1"
fi
