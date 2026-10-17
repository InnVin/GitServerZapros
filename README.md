# GitServerZapros

> Общая инструкция по серверу и выкладке для всех проектов: https://github.com/InnVin/claude-global/blob/main/CLAUDE.md — читать первой.

Общая приёмная сигналов GitHub для всех проектов на сервере JustHost.
Коммит в ветку проекта → GitHub шлёт сигнал → сервер за секунды забирает изменения.

## Как работает
1. GitHub (вебхук) → `https://dkp.194-58-38-8.sslip.io/gsz/hook`.
2. `gsz-receiver` (`receiver.mjs`, порт 127.0.0.1:8095) проверяет подпись общим секретом `/etc/gsz/env`,
   находит репозиторий в `projects.json` и оставляет отметку `/var/lib/gsz/triggers/<name>`.
3. `gsz-deploy@<name>.path` видит отметку и запускает `deploy.sh <name>`: `git fetch` + fast-forward
   в папке проекта, затем команда `after` (переменные `OLD`, `NEW` — коммиты до и после).
4. Запасной таймер `gsz-poll.timer` раз в 5 минут проверяет все проекты.

## Добавить проект
1. Запись в `projects.json`: `"Владелец/Репо": { "name", "dir", "branch", "after" }`.
   `dir` — уже клонированная папка на сервере с доступом к GitHub на чтение.
2. Коммит в `main` — GitServerZapros обновит сам себя и включит слежение за новым проектом.
3. В GitHub у репозитория: Settings → Webhooks → Add webhook — адрес выше, `application/json`,
   секрет из `/etc/gsz/env` (тот же для всех).

## Установка (один раз)
`git clone https://github.com/InnVin/GitServerZapros /opt/gsz && bash /opt/gsz/install.sh`

Журнал: `journalctl -u 'gsz-*' -n 30`. В репозитории нет секретов — только код и список папок.
