import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createSessionRecord, normalizeSessionRecord, resumeSessionRecord, sessionLaunchConflicts } from './session_lifecycle.mjs';

const HOST = '127.0.0.1';
const PORT = 18320;
const dashboardRoot = path.dirname(fileURLToPath(import.meta.url));
const serverPath = fileURLToPath(import.meta.url);
const sessionLifecyclePath = path.join(dashboardRoot, 'session_lifecycle.mjs');
const serverHash = crypto.createHash('sha256').update(fs.readFileSync(serverPath)).update(fs.readFileSync(sessionLifecyclePath)).digest('hex');
const projectRoot = path.resolve(dashboardRoot, '..');
const staticRoot = path.join(dashboardRoot, 'static');
const runtimeRoot = path.join(projectRoot, '.runtime', 'dashboard');
const usageRoot = path.join(runtimeRoot, 'usage');
const googleCatalogRoot = path.join(runtimeRoot, 'google-models');
const accountTrashRoot = path.join(projectRoot, '.runtime', 'account-trash');
const actionsRoot = path.join(runtimeRoot, 'actions');
const readyPath = path.join(runtimeRoot, 'ready.json');
const dashboardSessionPath = path.join(runtimeRoot, 'dashboard-session.json');
const terminalsPath = path.join(runtimeRoot, 'terminals.json');
const sessionsRoot = path.join(projectRoot, '.runtime', 'claude-sessions');
const sessionsPath = path.join(sessionsRoot, 'index.json');
const sessionMigrationPath = path.join(sessionsRoot, 'legacy-migration.json');
const sessionTrashRoot = path.join(sessionsRoot, 'trash');
const claudeHomeRoot = path.join(projectRoot, '.runtime', 'claude-home');
const legacyModesRoot = path.join(projectRoot, 'provider_router', '.ccr-local', 'modes');
const updatesPath = path.join(runtimeRoot, 'updates.json');
const accountProfilesPath = path.join(projectRoot, 'provider_router', '.ccr-local', 'account-profiles.json');
const codexAccountsRoot = path.join(projectRoot, 'provider_router', '.ccr-local', 'codex-accounts');
const codexBinary = path.join(projectRoot, 'provider_router', 'codex-login-runtime', 'codex.exe');
const googleAccountsRoot = path.join(projectRoot, '.runtime', 'challenger', 'accounts', 'google');
const googleRuntimeModelsPath = path.join(projectRoot, 'router_challenger', 'google-runtime-models.json');
const googleRuntimeScript = path.join(projectRoot, 'tools', 'google_project_runtime.ps1');
const settingPath = path.join(projectRoot, 'setting.json');
const removedAccountsPath = path.join(projectRoot, 'provider_router', '.ccr-local', 'removed-accounts.json');
const appliedSettingHashPath = path.join(projectRoot, 'provider_router', '.ccr-local', 'setting.applied.sha256');
const helperScript = path.join(projectRoot, 'tools', 'dashboard_terminal.ps1');
const dispatcherScript = path.join(projectRoot, 'tools', 'dashboard_spawn_terminal.ps1');
const instanceId = crypto.randomBytes(24).toString('base64url');
const activeActions = new Set();
const activeSessionLaunches = new Set();
const AUTO_REFRESH_MS = 5 * 60 * 1000;
const AUTO_REFRESH_START_DELAY_MS = 15_000;
let activeLaunches = 0;

fs.mkdirSync(usageRoot, { recursive: true });
fs.mkdirSync(googleCatalogRoot, { recursive: true });
fs.mkdirSync(accountTrashRoot, { recursive: true });
fs.mkdirSync(actionsRoot, { recursive: true });
fs.mkdirSync(sessionsRoot, { recursive: true });
fs.mkdirSync(sessionTrashRoot, { recursive: true });
fs.mkdirSync(claudeHomeRoot, { recursive: true });

function readJson(file, fallback = null) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}

function writeJson(file, value) {
  const temp = `${file}.${process.pid}.tmp`;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(temp, `${JSON.stringify(value, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
  fs.renameSync(temp, file);
}

function loadOrCreateBootstrapToken() {
  const existing = readJson(dashboardSessionPath, {});
  const createdAt = Date.parse(existing?.createdAt || '');
  const reusable = Number.isFinite(createdAt) && Date.now() - createdAt < 30 * 24 * 60 * 60 * 1000;
  if (reusable && typeof existing?.bootstrapToken === 'string' && /^[A-Za-z0-9_-]{40,80}$/.test(existing.bootstrapToken)) return existing.bootstrapToken;
  const bootstrapToken = crypto.randomBytes(32).toString('base64url');
  writeJson(dashboardSessionPath, { schemaVersion: 1, bootstrapToken, createdAt: new Date().toISOString() });
  return bootstrapToken;
}

function pruneActionStatusFiles() {
  let entries = [];
  try { entries = fs.readdirSync(actionsRoot, { withFileTypes: true }); } catch { return; }
  const cutoff = Date.now() - 24 * 60 * 60 * 1000;
  for (const entry of entries) {
    if (!entry.isFile() || !/^[0-9a-f-]{36}\.json$/i.test(entry.name)) continue;
    const candidate = path.join(actionsRoot, entry.name);
    try { if (fs.statSync(candidate).mtimeMs < cutoff) fs.unlinkSync(candidate); } catch { }
  }
}

const bootstrapToken = loadOrCreateBootstrapToken();
const sessionCookie = `claude_cli_dashboard=${bootstrapToken}`;
pruneActionStatusFiles();

function safeSessionName(value) {
  if (typeof value !== 'string') return '';
  const normalized = value.trim().replace(/\s+/g, ' ');
  return normalized.length <= 80 && !/[\r\n]/.test(normalized) ? normalized : '';
}

function safeSessionId(value) {
  return typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value) ? value.toLowerCase() : '';
}

function safeId(value) {
  return crypto.createHash('sha256').update(String(value), 'utf8').digest('hex');
}

function usagePath(accountId) {
  return path.join(usageRoot, `${safeId(accountId)}.json`);
}

function googleCatalogPath(accountId) {
  return path.join(googleCatalogRoot, `${safeId(accountId)}.json`);
}

function cachedGoogleModels(accountId) {
  const value = readJson(googleCatalogPath(accountId), {});
  return Array.isArray(value?.models)
    ? value.models.map((model) => typeof model?.displayName === 'string' && model.displayName.trim() ? model.displayName.trim() : String(model?.id || '')).filter(Boolean)
    : [];
}

function cachedGoogleCatalog(accountId) {
  const value = readJson(googleCatalogPath(accountId), {});
  return Array.isArray(value?.models) ? value.models : [];
}

function googleRuntimeModelIds() {
  const value = readJson(googleRuntimeModelsPath, {});
  return new Set(Array.isArray(value?.models)
    ? value.models.filter((model) => typeof model === 'string' && /^[a-z0-9][a-z0-9_.-]{0,127}$/.test(model))
    : []);
}

function buildGoogleRouteCandidates(slot, catalog, supported) {
  const routes = [];
  const accountId = `google:${slot}`;
  const slotNumber = googleSlotNumber(slot);
  if (!slotNumber) return routes;
  for (const model of catalog) {
    const modelId = typeof model?.id === 'string' ? model.id.trim() : '';
    if (!supported.has(modelId)) continue;
    const displayName = typeof model?.displayName === 'string' && model.displayName.trim() ? model.displayName.trim() : modelId;
    const suffix = crypto.createHash('sha256').update(`${slot}\0${modelId}`, 'utf8').digest('hex').slice(0, 12);
    routes.push({
      id: `google-${slotNumber}-${suffix}`,
      name: `Google AI Pro ${slotNumber}: ${displayName}`,
      provider: slot,
      model: modelId,
      kind: 'google',
      accountId,
      slot,
    });
  }
  return routes;
}

function googleRoutes() {
  const supported = googleRuntimeModelIds();
  if (!supported.size) return [];
  const routes = [];
  for (const slot of googleSlots()) {
    const state = googleSlotState(slot);
    if (state.status !== 'ready') continue;
    const accountId = `google:${slot}`;
    routes.push(...buildGoogleRouteCandidates(slot, cachedGoogleCatalog(accountId), supported));
  }
  return routes;
}

function googleCatalogState(accountId) {
  const value = readJson(googleCatalogPath(accountId), {});
  const models = Array.isArray(value?.models) ? value.models : [];
  const rawError = typeof value?.error === 'string' ? value.error : '';
  const error = rawError
    ? (/HTTP 401/.test(rawError)
      ? 'Phiên Google đã hết hạn hoặc không còn được cấp quyền đọc catalog. Hãy xóa slot này và đăng nhập lại đúng tài khoản.'
      : /HTTP 403/.test(rawError)
        ? 'Tài khoản Google không được cấp quyền đọc catalog Antigravity hiện tại.'
        : 'Google chưa trả về catalog model; hãy thử đồng bộ lại sau.')
    : undefined;
  return {
    status: models.length ? 'available' : error ? 'error' : 'unknown',
    observedAt: typeof value?.observedAt === 'string' ? value.observedAt : null,
    source: typeof value?.source === 'string' ? value.source : 'Google Antigravity dynamic catalog',
    ...(error ? { error } : {}),
  };
}

function emptyUsage(message = '') {
  return { status: 'idle', observedAt: null, source: 'Chưa có dữ liệu', experimental: true, groups: [], message };
}

function cachedUsage(accountId, fallback) {
  const value = readJson(usagePath(accountId));
  return value?.schemaVersion === 1 && value?.accountId === accountId ? value.usage : fallback;
}

function readRoutes() {
  const routes = [];
  const accountIndex = readJson(accountProfilesPath, { profiles: [] });
  for (const profile of Array.isArray(accountIndex?.profiles) ? accountIndex.profiles : []) {
    if (!profile || profile.enabled === false || typeof profile.id !== 'string' || typeof profile.provider !== 'string' || typeof profile.model !== 'string') continue;
    if (!/^[a-z0-9][a-z0-9_.-]{0,62}$/.test(profile.id)) continue;
    routes.push({ id: profile.id, name: String(profile.name || `${profile.provider} [${profile.model}]`), provider: profile.provider, model: profile.model, kind: 'codex' });
  }
  const setting = readJson(settingPath, { profiles: [], providers: [] });
  for (const profile of Array.isArray(setting?.profiles) ? setting.profiles : []) {
    if (!profile || profile.enabled === false || typeof profile.id !== 'string' || typeof profile.provider !== 'string' || typeof profile.model !== 'string') continue;
    if (!/^[a-z0-9][a-z0-9-]{0,62}$/.test(profile.id)) continue;
    routes.push({ id: profile.id, name: String(profile.name || `${profile.provider} [${profile.model}]`), provider: profile.provider, model: profile.model, kind: 'api' });
  }
  routes.push(...googleRoutes());
  return routes;
}

function inferCodexPlan(label, models) {
  if (models.some((model) => /sol/i.test(model)) || /plus|pro/i.test(label)) return 'Plus';
  return 'Free';
}

function safeAccountKey(value) {
  return typeof value === 'string' && /^[a-z0-9][a-z0-9_.-]{0,62}$/i.test(value) ? value : '';
}

function safeCodexLabel(value) {
  return typeof value === 'string' && value.length <= 100 && /^[a-z0-9][a-z0-9_.+@ -]*$/i.test(value) ? value : '';
}

function safeGoogleLoginHint(value) {
  if (value === undefined || value === null || value === '') return '';
  if (typeof value !== 'string' || value.length > 254 || /[\r\n]/.test(value)) return null;
  const normalized = value.trim();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized) ? normalized : null;
}

function codexHomeEntries() {
  try {
    return fs.readdirSync(codexAccountsRoot, { withFileTypes: true })
      .filter((item) => item.isDirectory() && safeAccountKey(item.name))
      .map((item) => ({ name: item.name, home: path.join(codexAccountsRoot, item.name) }));
  } catch { return []; }
}

function googleSlotNumber(slot) {
  const match = /^google_pro_([1-9][0-9]{0,2})$/.exec(String(slot));
  const value = match ? Number(match[1]) : 0;
  return value >= 1 && value <= 50 ? value : 0;
}

function googleSlots() {
  const slots = [];
  try {
    for (const entry of fs.readdirSync(googleAccountsRoot, { withFileTypes: true })) {
      if (entry.isDirectory() && googleSlotNumber(entry.name)) slots.push(entry.name);
    }
  } catch { }
  return slots.sort((a, b) => googleSlotNumber(a) - googleSlotNumber(b));
}

function nextGoogleSlot() {
  const occupied = new Set(googleSlots());
  for (let index = 1; index <= 50; index += 1) {
    const slot = `google_pro_${index}`;
    if (!occupied.has(slot)) return slot;
  }
  throw new Error('Đã đạt giới hạn 50 tài khoản Google cục bộ.');
}

function googleSlotState(slot) {
  const slotRoot = path.join(googleAccountsRoot, slot);
  const authRoot = path.join(slotRoot, 'auth');
  let authFiles = [];
  try { authFiles = fs.readdirSync(authRoot, { withFileTypes: true }).filter((item) => item.isFile() && item.name.endsWith('.json')).map((item) => path.join(authRoot, item.name)); } catch { }
  const complete = fs.existsSync(path.join(slotRoot, 'completed.json')) && authFiles.length === 1;
  return { slotRoot, authFiles, status: complete ? 'ready' : authFiles.length ? 'incomplete' : 'not_signed_in' };
}

function buildAccounts(routes) {
  const accounts = [];
  const codexGroups = new Map();
  for (const route of routes.filter((item) => item.kind === 'codex')) {
    const group = codexGroups.get(route.provider) || { models: [], routes: [] };
    if (!group.models.includes(route.model)) group.models.push(route.model);
    group.routes.push(route.id);
    codexGroups.set(route.provider, group);
  }
  for (const [provider, group] of codexGroups) {
    const id = `codex:${provider}`;
    accounts.push({
      id, kind: 'codex', label: provider, plan: inferCodexPlan(provider, group.models), status: 'ready',
      models: group.models, routes: group.routes,
      usage: cachedUsage(id, emptyUsage('Bấm làm mới để đọc hạn mức trực tiếp từ phiên Codex cục bộ.')),
    });
  }

  const activeCodexHomes = new Set([...codexGroups.keys()].map((provider) => findCodexHome(provider)).filter(Boolean).map((home) => path.resolve(home).toLowerCase()));
  for (const entry of codexHomeEntries()) {
    if (activeCodexHomes.has(path.resolve(entry.home).toLowerCase())) continue;
    if (!fs.existsSync(path.join(entry.home, 'auth.json')) || !fs.existsSync(path.join(entry.home, 'account-label.sha256'))) continue;
    const pending = readJson(path.join(entry.home, 'pending-account.json'), {});
    const label = safeCodexLabel(pending?.label) || entry.name;
    const expectedPlan = pending?.expectedPlan === 'codex_plus' ? 'Plus' : inferCodexPlan(label, []);
    const id = `codex-pending:${entry.name}`;
    accounts.push({
      id, kind: 'codex', label, resumeKey: entry.name, plan: expectedPlan, status: 'incomplete', models: [], routes: [],
      usage: emptyUsage('Đăng nhập đã được lưu trong dự án nhưng route chưa tạo xong. Bấm “Hoàn tất nhập” để tiếp tục, không cần đăng nhập lại nếu phiên còn hiệu lực.'),
    });
  }

  for (const slot of googleSlots()) {
    const index = googleSlotNumber(slot);
    const id = `google:${slot}`;
    const state = googleSlotState(slot);
    const fallback = emptyUsage(state.status === 'ready' ? 'Bấm làm mới để đọc hai nhóm Gemini và Claude/GPT.' : 'Chọn Slot bên dưới để đăng nhập Google AI Pro.');
    fallback.groups = [
      { id: 'gemini_models', label: 'Gemini', status: 'unknown', windows: [] },
      { id: 'claude_gpt_models', label: 'Claude / GPT', status: 'unknown', windows: [] },
    ];
    const accountRoutes = routes.filter((route) => route.kind === 'google' && route.accountId === id);
    accounts.push({
      id, kind: 'google', label: `Google AI Pro ${index}`, plan: 'Google AI Pro', status: state.status,
      models: cachedGoogleModels(id), routes: accountRoutes.map((route) => route.id),
      catalog: { ...googleCatalogState(id), routableCount: accountRoutes.length },
      usage: cachedUsage(id, fallback),
    });
  }

  const setting = readJson(settingPath, { providers: [] });
  for (const provider of Array.isArray(setting?.providers) ? setting.providers : []) {
    if (!provider || typeof provider.id !== 'string' || typeof provider.name !== 'string') continue;
    const id = `api:${provider.id}`;
    const providerRoutes = routes.filter((route) => route.kind === 'api' && route.provider === provider.name);
    const hasQuotaPage = typeof provider.quota_page_url === 'string' && Boolean(provider.quota_page_url.trim());
    accounts.push({
      id, kind: 'api', label: provider.name, plan: String(provider.protocol || 'API'),
      providerKey: provider.id,
      quotaPageAvailable: hasQuotaPage,
      status: provider.enabled === false ? 'disabled' : 'ready',
      models: Array.isArray(provider.models) ? provider.models.map(String) : providerRoutes.map((route) => route.model),
      routes: providerRoutes.map((route) => route.id),
      usage: { ...emptyUsage(hasQuotaPage ? 'Provider có trang quota riêng. Dashboard chỉ mở đúng trang HTTPS cùng host và không gửi key trong URL.' : 'API tùy chỉnh không có chuẩn chung cho hạn mức; dashboard chỉ hiển thị khi nhà cung cấp có adapter riêng.'), experimental: false, source: hasQuotaPage ? 'Trang quota do provider cung cấp' : 'Không có API hạn mức chuẩn' },
    });
  }
  return accounts;
}

function discoverTranscriptIds() {
  const ids = new Set();
  const pending = [claudeHomeRoot];
  while (pending.length) {
    const directory = pending.pop();
    let entries = [];
    try { entries = fs.readdirSync(directory, { withFileTypes: true }); } catch { continue; }
    for (const entry of entries) {
      const candidate = path.join(directory, entry.name);
      if (entry.isDirectory()) pending.push(candidate);
      else if (entry.isFile() && entry.name.toLowerCase().endsWith('.jsonl')) {
        const id = safeSessionId(path.basename(entry.name, '.jsonl'));
        if (id) ids.add(id);
      }
    }
  }
  return ids;
}

function sessionTranscriptPaths(sessionId) {
  const id = safeSessionId(sessionId);
  if (!id) return [];
  const matches = [];
  const pending = [claudeHomeRoot];
  while (pending.length) {
    const directory = pending.pop();
    let entries = [];
    try { entries = fs.readdirSync(directory, { withFileTypes: true }); } catch { continue; }
    for (const entry of entries) {
      const candidate = path.resolve(directory, entry.name);
      const relative = path.relative(claudeHomeRoot, candidate);
      if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) continue;
      if (entry.isDirectory()) pending.push(candidate);
      else if (entry.isFile() && entry.name.toLowerCase() === `${id}.jsonl`) matches.push(candidate);
    }
  }
  return matches;
}

function sessionRecords() {
  const records = readJson(sessionsPath, []);
  if (!Array.isArray(records)) return [];
  const transcripts = discoverTranscriptIds();
  const terminalRecords = readJson(terminalsPath, []);
  const origins = new Map();
  if (Array.isArray(terminalRecords)) {
    const ordered = [...terminalRecords].sort((a, b) => Date.parse(a?.startedAt || '') - Date.parse(b?.startedAt || ''));
    for (const terminal of ordered) {
      const id = safeSessionId(terminal?.sessionId);
      if (id && !origins.has(id) && typeof terminal?.routeId === 'string') origins.set(id, terminal);
    }
  }
  return records
    .filter((record) => transcripts.has(safeSessionId(record?.id)) && typeof (record?.originRouteId || record?.routeId) === 'string')
    .map((record) => normalizeSessionRecord(record, origins.get(safeSessionId(record?.id))))
    .map((record) => {
      const id = safeSessionId(record.id);
      return {
        id,
        name: safeSessionName(record.name) || `Phiên ${id.slice(0, 8)}`,
        routeId: String(record.routeId),
        routeName: String(record.routeName || record.routeId),
        model: String(record.model || ''),
        originRouteId: String(record.originRouteId || record.routeId),
        originRouteName: String(record.originRouteName || record.routeName || record.routeId),
        originModel: String(record.originModel || record.model || ''),
        lastRouteId: String(record.lastRouteId || record.routeId),
        lastRouteName: String(record.lastRouteName || record.routeName || record.routeId),
        lastModel: String(record.lastModel || record.model || ''),
        createdAt: String(record.createdAt || new Date(0).toISOString()),
        lastOpenedAt: String(record.lastOpenedAt || record.createdAt || new Date(0).toISOString()),
        migrated: record.migrated === true,
      };
    })
    .sort((a, b) => Date.parse(b.lastOpenedAt) - Date.parse(a.lastOpenedAt))
    .slice(0, 200);
}

function saveSessionRecord(record) {
  const current = sessionRecords().filter((item) => item.id !== record.id);
  writeJson(sessionsPath, [record, ...current].slice(0, 200));
}

function moveSessionToTrash(sessionId) {
  const id = safeSessionId(sessionId);
  const records = readJson(sessionsPath, []);
  if (!id || !Array.isArray(records)) throw new Error('Session Claude không hợp lệ.');
  const record = sessionRecords().find((item) => item.id === id);
  if (!record) throw new Error('Session Claude không còn trong chỉ mục cục bộ.');
  if (readTerminals().some((terminal) => terminal.sessionId === id && terminal.running)) {
    throw new Error('Hãy đóng terminal đang dùng session này trước khi xóa.');
  }
  const sources = sessionTranscriptPaths(id);
  if (!sources.length) throw new Error('Không tìm thấy transcript cục bộ của session này.');

  const trashBatch = path.join(sessionTrashRoot, `${id}-${crypto.randomUUID()}`);
  const moved = [];
  try {
    for (const source of sources) {
      const relative = path.relative(claudeHomeRoot, source);
      const destination = path.join(trashBatch, 'claude-home', relative);
      fs.mkdirSync(path.dirname(destination), { recursive: true });
      fs.renameSync(source, destination);
      moved.push({ source, destination, relative });
    }
    writeJson(path.join(trashBatch, 'manifest.json'), {
      schemaVersion: 1,
      session: record,
      movedAt: new Date().toISOString(),
      files: moved.map((item) => item.relative),
      policy: 'recoverable-project-local-trash',
    });
    writeJson(sessionsPath, records.filter((item) => safeSessionId(item?.id) !== id));
  } catch (error) {
    for (const item of moved.reverse()) {
      try {
        fs.mkdirSync(path.dirname(item.source), { recursive: true });
        fs.renameSync(item.destination, item.source);
      } catch { }
    }
    try { fs.rmSync(trashBatch, { recursive: true, force: true }); } catch { }
    throw error;
  }
  return { session: record, movedFiles: moved.length };
}

function copyLegacySessionFiles(routes) {
  if (readJson(sessionMigrationPath)?.completed === true) return;
  const copied = [];
  const known = new Map(sessionRecords().map((record) => [record.id, record]));
  let modeEntries = [];
  try { modeEntries = fs.readdirSync(legacyModesRoot, { withFileTypes: true }).filter((entry) => entry.isDirectory()); } catch { }
  for (const modeEntry of modeEntries) {
    const sourceProjects = path.join(legacyModesRoot, modeEntry.name, 'projects');
    if (!fs.existsSync(sourceProjects)) continue;
    const route = routes.find((item) => item.id === modeEntry.name);
    const pending = [sourceProjects];
    while (pending.length) {
      const directory = pending.pop();
      let entries = [];
      try { entries = fs.readdirSync(directory, { withFileTypes: true }); } catch { continue; }
      for (const entry of entries) {
        const source = path.join(directory, entry.name);
        if (entry.isDirectory()) { pending.push(source); continue; }
        if (!entry.isFile() || !entry.name.toLowerCase().endsWith('.jsonl')) continue;
        const id = safeSessionId(path.basename(entry.name, '.jsonl'));
        if (!id) continue;
        const relative = path.relative(sourceProjects, source);
        const destination = path.join(claudeHomeRoot, 'projects', relative);
        if (!fs.existsSync(destination)) {
          fs.mkdirSync(path.dirname(destination), { recursive: true });
          fs.copyFileSync(source, destination);
          copied.push(id);
        }
        if (!known.has(id)) {
          const stat = fs.statSync(source);
          const record = createSessionRecord({
            id,
            name: `Phiên cũ ${id.slice(0, 8)}`,
            route: { id: route?.id || modeEntry.name, name: route?.name || modeEntry.name, model: route?.model || '' },
            now: stat.birthtime.toISOString(),
            migrated: true,
          });
          record.lastOpenedAt = stat.mtime.toISOString();
          known.set(id, record);
        }
      }
    }
  }
  writeJson(sessionsPath, [...known.values()].sort((a, b) => Date.parse(b.lastOpenedAt) - Date.parse(a.lastOpenedAt)).slice(0, 200));
  writeJson(sessionMigrationPath, { schemaVersion: 1, completed: true, completedAt: new Date().toISOString(), copiedFiles: copied.length, policy: 'copied-without-reading-or-deleting-source' });
}

function processRunning(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try { process.kill(pid, 0); return true; } catch { return false; }
}

function readTerminals() {
  const records = readJson(terminalsPath, []);
  if (!Array.isArray(records)) return [];
  const normalized = records.slice(-40).map((record) => ({ ...record, running: processRunning(Number(record.pid)) }));
  if (JSON.stringify(records) !== JSON.stringify(normalized)) writeJson(terminalsPath, normalized);
  return normalized.reverse();
}

function clearClosedTerminalHistory() {
  const records = readJson(terminalsPath, []);
  if (!Array.isArray(records)) throw new Error('Lịch sử terminal cục bộ không hợp lệ.');
  const retained = [];
  let removed = 0;
  for (const record of records) {
    if (processRunning(Number(record.pid))) retained.push({ ...record, running: true });
    else removed += 1;
  }
  writeJson(terminalsPath, retained);
  return { removed, retained: retained.length };
}

function activeRouteIds() {
  return new Set(readTerminals().filter((terminal) => terminal.running).map((terminal) => terminal.routeId));
}

function accountTrashDirectory(kind, id) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const target = path.join(accountTrashRoot, `${stamp}-${kind}-${safeId(id).slice(0, 12)}`);
  fs.mkdirSync(target, { recursive: false, mode: 0o700 });
  return target;
}

function assertAccountIdle(account) {
  const active = activeRouteIds();
  const used = account.routes.filter((routeId) => active.has(routeId));
  if (used.length) throw new Error('Hãy đóng terminal đang dùng tài khoản/provider này trước khi xóa.');
  if (readTerminals().some((terminal) => terminal.running)) throw new Error('Để xóa an toàn, hãy đóng mọi terminal Claude đang chạy rồi thử lại.');
}

function syncRouterSettings() {
  const powershell = path.join(process.env.ProgramFiles || 'C:\\Program Files', 'PowerShell', '7', 'pwsh.exe');
  const router = path.join(projectRoot, 'tools', 'router_project_menu.ps1');
  if (!fs.existsSync(powershell) || !fs.existsSync(router)) throw new Error('Thiếu công cụ đồng bộ router cục bộ.');
  const result = spawnSync(powershell, ['-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', router, '-Root', projectRoot, '-SyncSettings'], { cwd: projectRoot, encoding: 'utf8', windowsHide: true, timeout: 45_000, shell: false });
  if (result.status !== 0) throw new Error('Router không xác nhận việc gỡ provider; dữ liệu nguồn chưa bị xóa.');
}

function moveGoogleAccountToTrash(account) {
  const slot = account.id.slice('google:'.length);
  if (!googleSlotNumber(slot)) throw new Error('Slot Google không hợp lệ.');
  const state = googleSlotState(slot);
  if (!fs.existsSync(state.slotRoot)) throw new Error('Slot Google không còn tồn tại.');
  assertAccountIdle(account);
  if (state.status === 'ready') stopGoogleRuntime(slot);
  const trash = accountTrashDirectory('google', slot);
  fs.renameSync(state.slotRoot, path.join(trash, slot));
  for (const cache of [usagePath(account.id), googleCatalogPath(account.id)]) {
    if (fs.existsSync(cache)) fs.renameSync(cache, path.join(trash, path.basename(cache)));
  }
  writeJson(path.join(trash, 'manifest.json'), { schemaVersion: 1, kind: 'google', accountId: account.id, label: account.label, removedAt: new Date().toISOString(), recoverable: true });
  return { trash: path.relative(projectRoot, trash).replaceAll('\\', '/') };
}

function moveApiProviderToTrash(account) {
  if (!account.providerKey) throw new Error('Provider API không có ID ổn định.');
  assertAccountIdle(account);
  const setting = readJson(settingPath);
  if (!setting || !Array.isArray(setting.providers) || !Array.isArray(setting.profiles)) throw new Error('setting.json không hợp lệ.');
  const provider = setting.providers.find((item) => item?.id === account.providerKey);
  if (!provider) throw new Error('Provider API không còn trong setting.json.');
  const next = {
    ...setting,
    providers: setting.providers.filter((item) => item?.id !== account.providerKey),
    profiles: setting.profiles.filter((profile) => profile?.provider !== provider.name),
  };
  const trash = accountTrashDirectory('api', account.providerKey);
  writeJson(path.join(trash, 'setting.before.json'), setting);
  writeJson(path.join(trash, 'manifest.json'), { schemaVersion: 1, kind: 'api', accountId: account.id, label: account.label, removedAt: new Date().toISOString(), recoverable: true });
  writeJson(settingPath, next);
  try {
    try { fs.unlinkSync(appliedSettingHashPath); } catch { }
    syncRouterSettings();
  } catch (error) {
    writeJson(settingPath, setting);
    throw error;
  }
  return { trash: path.relative(projectRoot, trash).replaceAll('\\', '/') };
}

function moveCodexAccountToTrash(account) {
  assertAccountIdle(account);
  const pending = account.id.startsWith('codex-pending:');
  const providerName = pending ? '' : account.label;
  const home = pending && account.resumeKey ? path.join(codexAccountsRoot, account.resumeKey) : findCodexHome(account.label);
  if (!home || !fs.existsSync(home)) throw new Error('Không tìm thấy thư mục đăng nhập Codex cục bộ.');
  const profileIndex = readJson(accountProfilesPath, { schemaVersion: 1, profiles: [] });
  const trash = accountTrashDirectory('codex', pending ? account.resumeKey : account.label);
  writeJson(path.join(trash, 'account-profiles.before.json'), profileIndex);
  writeJson(path.join(trash, 'manifest.json'), { schemaVersion: 1, kind: 'codex', accountId: account.id, label: account.label, removedAt: new Date().toISOString(), recoverable: true });
  if (providerName) {
    const removed = readJson(removedAccountsPath, { schemaVersion: 1, providers: [] });
    const providers = Array.isArray(removed?.providers) ? removed.providers.filter((item) => item?.name !== providerName) : [];
    providers.push({ name: providerName, removedAt: new Date().toISOString() });
    writeJson(removedAccountsPath, { schemaVersion: 1, providers });
    syncRouterSettings();
  }
  const profiles = Array.isArray(profileIndex?.profiles) ? profileIndex.profiles.filter((profile) => profile?.provider !== providerName) : [];
  writeJson(accountProfilesPath, { schemaVersion: 1, profiles });
  fs.renameSync(home, path.join(trash, path.basename(home)));
  if (fs.existsSync(usagePath(account.id))) fs.renameSync(usagePath(account.id), path.join(trash, path.basename(usagePath(account.id))));
  return { trash: path.relative(projectRoot, trash).replaceAll('\\', '/') };
}

function moveAccountToTrash(account) {
  if (account.kind === 'google') return moveGoogleAccountToTrash(account);
  if (account.kind === 'api') return moveApiProviderToTrash(account);
  if (account.kind === 'codex') return moveCodexAccountToTrash(account);
  throw new Error('Loại tài khoản không được hỗ trợ.');
}

function binaryVersion() {
  const binary = path.join(projectRoot, 'bin', 'claude.exe');
  if (!fs.existsSync(binary)) return 'chưa cài';
  const result = spawnSync(binary, ['--version'], { cwd: projectRoot, encoding: 'utf8', timeout: 6000, windowsHide: true });
  const match = `${result.stdout || ''} ${result.stderr || ''}`.match(/\d+\.\d+\.\d+/);
  if (match?.[0]) return match[0];
  const state = (() => { try { return fs.readFileSync(path.join(projectRoot, '40-State', 'CURRENT_STATE.md'), 'utf8'); } catch { return ''; } })();
  return state.match(/Claude Code [`"]?(\d+\.\d+\.\d+)/i)?.[1] || 'đã cài';
}

const claudeVersion = binaryVersion();
const routerPackage = readJson(path.join(projectRoot, 'provider_router', 'node_modules', '@musistudio', 'claude-code-router', 'package.json'), {});
const routerVersion = typeof routerPackage?.version === 'string' ? routerPackage.version : 'chưa cài';

function gitCommitDate(directory) {
  const result = spawnSync('git', ['-C', directory, 'log', '-1', '--format=%cI'], { cwd: projectRoot, encoding: 'utf8', timeout: 5000, windowsHide: true });
  const value = String(result.stdout || '').trim();
  return result.status === 0 && !Number.isNaN(Date.parse(value)) ? value : null;
}

function versionKey(value) {
  return String(value || '').trim().replace(/^rust-v/i, '').replace(/^v/i, '').replace(/^claude-code-/i, '');
}

function compareVersions(left, right) {
  const parse = (value) => {
    const normalized = versionKey(value);
    const match = normalized.match(/^(\d+)\.(\d+)\.(\d+)(.*)$/);
    return match ? { numbers: match.slice(1, 4).map(Number), suffix: match[4] || '' } : null;
  };
  const a = parse(left); const b = parse(right);
  if (!a || !b) return versionKey(left) === versionKey(right) ? 0 : null;
  for (let index = 0; index < 3; index += 1) {
    if (a.numbers[index] !== b.numbers[index]) return a.numbers[index] > b.numbers[index] ? 1 : -1;
  }
  if (!a.suffix && b.suffix) return 1;
  if (a.suffix && !b.suffix) return -1;
  return a.suffix === b.suffix ? 0 : a.suffix.localeCompare(b.suffix, 'en', { numeric: true });
}

function updateStatus(localVersion, latestVersion) {
  const comparison = compareVersions(localVersion, latestVersion);
  if (comparison === null) return versionKey(localVersion) === versionKey(latestVersion) ? 'current' : 'available';
  return comparison >= 0 ? 'current' : 'available';
}

let localUpdateSnapshot = null;

function localUpdateState() {
  const cached = readJson(updatesPath, { checkedAt: null, latest: {}, errors: {} });
  if (!localUpdateSnapshot) {
    const challengerSource = readJson(path.join(projectRoot, 'router_challenger', 'SOURCE.json'), {});
    const challengerBuild = readJson(path.join(projectRoot, 'router_challenger', 'BUILD.json'), {});
    const routerSource = readJson(path.join(projectRoot, 'provider_router', 'SOURCE.json'), {});
    const codexSource = readJson(path.join(projectRoot, 'provider_router', 'CODEX_LOGIN_SOURCE.json'), {});
    const projectUpdatedAt = gitCommitDate(projectRoot);
    const codexHelperVersion = (() => {
      if (!fs.existsSync(codexBinary)) return 'chưa cài';
      const result = spawnSync(codexBinary, ['--version'], { cwd: projectRoot, encoding: 'utf8', timeout: 5000, windowsHide: true });
      return String(result.stdout || result.stderr || '').trim().split(/\s+/).pop() || 'đã cài';
    })();
    localUpdateSnapshot = {
      lastProjectUpdateAt: projectUpdatedAt,
      components: [
        { id: 'claude', label: 'Claude Code', localVersion: claudeVersion, lastUpdatedAt: projectUpdatedAt, source: 'anthropics/claude-code' },
        { id: 'router', label: 'Claude Code Router', localVersion: routerVersion, lastUpdatedAt: routerSource?.reviewed_at || null, source: 'musistudio/claude-code-router' },
        { id: 'codex', label: 'Codex helper', localVersion: codexHelperVersion, lastUpdatedAt: codexSource?.reviewed_at || codexSource?.copied_at || null, source: 'openai/codex' },
        { id: 'challenger', label: 'Google / CLIProxyAPI', localVersion: challengerSource?.source_tag || 'chưa cài', lastUpdatedAt: challengerBuild?.built_at || challengerSource?.reviewed_at || null, source: 'router-for-me/CLIProxyAPI' },
      ],
    };
  }
  const components = localUpdateSnapshot.components.map((component) => {
    const errorMessage = typeof cached?.errors?.[component.id] === 'string' ? cached.errors[component.id] : null;
    return {
      ...component,
      latestVersion: cached?.latest?.[component.id] || null,
      errorMessage,
      status: errorMessage ? 'error' : cached?.latest?.[component.id] ? updateStatus(component.localVersion, cached.latest[component.id]) : 'unchecked',
    };
  });
  return { checkedAt: cached?.checkedAt || null, lastProjectUpdateAt: localUpdateSnapshot.lastProjectUpdateAt, components };
}

async function checkUpdates() {
  const repositories = {
    claude: 'anthropics/claude-code',
    router: 'musistudio/claude-code-router',
    codex: 'openai/codex',
    challenger: 'router-for-me/CLIProxyAPI',
  };
  const previous = readJson(updatesPath, { latest: {} });
  const latest = { ...(previous?.latest || {}) };
  const errors = {};
  const entries = Object.entries(repositories);
  const settled = await Promise.allSettled(entries.map(([, repository]) =>
    fetchJson(`https://api.github.com/repos/${repository}/releases/latest`, { headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'claude-cli-local-dashboard' } })
  ));
  settled.forEach((result, index) => {
    const id = entries[index][0];
    if (result.status === 'fulfilled') latest[id] = String(result.value.tag_name || result.value.name || '').trim() || null;
    else errors[id] = result.reason instanceof Error ? result.reason.message : String(result.reason);
  });
  writeJson(updatesPath, { schemaVersion: 1, checkedAt: new Date().toISOString(), latest, errors });
  return localUpdateState();
}

function routerStatus() {
  const service = readJson(path.join(projectRoot, 'provider_router', '.ccr-local', 'appdata', 'claude-code-router', 'service.json'));
  return service && processRunning(Number(service.pid)) ? 'running' : 'stopped';
}

function buildState() {
  const routes = readRoutes();
  copyLegacySessionFiles(routes);
  return {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    project: { name: 'Claude CLI Control Room', rootLabel: path.basename(projectRoot), isolation: 'Mọi state nằm trong folder dự án' },
    accounts: buildAccounts(routes),
    routes,
    sessions: sessionRecords(),
    terminals: readTerminals(),
    services: { dashboard: 'running', router: routerStatus(), claudeVersion, routerVersion },
    updates: localUpdateState(),
  };
}

function findCodexHome(provider) {
  const expectedHash = crypto.createHash('sha256').update(provider, 'utf8').digest('hex');
  let entries = [];
  try { entries = fs.readdirSync(codexAccountsRoot, { withFileTypes: true }).filter((item) => item.isDirectory()); } catch { }
  for (const entry of entries) {
    const home = path.join(codexAccountsRoot, entry.name);
    try {
      const marker = fs.readFileSync(path.join(home, 'account-label.sha256'), 'utf8').trim().toLowerCase();
      if (marker === expectedHash) return home;
    } catch { }
  }
  const slug = provider.toLowerCase().replace(/[^a-z0-9_.-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 63);
  const fallback = path.join(codexAccountsRoot, slug);
  return fs.existsSync(path.join(fallback, 'auth.json')) ? fallback : null;
}

function numberOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function resetIso(window) {
  const direct = numberOrNull(window?.reset_at ?? window?.resetAt ?? window?.resetsAt);
  if (direct !== null) return new Date(direct < 1e12 ? direct * 1000 : direct).toISOString();
  const after = numberOrNull(window?.reset_after_seconds ?? window?.resetAfterSeconds);
  return after !== null ? new Date(Date.now() + after * 1000).toISOString() : null;
}

function codexChildEnvironment(home, source = process.env) {
  const env = {};
  for (const [name, value] of Object.entries(source)) {
    if (/^(OPENAI|CODEX|CHATGPT|AZURE_OPENAI)_/i.test(name)) continue;
    env[name] = value;
  }
  env.CODEX_HOME = home;
  env.CODEX_SQLITE_HOME = home;
  env.NO_COLOR = '1';
  return env;
}

function durationLabel(seconds, prefix = '') {
  if (seconds === 18000) return `${prefix}5 giờ`;
  if (seconds === 604800) return `${prefix}Hàng tuần`;
  if (seconds >= 28 * 86400 && seconds <= 31 * 86400) return `${prefix}Hàng tháng`;
  if (seconds && seconds % 86400 === 0) return `${prefix}${seconds / 86400} ngày`;
  if (seconds && seconds % 3600 === 0) return `${prefix}${seconds / 3600} giờ`;
  return `${prefix}Hạn mức`;
}

function normalizeCodexUsage(payload) {
  const byId = payload?.rateLimitsByLimitId && typeof payload.rateLimitsByLimitId === 'object' ? payload.rateLimitsByLimitId : null;
  const rateLimit = byId?.codex ?? payload?.rateLimits ?? {};
  const windows = [];
  for (const [key, raw] of [['primary', rateLimit?.primary], ['secondary', rateLimit?.secondary]]) {
    if (!raw || typeof raw !== 'object') continue;
    const used = numberOrNull(raw.usedPercent);
    const durationMins = numberOrNull(raw.windowDurationMins);
    const durationSeconds = durationMins === null ? null : durationMins * 60;
    windows.push({ id: `codex-${key}`, label: durationLabel(durationSeconds), remainingPercent: used === null ? null : Math.max(0, Math.min(100, 100 - used)), resetAt: resetIso(raw) });
  }
  if (rateLimit?.individualLimit && typeof rateLimit.individualLimit === 'object') {
    const individual = rateLimit.individualLimit;
    windows.push({
      id: 'codex-individual-credit', label: 'Tín dụng tháng',
      remainingPercent: numberOrNull(individual.remainingPercent), resetAt: resetIso(individual),
      detail: `Đã dùng ${individual.used ?? '—'} / ${individual.limit ?? '—'} · tự đặt lại theo nhà cung cấp`,
    });
  }
  const credits = rateLimit?.credits && typeof rateLimit.credits === 'object' ? rateLimit.credits : {};
  const resetCreditsAvailable = Math.max(0, Math.trunc(numberOrNull(payload?.rateLimitResetCredits?.availableCount) ?? 0));
  const hasWeekly = windows.some((window) => window.label === 'Hàng tuần');
  return {
    status: windows.length ? 'available' : 'unknown', observedAt: new Date().toISOString(),
    source: 'OpenAI Codex app-server (chính thức)', experimental: false,
    credits: { hasCredits: credits.hasCredits === true, balance: numberOrNull(credits.balance) },
    resetCreditsAvailable,
    detectedPlan: typeof rateLimit?.planType === 'string' ? rateLimit.planType : null,
    groups: [{ id: 'codex', label: 'Codex', status: windows.length ? 'available' : 'unknown', windows }],
    message: windows.length ? (hasWeekly ? 'Quota tự đặt lại theo thời điểm OpenAI trả về; dashboard không tự dùng reset credit.' : 'OpenAI chưa trả về bucket tuần cho tài khoản này; dashboard không lấy bucket tháng giả làm quota tuần.') : 'OpenAI không trả về cửa sổ hạn mức có thể nhận dạng.',
  };
}

async function fetchJson(url, options) {
  const response = await fetch(url, { ...options, signal: AbortSignal.timeout(20_000) });
  const text = await response.text();
  let payload = null;
  try { payload = JSON.parse(text); } catch { }
  if (!response.ok) throw new Error(`Nhà cung cấp trả về HTTP ${response.status}.`);
  if (!payload || typeof payload !== 'object') throw new Error('Nhà cung cấp trả về dữ liệu không nhận dạng được.');
  return payload;
}

async function refreshCodex(account) {
  const home = findCodexHome(account.label);
  if (!home) throw new Error('Không tìm thấy phiên Codex cục bộ tương ứng. Hãy đăng nhập lại từ dashboard.');
  if (!fs.existsSync(codexBinary)) throw new Error('Thiếu Codex helper cục bộ để đọc hạn mức chính thức.');
  const payload = await new Promise((resolve, reject) => {
    const env = codexChildEnvironment(home);
    const child = spawn(codexBinary, ['app-server', '--stdio'], { cwd: projectRoot, env, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'], shell: false });
    let stdout = '';
    let settled = false;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { child.kill(); } catch { }
      if (error) reject(error); else resolve(value);
    };
    const send = (message) => child.stdin.write(`${JSON.stringify(message)}\n`);
    const timer = setTimeout(() => finish(new Error('Codex app-server không trả về hạn mức trong 20 giây.')), 20_000);
    child.on('error', (error) => finish(new Error(`Không thể mở Codex app-server: ${error.message}`)));
    child.stderr.resume();
    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString('utf8');
      while (stdout.includes('\n')) {
        const index = stdout.indexOf('\n');
        const line = stdout.slice(0, index).trim();
        stdout = stdout.slice(index + 1);
        if (!line) continue;
        let message;
        try { message = JSON.parse(line); } catch { continue; }
        if (message.id === 1 && message.result) {
          send({ method: 'initialized', params: {} });
          send({ id: 2, method: 'account/rateLimits/read', params: {} });
        } else if (message.id === 1 && message.error) {
          finish(new Error('Codex app-server từ chối khởi tạo.'));
        } else if (message.id === 2 && message.result) {
          finish(null, message.result);
        } else if (message.id === 2 && message.error) {
          finish(new Error('Codex app-server không đọc được hạn mức; phiên cục bộ có thể cần đăng nhập lại.'));
        }
      }
    });
    child.on('exit', (code) => { if (!settled) finish(new Error(`Codex app-server đóng sớm (mã ${code ?? 'không rõ'}).`)); });
    send({ id: 1, method: 'initialize', params: { clientInfo: { name: 'claude-cli-local-dashboard', version: '1.0.0' }, capabilities: { experimentalApi: true } } });
  });
  return normalizeCodexUsage(payload);
}

function firstString(record, names) {
  for (const name of names) if (typeof record?.[name] === 'string' && record[name].trim()) return record[name].trim();
  return '';
}

function googleAuthContext(state) {
  if (state.status !== 'ready' || state.authFiles.length !== 1) throw new Error('Slot Google này chưa đăng nhập hoàn chỉnh.');
  const auth = readJson(state.authFiles[0]);
  const nested = auth?.metadata && typeof auth.metadata === 'object' ? auth.metadata : {};
  const accessToken = firstString(auth, ['access_token', 'accessToken']) || firstString(nested, ['access_token', 'accessToken']);
  const project = firstString(auth, ['project_id', 'projectId']) || firstString(nested, ['project_id', 'projectId']);
  if (!accessToken || !project) throw new Error('Phiên Google thiếu access token hoặc project ID; hãy đăng nhập lại slot này.');
  return { accessToken, project };
}

function normalizeGoogleCatalog(payload) {
  const hidden = new Set(['chat_20706', 'chat_23310', 'tab_flash_lite_preview', 'tab_jump_flash_lite_preview']);
  const models = [];
  const source = payload?.models && typeof payload.models === 'object' && !Array.isArray(payload.models) ? payload.models : {};
  for (const [rawId, metadata] of Object.entries(source)) {
    const id = String(rawId || '').trim();
    if (!id || hidden.has(id) || id.length > 160 || /[\r\n]/.test(id)) continue;
    const displayName = firstString(metadata, ['displayName', 'display_name', 'name']) || id;
    models.push({ id, displayName: displayName.slice(0, 180) });
  }
  return models.sort((a, b) => a.displayName.localeCompare(b.displayName, 'vi'));
}

async function refreshGoogleCatalog(accountId, state, authContext) {
  const headers = { Authorization: `Bearer ${authContext.accessToken}`, 'Content-Type': 'application/json', 'User-Agent': 'antigravity/hub/2.9.1 darwin/arm64' };
  const endpoints = [
    'https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels',
    'https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels',
  ];
  let lastError = null;
  for (const url of endpoints) {
    try {
      const models = normalizeGoogleCatalog(await fetchJson(url, { method: 'POST', headers, body: JSON.stringify({ project: authContext.project }) }));
      if (!models.length) throw new Error('Google không trả về model khả dụng.');
      writeJson(googleCatalogPath(accountId), { schemaVersion: 1, accountId, observedAt: new Date().toISOString(), source: 'Google Antigravity fetchAvailableModels', models });
      return models;
    } catch (error) { lastError = error; }
  }
  writeJson(googleCatalogPath(accountId), { schemaVersion: 1, accountId, observedAt: new Date().toISOString(), source: 'Google Antigravity fetchAvailableModels', models: cachedGoogleCatalog(accountId), error: lastError instanceof Error ? lastError.message : String(lastError || 'unknown') });
  throw lastError || new Error('Google không trả về catalog model.');
}

function classifyGoogleGroup(group) {
  const text = JSON.stringify({ name: group?.display_name ?? group?.displayName, description: group?.description, buckets: group?.buckets?.map((bucket) => ({ name: bucket?.display_name ?? bucket?.displayName, description: bucket?.description })) }).toLowerCase();
  if (text.includes('gemini')) return 'gemini_models';
  if (text.includes('claude') || text.includes('gpt')) return 'claude_gpt_models';
  return '';
}

function normalizeGoogleUsage(payload) {
  const byId = {
    gemini_models: { id: 'gemini_models', label: 'Gemini', status: 'unknown', windows: [] },
    claude_gpt_models: { id: 'claude_gpt_models', label: 'Claude / GPT', status: 'unknown', windows: [] },
  };
  for (const group of Array.isArray(payload?.groups) ? payload.groups : []) {
    const targetId = classifyGoogleGroup(group);
    if (!targetId) continue;
    const target = byId[targetId];
    for (const [index, bucket] of (Array.isArray(group.buckets) ? group.buckets : []).entries()) {
      const fraction = numberOrNull(bucket?.remaining_fraction ?? bucket?.remainingFraction);
      if (fraction === null) continue;
      const reset = firstString(bucket, ['reset_time', 'resetTime']);
      target.windows.push({ id: `${targetId}-${index}`, label: firstString(bucket, ['display_name', 'displayName', 'window']) || 'Hàng tuần', remainingPercent: Math.max(0, Math.min(100, fraction * 100)), resetAt: reset || null, detail: firstString(bucket, ['description']) || undefined });
    }
    if (target.windows.length) target.status = 'available';
  }
  return {
    status: Object.values(byId).some((group) => group.windows.length) ? 'available' : 'unknown',
    observedAt: new Date().toISOString(), source: 'Google Antigravity quota endpoint', experimental: true,
    groups: Object.values(byId), message: 'Google luôn được tách thành hai nhóm Gemini và Claude/GPT; nhóm không được trả về sẽ giữ trạng thái chưa xác định.',
  };
}

async function refreshGoogle(account) {
  const slot = account.id.slice('google:'.length);
  const state = googleSlotState(slot);
  const authContext = googleAuthContext(state);
  const catalogPromise = refreshGoogleCatalog(account.id, state, authContext).catch(() => null);
  const headers = { Authorization: `Bearer ${authContext.accessToken}`, 'Content-Type': 'application/json', 'User-Agent': 'antigravity/cli/local-dashboard' };
  const endpoints = [
    'https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary',
    'https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary',
  ];
  let lastError = null;
  for (const url of endpoints) {
    try {
      const usage = normalizeGoogleUsage(await fetchJson(url, { method: 'POST', headers, body: JSON.stringify({ project: authContext.project }) }));
      await catalogPromise;
      return usage;
    }
    catch (error) { lastError = error; }
  }
  await catalogPromise;
  throw lastError || new Error('Google không trả về hạn mức.');
}

async function refreshUsage(accountId) {
  const state = buildState();
  const account = state.accounts.find((item) => item.id === accountId);
  if (!account) throw new Error('Tài khoản không còn tồn tại trong dự án.');
  if (account.status !== 'ready') throw new Error('Tài khoản chưa sẵn sàng.');
  let usage;
  if (account.kind === 'codex') usage = await refreshCodex(account);
  else if (account.kind === 'google') usage = await refreshGoogle(account);
  else throw new Error('Provider API này chưa có adapter hạn mức an toàn.');
  writeJson(usagePath(accountId), { schemaVersion: 1, accountId, usage });
  return usage;
}

function spawnTerminal(action, ...values) {
  if (!fs.existsSync(helperScript) || !fs.existsSync(dispatcherScript)) throw new Error('Thiếu công cụ mở terminal của dashboard.');
  const candidates = [
    path.join(process.env.ProgramFiles || 'C:\\Program Files', 'PowerShell', '7', 'pwsh.exe'),
    path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
  ];
  const powershell = candidates.find((candidate) => fs.existsSync(candidate));
  if (!powershell) throw new Error('Máy này thiếu PowerShell để mở terminal Claude.');
  const statusPath = path.join(actionsRoot, `${crypto.randomUUID()}.json`);
  const args = ['-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', dispatcherScript, '-Action', action, '-Root', projectRoot, '-StatusPath', statusPath];
  if (values[0] !== undefined) args.push('-Value', String(values[0]));
  if (values[1] !== undefined) args.push('-Extra', String(values[1]));
  if (values[2] !== undefined) args.push('-Label', String(values[2]));
  if (values[3] !== undefined) args.push('-Meta', String(values[3]));
  const result = spawnSync(powershell, args, { cwd: projectRoot, windowsHide: true, encoding: 'utf8', timeout: 10_000, shell: false });
  if (result.status !== 0) throw new Error('Không thể mở terminal riêng của dự án.');
  let launched;
  try { launched = JSON.parse(String(result.stdout || '').trim().split(/\r?\n/).filter(Boolean).at(-1)); } catch { }
  if (!Number.isInteger(launched?.pid) || launched.pid <= 0) throw new Error('Terminal mới không trả về PID hợp lệ.');
  return { pid: launched.pid, statusPath };
}

function stopGoogleRuntime(slot) {
  if (!googleSlotNumber(slot) || !fs.existsSync(googleRuntimeScript)) throw new Error('Thiếu công cụ runtime Google cục bộ.');
  const candidates = [
    path.join(process.env.ProgramFiles || 'C:\\Program Files', 'PowerShell', '7', 'pwsh.exe'),
    path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
  ];
  const powershell = candidates.find((candidate) => fs.existsSync(candidate));
  if (!powershell) throw new Error('Máy này thiếu PowerShell để dừng runtime Google an toàn.');
  const result = spawnSync(powershell, ['-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', googleRuntimeScript, '-Action', 'Stop', '-Slot', slot, '-Root', projectRoot], {
    cwd: projectRoot, windowsHide: true, encoding: 'utf8', timeout: 15_000, shell: false,
  });
  if (result.status !== 0) throw new Error('Không thể xác minh và dừng runtime Google trước khi xóa tài khoản.');
}

async function waitForActionStatus(launch, expected, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const status = readJson(launch.statusPath, {});
    if (status?.status === 'failed') throw new Error('Terminal dự án đã báo lỗi trước khi khởi động xong.');
    if (expected.includes(status?.status)) {
      await new Promise((resolve) => setTimeout(resolve, 650));
      const stable = readJson(launch.statusPath, {});
      if (stable?.status === 'failed' || !processRunning(launch.pid)) throw new Error('Terminal dự án đã đóng ngay sau tín hiệu khởi động.');
      setTimeout(() => { try { fs.unlinkSync(launch.statusPath); } catch { } }, 30_000).unref();
      return stable;
    }
    if (!processRunning(launch.pid)) throw new Error('Terminal dự án đã đóng trước khi khởi động xong.');
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  throw new Error('Terminal dự án chưa xác nhận khởi động trong thời gian cho phép.');
}

async function launchRoute(route, options = {}) {
  activeLaunches += 1;
  const resumeId = safeSessionId(options.resumeId);
  let sessionReserved = false;
  try {
    let record;
    if (resumeId) {
      const terminals = readTerminals();
      if (sessionLaunchConflicts(resumeId, terminals, activeSessionLaunches)) {
        throw new Error('Session này đang mở trong một terminal khác. Hãy đóng terminal đó trước khi mở lại; nếu cần làm song song, hãy mở một session mới bằng cùng account/model.');
      }
      activeSessionLaunches.add(resumeId);
      sessionReserved = true;
      record = sessionRecords().find((item) => item.id === resumeId);
      if (!record) throw new Error('Không tìm thấy session Claude cục bộ này.');
      record = resumeSessionRecord(record, route, new Date().toISOString());
    } else {
      const id = crypto.randomUUID();
      record = createSessionRecord({
        id,
        name: safeSessionName(options.name) || `Phiên ${route.model} ${new Date().toLocaleString('vi-VN')}`.slice(0, 80),
        route,
        now: new Date().toISOString(),
      });
    }
    const launch = route.kind === 'google'
      ? spawnTerminal(resumeId ? 'launch-google-resume' : 'launch-google-new', route.slot, route.model, record.id, record.name)
      : spawnTerminal(resumeId ? 'launch-resume' : 'launch-new', route.id, record.id, record.name);
    await waitForActionStatus(launch, ['claude_starting'], 70_000);
    saveSessionRecord(record);
    const records = readJson(terminalsPath, []);
    const next = Array.isArray(records) ? records.slice(-39) : [];
    next.push({ pid: launch.pid, sessionId: record.id, sessionName: record.name, routeId: route.id, routeName: route.name, model: route.model, startedAt: new Date().toISOString(), running: true });
    writeJson(terminalsPath, next);
    return { pid: launch.pid, session: record };
  } finally {
    if (sessionReserved) activeSessionLaunches.delete(resumeId);
    activeLaunches = Math.max(0, activeLaunches - 1);
  }
}

function securityHeaders(response) {
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('X-Frame-Options', 'DENY');
  response.setHeader('Referrer-Policy', 'no-referrer');
  response.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  response.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'");
}

function json(response, status, payload) {
  securityHeaders(response);
  response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  response.end(JSON.stringify(payload));
}

function authorized(request) {
  return String(request.headers.cookie || '').split(';').map((item) => item.trim()).includes(sessionCookie);
}

function sameOrigin(request) {
  const origin = request.headers.origin;
  return !origin || origin === `http://${HOST}:${PORT}`;
}

async function bodyJson(request) {
  let body = '';
  for await (const chunk of request) {
    body += chunk;
    if (body.length > 8192) throw new Error('Yêu cầu quá lớn.');
  }
  return body ? JSON.parse(body) : {};
}

function serveStatic(request, response, pathname) {
  const requested = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
  const resolved = path.resolve(staticRoot, requested);
  if (resolved !== staticRoot && !resolved.startsWith(`${staticRoot}${path.sep}`)) return json(response, 404, { error: 'Không tìm thấy.' });
  const file = fs.existsSync(resolved) && fs.statSync(resolved).isFile() ? resolved : path.join(staticRoot, 'index.html');
  if (!fs.existsSync(file)) return json(response, 503, { error: 'Dashboard chưa được build. Chạy bộ cài dự án rồi thử lại.' });
  const extension = path.extname(file).toLowerCase();
  const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon' };
  securityHeaders(response);
  response.writeHead(200, { 'Content-Type': types[extension] || 'application/octet-stream', 'Cache-Control': extension === '.html' ? 'no-store' : 'public, max-age=31536000, immutable' });
  fs.createReadStream(file).pipe(response);
}

async function handle(request, response) {
  const url = new URL(request.url || '/', `http://${HOST}:${PORT}`);
  if (url.pathname === '/health') return json(response, 200, { ok: true, service: 'claude-cli-dashboard', instanceId, serverHash });
  if (url.pathname === '/' && url.searchParams.get('session') === bootstrapToken) {
    securityHeaders(response);
    response.writeHead(302, { Location: '/', 'Set-Cookie': `${sessionCookie}; HttpOnly; SameSite=Strict; Path=/` });
    return response.end();
  }
  if (!authorized(request)) return json(response, 401, { error: 'Mở dashboard bằng DASHBOARD.bat để tạo phiên cục bộ an toàn.' });
  if (!sameOrigin(request)) return json(response, 403, { error: 'Nguồn yêu cầu không hợp lệ.' });

  if (request.method === 'GET' && url.pathname === '/api/state') return json(response, 200, buildState());
  if (request.method === 'POST' && url.pathname.startsWith('/api/')) {
    const body = await bodyJson(request);
    if (url.pathname === '/api/launch') {
      const route = readRoutes().find((item) => item.id === body.routeId);
      if (!route) return json(response, 400, { error: 'Route không hợp lệ hoặc đã bị xóa.' });
      const name = body.name === undefined ? '' : safeSessionName(body.name);
      if (body.name && !name) return json(response, 400, { error: 'Tên session phải từ 1 đến 80 ký tự và không được xuống dòng.' });
      return json(response, 200, { ok: true, ...await launchRoute(route, { name }) });
    }
    if (url.pathname === '/api/sessions/resume') {
      const sessionId = safeSessionId(body.sessionId);
      if (!sessionId) return json(response, 400, { error: 'Session Claude không hợp lệ.' });
      const session = sessionRecords().find((item) => item.id === sessionId);
      if (!session) return json(response, 404, { error: 'Session Claude không còn trong chỉ mục cục bộ.' });
      const route = readRoutes().find((item) => item.id === (body.routeId || session.routeId));
      if (!route) return json(response, 400, { error: 'Route cũ không còn dùng được; hãy chọn một route hiện có để mở lại session.' });
      return json(response, 200, { ok: true, ...await launchRoute(route, { resumeId: sessionId }) });
    }
    if (url.pathname === '/api/sessions/delete') {
      const sessionId = safeSessionId(body.sessionId);
      if (!sessionId || body.confirmation !== sessionId) return json(response, 400, { error: 'Xác nhận xóa session không hợp lệ.' });
      return json(response, 200, { ok: true, ...moveSessionToTrash(sessionId) });
    }
    if (url.pathname === '/api/terminals/clear-closed') {
      if (body.confirmation !== 'clear-closed-terminals') return json(response, 400, { error: 'Xác nhận dọn lịch sử terminal không hợp lệ.' });
      return json(response, 200, { ok: true, ...clearClosedTerminalHistory() });
    }
    if (url.pathname === '/api/accounts/codex') {
      if (!['free', 'plus'].includes(body.plan)) return json(response, 400, { error: 'Gói Codex không hợp lệ.' });
      await waitForActionStatus(spawnTerminal('codex', body.plan === 'plus' ? 'codex_plus' : 'codex_free'), ['terminal_ready'], 12_000);
      return json(response, 200, { ok: true });
    }
    if (url.pathname === '/api/accounts/codex/resume') {
      if (!safeAccountKey(body.resumeKey)) return json(response, 400, { error: 'Tài khoản Codex chưa hoàn tất không hợp lệ.' });
      const home = path.join(codexAccountsRoot, body.resumeKey);
      if (!fs.existsSync(path.join(home, 'auth.json')) || !fs.existsSync(path.join(home, 'account-label.sha256'))) return json(response, 404, { error: 'Không còn phiên Codex chưa hoàn tất này.' });
      const pending = readJson(path.join(home, 'pending-account.json'), {});
      const label = safeCodexLabel(pending?.label) || body.resumeKey;
      const plan = pending?.expectedPlan === 'codex_plus' || /plus|pro/i.test(label) ? 'codex_plus' : 'codex_free';
      await waitForActionStatus(spawnTerminal('codex-resume', plan, label), ['terminal_ready'], 12_000);
      return json(response, 200, { ok: true });
    }
    if (url.pathname === '/api/accounts/google') {
      const slot = body.slot ? String(body.slot) : nextGoogleSlot();
      if (!googleSlotNumber(slot)) return json(response, 400, { error: 'Slot Google không hợp lệ.' });
      const loginHint = safeGoogleLoginHint(body.loginHint);
      if (loginHint === null) return json(response, 400, { error: 'Email Google không hợp lệ.' });
      await waitForActionStatus(spawnTerminal('google', slot, loginHint), ['terminal_ready'], 12_000);
      return json(response, 200, { ok: true, slot });
    }
    if (url.pathname === '/api/accounts/remove') {
      if (typeof body.accountId !== 'string' || body.accountId.length > 180) return json(response, 400, { error: 'Tài khoản/provider không hợp lệ.' });
      const account = buildState().accounts.find((item) => item.id === body.accountId);
      if (!account) return json(response, 404, { error: 'Tài khoản/provider không còn tồn tại.' });
      if (body.confirmation !== account.id) return json(response, 400, { error: 'Xác nhận xóa tài khoản/provider không hợp lệ.' });
      return json(response, 200, { ok: true, ...moveAccountToTrash(account) });
    }
    if (url.pathname === '/api/settings/open') {
      const notepad = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'notepad.exe');
      const child = spawn(notepad, [settingPath], { cwd: projectRoot, detached: true, windowsHide: false, stdio: 'ignore' });
      child.unref();
      return json(response, 200, { ok: true });
    }
    if (url.pathname === '/api/providers/quota/open') {
      if (typeof body.providerKey !== 'string' || !/^[a-z0-9][a-z0-9-]{0,62}$/.test(body.providerKey)) return json(response, 400, { error: 'Provider không hợp lệ.' });
      const setting = readJson(settingPath, { providers: [] });
      const provider = (Array.isArray(setting?.providers) ? setting.providers : []).find((item) => item?.id === body.providerKey);
      if (!provider || typeof provider.base_url !== 'string' || typeof provider.quota_page_url !== 'string') return json(response, 404, { error: 'Provider không có trang quota đã cấu hình.' });
      let baseUrl; let quotaUrl;
      try { baseUrl = new URL(provider.base_url); quotaUrl = new URL(provider.quota_page_url); } catch { return json(response, 400, { error: 'URL quota không hợp lệ.' }); }
      if (baseUrl.protocol !== 'https:' || quotaUrl.protocol !== 'https:' || baseUrl.origin !== quotaUrl.origin || quotaUrl.username || quotaUrl.password) return json(response, 400, { error: 'Trang quota phải là HTTPS cùng host với API và không chứa credential.' });
      const rundll32 = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'rundll32.exe');
      const child = spawn(rundll32, ['url.dll,FileProtocolHandler', quotaUrl.href], { cwd: projectRoot, detached: true, windowsHide: false, stdio: 'ignore', shell: false });
      child.unref();
      return json(response, 200, { ok: true });
    }
    if (url.pathname === '/api/usage/refresh') {
      if (typeof body.accountId !== 'string' || body.accountId.length > 180) return json(response, 400, { error: 'Tài khoản không hợp lệ.' });
      if (activeActions.has(body.accountId)) return json(response, 409, { error: 'Tài khoản này đang được làm mới.' });
      activeActions.add(body.accountId);
      try { return json(response, 200, { ok: true, usage: await refreshUsage(body.accountId) }); }
      finally { activeActions.delete(body.accountId); }
    }
    if (url.pathname === '/api/usage/refresh-all') {
      const accounts = buildState().accounts.filter((account) => account.status === 'ready' && account.kind !== 'api');
      const results = [];
      for (const account of accounts) {
        try { await refreshUsage(account.id); results.push({ accountId: account.id, ok: true }); }
        catch (error) { results.push({ accountId: account.id, ok: false, error: error instanceof Error ? error.message : String(error) }); }
      }
      return json(response, 200, { ok: true, results });
    }
    if (url.pathname === '/api/google/models/refresh-all') {
      const accounts = buildState().accounts.filter((account) => account.kind === 'google' && account.status === 'ready');
      if (!accounts.length) {
        return json(response, 400, { error: 'Chưa có tài khoản Google đã đăng nhập để đồng bộ model.' });
      }
      const results = [];
      for (const account of accounts) {
        const slot = account.id.slice('google:'.length);
        try {
          const state = googleSlotState(slot);
          const models = await refreshGoogleCatalog(account.id, state, googleAuthContext(state));
          results.push({ accountId: account.id, ok: true, count: models.length });
        } catch (error) { results.push({ accountId: account.id, ok: false, error: error instanceof Error ? error.message : String(error) }); }
      }
      const succeeded = results.filter((result) => result.ok);
      if (!succeeded.length) {
        return json(response, 502, {
          error: 'Google chưa trả danh sách model cho các tài khoản hiện tại. Không có model nào bị ghi cứng hoặc báo thành công giả.',
          results,
        });
      }
      return json(response, 200, { ok: true, synchronizedAccounts: succeeded.length, results });
    }
    if (url.pathname === '/api/updates/check') {
      return json(response, 200, { ok: true, updates: await checkUpdates() });
    }
    return json(response, 404, { error: 'Thao tác không tồn tại.' });
  }
  if (request.method !== 'GET') return json(response, 405, { error: 'Phương thức không được phép.' });
  return serveStatic(request, response, url.pathname);
}

function runSelfTest() {
  if (!safeCodexLabel('cruxes_hermits7y+renewik@icloud.com')) throw new Error('email-style Codex label was rejected');
  if (safeCodexLabel('unsafe&command')) throw new Error('command metacharacter was accepted in a Codex label');
  if (safeGoogleLoginHint('owner@example.com') !== 'owner@example.com' || safeGoogleLoginHint('bad address') !== null) throw new Error('Google login hint validation failed');
  if (!safeSessionId('1132beb4-1234-4abc-8abc-1234567890ab') || safeSessionId('not-a-session')) throw new Error('Claude session ID validation failed');
  if (resetIso({ resetsAt: 1_800_000_000 }) !== new Date(1_800_000_000 * 1000).toISOString()) throw new Error('official resetsAt timestamp was not normalized');
  const isolated = codexChildEnvironment('D:\\project-local-account', { Path: 'safe-path', OPENAI_API_KEY: 'outside', CODEX_ACCESS_TOKEN: 'outside', CHATGPT_ACCESS_TOKEN: 'outside', AZURE_OPENAI_API_KEY: 'outside' });
  if (isolated.OPENAI_API_KEY || isolated.CODEX_ACCESS_TOKEN || isolated.CHATGPT_ACCESS_TOKEN || isolated.AZURE_OPENAI_API_KEY) throw new Error('external credential environment was inherited');
  if (isolated.Path !== 'safe-path' || isolated.CODEX_HOME !== 'D:\\project-local-account' || isolated.CODEX_SQLITE_HOME !== 'D:\\project-local-account') throw new Error('project-local Codex environment was not established');
  const catalog = normalizeGoogleCatalog({ models: { 'future-model': { displayName: 'Future Model' }, chat_20706: { displayName: 'Internal' } } });
  if (catalog.length !== 1 || catalog[0].id !== 'future-model' || catalog[0].displayName !== 'Future Model') throw new Error('dynamic Google model catalog normalization failed');
  const routeCandidates = buildGoogleRouteCandidates('google_pro_3', [
    { id: 'future-model', displayName: 'Future Model' },
    { id: 'supported-model', displayName: 'Supported Model' },
  ], new Set(['supported-model']));
  if (routeCandidates.length !== 1 || routeCandidates[0].kind !== 'google' || routeCandidates[0].slot !== 'google_pro_3' || routeCandidates[0].model !== 'supported-model') throw new Error('Google catalog-to-runtime route intersection failed');
  if (updateStatus('2.1.250', 'v2.1.247') !== 'current' || updateStatus('0.149.0-alpha.4.1', 'rust-v0.150.1') !== 'available') throw new Error('update version ordering failed');
  process.stdout.write('PASS: dashboard Codex label, Google route intersection, reset timestamp and child-environment self-test\n');
}

if (process.argv.includes('--self-test')) {
  runSelfTest();
  process.exit(0);
}

if (process.argv.includes('--route-summary')) {
  const routes = readRoutes();
  const google = routes.filter((route) => route.kind === 'google');
  process.stdout.write(`${JSON.stringify({ schemaVersion: 1, routeCount: routes.length, googleRouteCount: google.length, googleModels: [...new Set(google.map((route) => route.model))].sort() })}\n`);
  process.exit(0);
}

const server = http.createServer((request, response) => {
  handle(request, response).catch((error) => json(response, 500, { error: error instanceof Error ? error.message : 'Lỗi dashboard.' }));
});

server.on('error', (error) => {
  process.stderr.write(`Dashboard server failed: ${error.message}\n`);
  process.exitCode = 1;
});

server.listen(PORT, HOST, () => {
  writeJson(readyPath, { schemaVersion: 1, pid: process.pid, host: HOST, port: PORT, loopbackOnly: true, instanceId, serverHash, startedAt: new Date().toISOString(), url: `http://${HOST}:${PORT}/?session=${bootstrapToken}` });
  process.stdout.write(`Claude CLI dashboard ready at http://${HOST}:${PORT}\n`);
});

async function refreshReadyAccounts(onlyStale = false) {
  if (activeLaunches > 0) return;
  const accounts = buildState().accounts.filter((account) => account.status === 'ready' && account.kind !== 'api');
  for (const account of accounts) {
    if (activeActions.has(account.id)) continue;
    const cached = readJson(usagePath(account.id));
    const observed = Date.parse(cached?.usage?.observedAt || '');
    if (onlyStale && Number.isFinite(observed) && Date.now() - observed < AUTO_REFRESH_MS) continue;
    activeActions.add(account.id);
    try { await refreshUsage(account.id); } catch { }
    finally { activeActions.delete(account.id); }
  }
}

// Quota/catalog refresh is deliberately delayed so a user can open the first
// Claude terminal without competing with several Codex/Google network probes.
setTimeout(() => void refreshReadyAccounts(true), AUTO_REFRESH_START_DELAY_MS).unref();
setInterval(() => void refreshReadyAccounts(false), AUTO_REFRESH_MS).unref();

function shutdown() {
  try { if (readJson(readyPath)?.pid === process.pid) fs.unlinkSync(readyPath); } catch { }
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 1500).unref();
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
process.on('uncaughtException', (error) => {
  process.stderr.write(`Dashboard uncaught error: ${error instanceof Error ? error.message : 'unknown'}\n`);
  shutdown();
});
process.on('unhandledRejection', (error) => {
  process.stderr.write(`Dashboard rejected operation: ${error instanceof Error ? error.message : 'unknown'}\n`);
});
