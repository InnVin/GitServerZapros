// GitServerZapros: страница состояния выкладки — http://<IP>/status (и /status.json).
//   node status.mjs put <name> <branch> <sha> <дата коммита> <sha на GitHub> <итог>  — записать проект и пересобрать страницу
//   node status.mjs                                                                — только пересобрать страницу
// Итог: ok (обновлён), same (без изменений), fetch / ff / after (ошибка шага), absent (проекта нет на этом сервере).
// На странице нет текстов коммитов и секретов: только версия, даты и совпадение с GitHub.
import fs from "node:fs";
import path from "node:path";

const DIR = process.env.GSZ_STATUS || "/var/lib/gsz/status";
const WWW = process.env.GSZ_WWW || "/var/lib/gsz/www";
const PROJECTS = process.env.GSZ_PROJECTS || "/opt/gsz/projects.json";
const NAME_RE = /^[a-z0-9-]+$/;

const readJson = (f, d) => { try { return JSON.parse(fs.readFileSync(f, "utf8")); } catch { return d; } };
const writeAtomic = (f, s) => { fs.writeFileSync(f + ".tmp", s); fs.renameSync(f + ".tmp", f); };
const now = new Date().toISOString();

const [cmd, name, branch, sha, cdate, remote, result] = process.argv.slice(2);
if (cmd === "put") {
  if (!NAME_RE.test(name || "")) { console.error("status: плохое имя проекта"); process.exit(1); }
  fs.mkdirSync(DIR, { recursive: true });
  const f = path.join(DIR, name + ".json");
  const prev = readJson(f, {});
  const cur = { name, branch, sha: sha || "", commit_date: cdate || "", remote_sha: remote || "", result, checked_at: now,
    deployed_at: prev.deployed_at || "" };
  // время выкладки: когда на сервере появилась эта версия
  if (cur.sha && (cur.sha !== prev.sha || !cur.deployed_at)) cur.deployed_at = now;
  if (!cur.sha) cur.deployed_at = "";
  writeAtomic(f, JSON.stringify(cur, null, 1));
}

// ---------- сборка страницы ----------
const env = Object.fromEntries((() => { try { return fs.readFileSync("/etc/innvin/server.env", "utf8"); } catch { return ""; } })()
  .split("\n").filter(l => /^[A-Z_0-9]+=/.test(l)).map(l => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1).trim()]));
const SERVER = { msk: "Москва" }[env.SERVER] || env.SERVER || "сервер";
const repos = Object.entries(readJson(PROJECTS, {})).map(([repo, v]) => ({ repo, ...v }));
const fmt = new Intl.DateTimeFormat("ru-RU", { timeZone: "Europe/Moscow", day: "2-digit", month: "2-digit", year: "2-digit", hour: "2-digit", minute: "2-digit" });
const t = s => { const d = new Date(s); return s && !isNaN(d) ? fmt.format(d).replace(",", "") : "—"; };
const esc = s => String(s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

const STATE = {
  absent: ["na", "не установлен на этом сервере"],
  fetch: ["bad", "нет связи с GitHub (git fetch)"],
  ff: ["bad", "не обновлён: нужна ручная проверка"],
  after: ["bad", "обновлён, но шаг после обновления с ошибкой"],
};
const rows = repos.map(p => {
  const s = readJson(path.join(DIR, p.name + ".json"), null);
  const short = s && s.sha ? s.sha.slice(0, 7) : "";
  let github = "unknown", cls = "warn", text = "ещё не проверялся";
  if (s) {
    if (STATE[s.result]) { [cls, text] = STATE[s.result]; github = s.result === "absent" ? "absent" : "unknown"; }
    else if (!s.remote_sha) { cls = "warn"; text = "нет ответа GitHub"; }
    else if (s.remote_sha === s.sha) { github = "match"; cls = "ok"; text = "совпадает с GitHub"; }
    else { github = "differs"; cls = "warn"; text = "отличается от GitHub (там " + s.remote_sha.slice(0, 7) + ")"; }
    if (s.result === "after" && github === "unknown") github = s.remote_sha && s.remote_sha === s.sha ? "match" : "differs";
  }
  return { project: p.repo.split("/").pop(), name: p.name, branch: p.branch, sha: short, commit_date: s ? s.commit_date : "",
    deployed_at: s ? s.deployed_at : "", checked_at: s ? s.checked_at : "", github, result: s ? s.result : "", cls, text };
});

fs.mkdirSync(WWW, { recursive: true });
writeAtomic(path.join(WWW, "status.json"), JSON.stringify({ server: env.SERVER || "", generated_at: now,
  projects: rows.map(({ cls, text, ...r }) => r) }, null, 1) + "\n");

const ok = rows.filter(r => r.cls === "ok").length, live = rows.filter(r => r.cls !== "na").length;
const html = `<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><meta http-equiv="refresh" content="60">
<title>Выкладка · ${esc(SERVER)}</title>
<style>
:root{--bg:#f6f6f4;--card:#fff;--ink:#1c1b1a;--muted:#6b6862;--line:#e7e5e1;--ok:#1e7d45;--warn:#a86400;--bad:#b42318;color-scheme:light}
@media (prefers-color-scheme:dark){:root{--bg:#111113;--card:#1a1a1d;--ink:#f0efec;--muted:#a19e97;--line:#2a2a2e;--ok:#4cc27e;--warn:#e7a33c;--bad:#f0645a;color-scheme:dark}}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:960px;margin:0 auto;padding:24px 16px}
h1{font-size:22px;margin:0 0 4px}p{margin:0 0 16px;color:var(--muted)}
.wrap{overflow-x:auto;background:var(--card);border:1px solid var(--line);border-radius:14px}
table{border-collapse:collapse;width:100%;min-width:720px}
th,td{text-align:left;padding:10px 12px;border-bottom:1px solid var(--line);white-space:nowrap}
th{font-size:12px;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.04em}
tr:last-child td{border-bottom:0}code{font:13px ui-monospace,Consolas,monospace}
.ok{color:var(--ok)}.warn{color:var(--warn)}.bad{color:var(--bad)}.na{color:var(--muted)}
</style></head><body><main>
<h1>Выкладка проектов</h1>
<p>${esc(SERVER)} · совпадают с GitHub: ${ok} из ${live} · обновлено ${t(now)} МСК</p>
<div class="wrap"><table>
<tr><th>Проект</th><th>Ветка</th><th>Версия</th><th>Коммит от</th><th>Выложено</th><th>Проверено</th><th>Состояние</th></tr>
${rows.map(r => `<tr><td><b>${esc(r.project)}</b></td><td>${esc(r.branch)}</td><td><code>${esc(r.sha || "—")}</code></td><td>${t(r.commit_date)}</td><td>${t(r.deployed_at)}</td><td>${t(r.checked_at)}</td><td class="${r.cls}">${r.cls === "ok" ? "✓ " : r.cls === "na" ? "" : "⚠ "}${esc(r.text)}</td></tr>`).join("\n")}
</table></div>
<p style="margin-top:12px">Время — московское. Проверка всех проектов — раз в 5 минут и сразу после каждого коммита. Данные: <a href="status.json" style="color:inherit">status.json</a></p>
</main></body></html>
`;
writeAtomic(path.join(WWW, "status.html"), html);
