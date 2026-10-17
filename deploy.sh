#!/bin/bash
# GitServerZapros: обновить один проект (deploy.sh <name>) или все (deploy.sh --all).
set -uo pipefail
PROJECTS=${GSZ_PROJECTS:-/opt/gsz/projects.json}

names() { node -e 'for (const v of Object.values(require(process.argv[1]))) console.log(v.name)' "$PROJECTS"; }
field() { node -e 'const v=Object.values(require(process.argv[1])).find(x=>x.name===process.argv[2]); process.stdout.write(String((v||{})[process.argv[3]]||""))' "$PROJECTS" "$1" "$2"; }

deploy_one() {
  local name=$1 dir branch after old new
  dir=$(field "$name" dir); branch=$(field "$name" branch); after=$(field "$name" after)
  [ -n "$dir" ] && [ -d "$dir/.git" ] || { echo "$name: нет папки $dir"; return 1; }
  exec 9>"/run/gsz-$name.lock"; flock 9
  cd "$dir" || return 1
  git fetch -q origin "$branch" || { echo "$name: git fetch не прошёл"; return 1; }
  old=$(git rev-parse HEAD); new=$(git rev-parse "origin/$branch")
  [ "$old" = "$new" ] && return 0
  git merge -q --ff-only "origin/$branch" || { echo "$name: не fast-forward, нужна ручная проверка"; return 1; }
  echo "$name: ${old:0:7} -> ${new:0:7}"
  if [ -n "$after" ]; then OLD=$old NEW=$new bash -c "$after" || echo "$name: шаг после обновления с ошибкой"; fi
}

if [ "${1:-}" = "--all" ]; then
  rc=0; for n in $(names); do ( deploy_one "$n" ) || rc=1; done; exit $rc
else
  deploy_one "$1"
fi
