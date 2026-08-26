import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HOST = '127.0.0.1';
const PORT = 18320;
const dashboardRoot = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(dashboardRoot, '..');
const staticRoot = path.join(dashboardRoot, 'static');
const runtimeRoot = path.join(projectRoot, '.runtime', 'dashboard');
const usageRoot = path.join(runtimeRoot, 'usage');
const readyPath = path.join(runtimeRoot, 'ready.json');
const terminalsPath = path.join(runtimeRoot, 'terminals.json');
const accountProfilesPath = path.join(projectRoot, 'provider_router', '.ccr-local', 'account-profiles.json');
const codexAccountsRoot = path.join(projectRoot, 'provider_router', '.ccr-local', 'codex-accounts');
const googleAccountsRoot = path.join(projectRoot, '.runtime', 'challenger', 'accounts', 'google');
const settingPath = path.join(projectRoot, 'setting.json');
const helperBat = path.join(projectRoot, 'tools', 'dashboard_terminal.bat');
const bootstrapToken = crypto.randomBytes(32).toString('base64url');
const instanceId = crypto.randomBytes(24).toString('base64url');
const sessionCookie = `claude_cli_dashboard=${bootstrapToken}`;
const activeActions = new Set();

fs.mkdirSync(usageRoot, { recursive: true });

function readJson(file, fallback = null) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}

function writeJson(file, value) {
  const temp = `${file}.${process.pid}.tmp`;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(temp, `${JSON.stringify(value, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
  fs.renameSync(temp, file);
}

function safeId(value) {
  return crypto.createHash('sha256').update(String(value), 'utf8').digest('hex');
}

function usagePath(accountId) {
  return path.join(usageRoot, `${safeId(accountId)}.json`);
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
  return routes;
}

function inferCodexPlan(label, models) {
  if (models.some((model) => /sol/i.test(model)) || /plus|pro/i.test(label)) return 'Plus';
  return 'Free';
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

  for (let index = 1; index <= 3; index += 1) {
    const slot = `google_pro_${index}`;
    const id = `google:${slot}`;
    const state = googleSlotState(slot);
    const fallback = emptyUsage(state.status === 'ready' ? 'Bấm làm mới để đọc hai nhóm Gemini và Claude/GPT.' : 'Chọn Slot bên dưới để đăng nhập Google AI Pro.');
    fallback.groups = [
      { id: 'gemini_models', label: 'Gemini', status: 'unknown', windows: [] },
      { id: 'claude_gpt_models', label: 'Claude / GPT', status: 'unknown', windows: [] },
    ];
    accounts.push({ id, kind: 'google', label: `Google AI Pro ${index}`, plan: 'Google AI Pro', status: state.status, models: [], routes: [], usage: cachedUsage(id, fallback) });
  }

  const setting = readJson(settingPath, { providers: [] });
  for (const provider of Array.isArray(setting?.providers) ? setting.providers : []) {
    if (!provider || typeof provider.id !== 'string' || typeof provider.name !== 'string') continue;
    const id = `api:${provider.id}`;
    const providerRoutes = routes.filter((route) => route.kind === 'api' && route.provider === provider.name);
    accounts.push({
      id, kind: 'api', label: provider.name, plan: String(provider.protocol || 'API'),
      status: provider.enabled === false ? 'disabled' : 'ready',
      models: Array.isArray(provider.models) ? provider.models.map(String) : providerRoutes.map((route) => route.model),
      routes: providerRoutes.map((route) => route.id),
      usage: { ...emptyUsage('API tùy chỉnh không có chuẩn chung cho hạn mức; dashboard chỉ hiển thị khi nhà cung cấp có adapter riêng.'), experimental: false, source: 'Không có API hạn mức chuẩn' },
    });
  }
  return accounts;
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

function routerStatus() {
  const service = readJson(path.join(projectRoot, 'provider_router', '.ccr-local', 'appdata', 'claude-code-router', 'service.json'));
  return service && processRunning(Number(service.pid)) ? 'running' : 'stopped';
}

function buildState() {
  const routes = readRoutes();
  return {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    project: { name: 'Claude CLI Control Room', rootLabel: path.basename(projectRoot), isolation: 'Mọi state nằm trong folder dự án' },
    accounts: buildAccounts(routes),
    routes,
    terminals: readTerminals(),
    services: { dashboard: 'running', router: routerStatus(), claudeVersion, routerVersion },
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
  const direct = numberOrNull(window?.reset_at ?? window?.resetAt);
  if (direct !== null) return new Date(direct < 1e12 ? direct * 1000 : direct).toISOString();
  const after = numberOrNull(window?.reset_after_seconds ?? window?.resetAfterSeconds);
  return after !== null ? new Date(Date.now() + after * 1000).toISOString() : null;
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
  const windows = [];
  const addRateLimit = (rateLimit, prefix = '') => {
    if (!rateLimit || typeof rateLimit !== 'object') return;
    for (const [key, raw] of [['primary', rateLimit.primary_window ?? rateLimit.primaryWindow], ['secondary', rateLimit.secondary_window ?? rateLimit.secondaryWindow]]) {
      if (!raw || typeof raw !== 'object') continue;
      const used = numberOrNull(raw.used_percent ?? raw.usedPercent);
      const duration = numberOrNull(raw.limit_window_seconds ?? raw.limitWindowSeconds);
      windows.push({ id: `${prefix || 'main'}-${key}`, label: durationLabel(duration, prefix), remainingPercent: used === null ? null : Math.max(0, Math.min(100, 100 - used)), resetAt: resetIso(raw) });
    }
  };
  addRateLimit(payload.rate_limit ?? payload.rateLimit);
  addRateLimit(payload.code_review_rate_limit ?? payload.codeReviewRateLimit, 'Code review · ');
  const credits = payload.credits && typeof payload.credits === 'object' ? payload.credits : {};
  return {
    status: windows.length ? 'available' : 'unknown', observedAt: new Date().toISOString(),
    source: 'OpenAI account usage endpoint', experimental: true,
    credits: { hasCredits: credits.has_credits === true, balance: numberOrNull(credits.balance) },
    groups: [{ id: 'codex', label: 'Codex', status: windows.length ? 'available' : 'unknown', windows }],
    message: windows.length ? '' : 'OpenAI không trả về cửa sổ hạn mức có thể nhận dạng.',
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
  const auth = readJson(path.join(home, 'auth.json'));
  const tokens = auth?.tokens && typeof auth.tokens === 'object' ? auth.tokens : auth;
  const accessToken = tokens?.access_token ?? tokens?.accessToken;
  const accountId = tokens?.account_id ?? tokens?.accountId;
  if (typeof accessToken !== 'string' || !accessToken) throw new Error('Phiên Codex không có access token hợp lệ; hãy đăng nhập lại.');
  const headers = { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json', 'User-Agent': 'codex_cli_rs/local-dashboard' };
  if (typeof accountId === 'string' && accountId) headers['ChatGPT-Account-Id'] = accountId;
  const payload = await fetchJson('https://chatgpt.com/backend-api/wham/usage', { method: 'GET', headers });
  return normalizeCodexUsage(payload);
}

function firstString(record, names) {
  for (const name of names) if (typeof record?.[name] === 'string' && record[name].trim()) return record[name].trim();
  return '';
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
  if (state.status !== 'ready' || state.authFiles.length !== 1) throw new Error('Slot Google này chưa đăng nhập hoàn chỉnh.');
  const auth = readJson(state.authFiles[0]);
  const nested = auth?.metadata && typeof auth.metadata === 'object' ? auth.metadata : {};
  const accessToken = firstString(auth, ['access_token', 'accessToken']) || firstString(nested, ['access_token', 'accessToken']);
  const project = firstString(auth, ['project_id', 'projectId']) || firstString(nested, ['project_id', 'projectId']);
  if (!accessToken || !project) throw new Error('Phiên Google thiếu access token hoặc project ID; hãy đăng nhập lại slot này.');
  const headers = { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json', 'User-Agent': 'antigravity/cli/local-dashboard' };
  const endpoints = [
    'https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary',
    'https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary',
  ];
  let lastError = null;
  for (const url of endpoints) {
    try { return normalizeGoogleUsage(await fetchJson(url, { method: 'POST', headers, body: JSON.stringify({ project }) })); }
    catch (error) { lastError = error; }
  }
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

function spawnTerminal(action, value) {
  if (!fs.existsSync(helperBat)) throw new Error('Thiếu công cụ mở terminal của dashboard.');
  const comspec = process.env.ComSpec || path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'cmd.exe');
  const child = spawn(comspec, ['/d', '/k', 'call', helperBat, action, value], { cwd: projectRoot, detached: true, windowsHide: false, stdio: 'ignore', shell: false });
  child.unref();
  return child.pid;
}

function launchRoute(route) {
  const pid = spawnTerminal('launch', route.id);
  const records = readJson(terminalsPath, []);
  const next = Array.isArray(records) ? records.slice(-39) : [];
  next.push({ pid, routeId: route.id, routeName: route.name, model: route.model, startedAt: new Date().toISOString(), running: true });
  writeJson(terminalsPath, next);
  return pid;
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
  if (url.pathname === '/health') return json(response, 200, { ok: true, service: 'claude-cli-dashboard', instanceId });
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
      return json(response, 200, { ok: true, pid: launchRoute(route) });
    }
    if (url.pathname === '/api/accounts/codex') {
      if (!['free', 'plus'].includes(body.plan)) return json(response, 400, { error: 'Gói Codex không hợp lệ.' });
      spawnTerminal('codex', body.plan === 'plus' ? 'codex_plus' : 'codex_free');
      return json(response, 200, { ok: true });
    }
    if (url.pathname === '/api/accounts/google') {
      if (!/^google_pro_[1-3]$/.test(body.slot || '')) return json(response, 400, { error: 'Slot Google không hợp lệ.' });
      spawnTerminal('google', body.slot);
      return json(response, 200, { ok: true });
    }
    if (url.pathname === '/api/settings/open') {
      const notepad = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'notepad.exe');
      const child = spawn(notepad, [settingPath], { cwd: projectRoot, detached: true, windowsHide: false, stdio: 'ignore' });
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
    return json(response, 404, { error: 'Thao tác không tồn tại.' });
  }
  if (request.method !== 'GET') return json(response, 405, { error: 'Phương thức không được phép.' });
  return serveStatic(request, response, url.pathname);
}

const server = http.createServer((request, response) => {
  handle(request, response).catch((error) => json(response, 500, { error: error instanceof Error ? error.message : 'Lỗi dashboard.' }));
});

server.on('error', (error) => {
  process.stderr.write(`Dashboard server failed: ${error.message}\n`);
  process.exitCode = 1;
});

server.listen(PORT, HOST, () => {
  writeJson(readyPath, { schemaVersion: 1, pid: process.pid, host: HOST, port: PORT, loopbackOnly: true, instanceId, startedAt: new Date().toISOString(), url: `http://${HOST}:${PORT}/?session=${bootstrapToken}` });
  process.stdout.write(`Claude CLI dashboard ready at http://${HOST}:${PORT}\n`);
});

function shutdown() {
  try { if (readJson(readyPath)?.pid === process.pid) fs.unlinkSync(readyPath); } catch { }
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 1500).unref();
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
