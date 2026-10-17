// GitServerZapros: приёмная сигналов GitHub для всех проектов на сервере.
// Проверяет подпись (GSZ_SECRET), находит проект в projects.json и оставляет отметку
// /var/lib/gsz/triggers/<name>; её видит gsz-deploy@<name>.path и обновляет проект.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const PORT = Number(process.env.GSZ_PORT || 8095);
const SECRET = process.env.GSZ_SECRET || "";
const PROJECTS = process.env.GSZ_PROJECTS || "/opt/gsz/projects.json";
const TRIGGERS = process.env.GSZ_TRIGGERS || "/var/lib/gsz/triggers";
const MAX_BODY = 5 * 1024 * 1024;

if (SECRET.length < 32) { console.error("GSZ_SECRET не задан или короткий"); process.exit(1); }

const projects = () => JSON.parse(fs.readFileSync(PROJECTS, "utf8"));
const NAME_RE = /^[a-z0-9-]+$/;

http.createServer(async (req, res) => {
  const p = String(req.url || "").split("?")[0];
  if (p === "/gsz/health") { res.writeHead(200).end("ok"); return; }
  if (p !== "/gsz/hook" || req.method !== "POST") { res.writeHead(404).end(); return; }

  let size = 0; const chunks = [];
  for await (const c of req) { size += c.length; if (size > MAX_BODY) { res.writeHead(413).end(); return; } chunks.push(c); }
  const raw = Buffer.concat(chunks);
  const sig = Buffer.from(String(req.headers["x-hub-signature-256"] || ""));
  const want = Buffer.from("sha256=" + crypto.createHmac("sha256", SECRET).update(raw).digest("hex"));
  if (sig.length !== want.length || !crypto.timingSafeEqual(sig, want)) { res.writeHead(401).end(); return; }

  const event = req.headers["x-github-event"];
  if (event === "ping") { res.writeHead(204).end(); return; }
  if (event !== "push") { res.writeHead(204).end(); return; }

  let body;
  try { body = JSON.parse(raw.toString("utf8")); } catch { res.writeHead(400).end(); return; }
  const repo = body && body.repository && body.repository.full_name || "";
  let proj;
  try { proj = Object.entries(projects()).find(([k]) => k.toLowerCase() === repo.toLowerCase()); }
  catch (e) { console.error("projects.json:", e.message); res.writeHead(500).end(); return; }
  if (!proj) { console.log(`нет в списке: ${repo}`); res.writeHead(204).end(); return; }

  const [, cfg] = proj;
  if (body.ref !== "refs/heads/" + cfg.branch || !NAME_RE.test(cfg.name)) { res.writeHead(204).end(); return; }
  fs.writeFileSync(path.join(TRIGGERS, cfg.name), new Date().toISOString() + "\n");
  console.log(`сигнал: ${repo} → ${cfg.name}`);
  res.writeHead(202).end();
}).listen(PORT, "127.0.0.1", () => console.log(`GitServerZapros: 127.0.0.1:${PORT}`));
