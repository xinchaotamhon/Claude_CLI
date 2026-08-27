import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import type { Account, ClaudeSession, DashboardState, Route, UsageWindow } from './types';
import './styles.css';

const EMPTY: DashboardState = {
  schemaVersion: 1,
  generatedAt: '',
  project: { name: 'Claude CLI', rootLabel: 'claude_CLI-V', isolation: 'project-local' },
  accounts: [],
  routes: [],
  sessions: [],
  terminals: [],
  updates: { checkedAt: null, lastProjectUpdateAt: null, components: [] },
  services: { dashboard: 'starting', router: 'unknown', claudeVersion: '—', routerVersion: '—' },
};

async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    ...init,
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', ...(init?.headers ?? {}) },
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error || `Yêu cầu thất bại (${response.status})`);
  return payload as T;
}

function formatReset(value: string | null) {
  if (!value) return 'Chưa có thời gian đặt lại';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'Chưa có thời gian đặt lại';
  const delta = date.getTime() - Date.now();
  if (delta <= 0) return 'Đang đặt lại';
  const minutes = Math.ceil(delta / 60_000);
  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  const mins = minutes % 60;
  if (days > 0) return `Đặt lại sau ${days} ngày ${hours} giờ`;
  if (hours > 0) return `Đặt lại sau ${hours} giờ ${mins} phút`;
  return `Đặt lại sau ${mins} phút`;
}

function Gauge({ window }: { window: UsageWindow }) {
  const percent = window.remainingPercent;
  const safe = percent === null ? 0 : Math.max(0, Math.min(100, percent));
  const tone = percent === null ? 'unknown' : safe <= 20 ? 'danger' : safe <= 45 ? 'warn' : 'good';
  return (
    <div className="usage-row">
      <div className="usage-copy">
        <div className="usage-title-row">
          <span>{window.label}</span>
          <strong className={`percent ${tone}`}>{percent === null ? '—' : `${Math.round(safe)}%`}</strong>
        </div>
        <progress className={`meter ${tone}`} max="100" value={percent === null ? 100 : safe} aria-label={`${window.label}: ${percent ?? 'không rõ'} phần trăm còn lại`} />
        <small>{window.detail || formatReset(window.resetAt)}</small>
      </div>
    </div>
  );
}

function AccountCard({ account, busy, connected, onRefresh, onResume, onOpenQuota, onDelete }: { account: Account; busy: boolean; connected: boolean; onRefresh: (id: string) => void; onResume: (account: Account) => void; onOpenQuota: (account: Account) => void; onDelete: (account: Account) => void }) {
  const statusText = account.status === 'ready' ? 'Đã sẵn sàng' : account.status === 'incomplete' ? 'Đăng nhập chưa xong' : account.status === 'disabled' ? 'Đã tắt' : 'Chưa đăng nhập';
  const windows = account.usage.groups.flatMap((group) => group.windows.map((window) => ({ group, window })));
  return (
    <article className={`account-card account-row ${account.kind}`}>
      <div className="account-head">
        <div className={`provider-mark ${account.kind}`} aria-hidden="true">
          {account.kind === 'codex' ? 'O' : account.kind === 'google' ? 'G' : 'API'}
        </div>
        <div className="account-identity">
          <div className="eyebrow">{account.kind === 'codex' ? 'ChatGPT / Codex' : account.kind === 'google' ? 'Google AI Pro' : 'API tùy chỉnh'}</div>
          <h3>{account.label}</h3>
          <div className="chips">
            <span className={`status-dot ${account.status}`} />
            <span>{statusText}</span>
            <span className="chip">{account.plan}</span>
          </div>
        </div>
        <div className="account-actions">
          <button className="icon-button" disabled={!connected || busy || account.status !== 'ready' || account.kind === 'api'} onClick={() => onRefresh(account.id)} title="Làm mới hạn mức và catalog model"><span className={busy ? 'spin' : ''}>↻</span></button>
          <button className="danger-button" disabled={!connected || busy} onClick={() => onDelete(account)}>{account.kind === 'api' ? 'Xóa provider' : 'Xóa tài khoản'}</button>
        </div>
      </div>

      <div className="model-list">
        {account.models.length ? account.models.map((model) => <span key={model}>{model}</span>) : <span className="muted-chip">Chưa có model</span>}
      </div>

      {(account.status === 'incomplete' || account.status === 'not_signed_in') && account.kind !== 'api' && (
        <button className="wide-button resume-button" disabled={!connected || busy} onClick={() => onResume(account)}>
          {account.kind === 'codex' ? 'Hoàn tất nhập tài khoản' : 'Tiếp tục đăng nhập Google'}
        </button>
      )}
      {account.kind === 'api' && account.quotaPageAvailable && (
        <button className="wide-button resume-button" disabled={!connected || busy} onClick={() => onOpenQuota(account)}>Mở trang quota của provider</button>
      )}

      <div className="usage-panel">
        {windows.map(({ group, window }) => (
          <Gauge key={`${group.id}-${window.id}`} window={{ ...window, label: account.kind === 'google' ? `${group.label} · ${window.label}` : window.label }} />
        ))}
        {!windows.length && (
          <div className="empty-usage">
            <span className="empty-orbit" />
            <div>
              <strong>{account.status === 'ready' ? 'Chưa có số hạn mức' : 'Đăng nhập để đọc hạn mức'}</strong>
              <p>{account.usage.message || 'Bấm làm mới sau khi tài khoản sẵn sàng. Nếu nhà cung cấp không công bố dữ liệu, dashboard sẽ giữ trạng thái chưa xác định.'}</p>
            </div>
          </div>
        )}
      </div>

      {account.kind !== 'api' && (
        <div className="credit-strip">
          <span>Tín dụng bổ sung</span>
          <strong>
            {account.usage.credits
              ? account.usage.credits.hasCredits
                ? account.usage.credits.balance === null
                  ? 'Có tín dụng · chưa rõ số dư'
                  : `Số dư nhà cung cấp: ${account.usage.credits.balance}`
                : 'Không có'
              : 'Chưa xác định'}
          </strong>
          {account.kind === 'codex' && typeof account.usage.resetCreditsAvailable === 'number' && (
            <small>{account.usage.resetCreditsAvailable} reset credit khả dụng · không tự dùng</small>
          )}
        </div>
      )}

      {account.usage.message && windows.length > 0 && <p className="usage-note">{account.usage.message}</p>}

      <footer className="account-foot">
        <span>{account.usage.experimental ? 'Nguồn thử nghiệm, có thể thay đổi' : account.usage.source}</span>
        <span>{account.usage.observedAt ? `Cập nhật ${new Date(account.usage.observedAt).toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' })}` : 'Chưa cập nhật'}</span>
      </footer>
    </article>
  );
}

function App() {
  const [state, setState] = useState<DashboardState>(EMPTY);
  const [selectedRoute, setSelectedRoute] = useState('');
  const [resumeRoutes, setResumeRoutes] = useState<Record<string, string>>({});
  const [sessionName, setSessionName] = useState('');
  const [googleLoginHint, setGoogleLoginHint] = useState('');
  const [loading, setLoading] = useState(true);
  const [dashboardConnected, setDashboardConnected] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ tone: 'ok' | 'error'; text: string } | null>(null);

  const reload = useCallback(async (quiet = false) => {
    if (!quiet) setLoading(true);
    try {
      const snapshot = await api<DashboardState>('/api/state');
      setState(snapshot);
      setDashboardConnected(true);
      setSelectedRoute((current) => current && snapshot.routes.some((route) => route.id === current) ? current : snapshot.routes[0]?.id || '');
      setResumeRoutes((current) => {
        const updated: Record<string, string> = { ...current };
        for (const session of snapshot.sessions) {
          const selected = updated[session.id];
          if (!selected || !snapshot.routes.some((route) => route.id === selected)) {
            updated[session.id] = snapshot.routes.find((route) => route.id === session.routeId)?.id || snapshot.routes[0]?.id || '';
          }
        }
        for (const sessionId of Object.keys(updated)) {
          if (!snapshot.sessions.some((session) => session.id === sessionId)) delete updated[sessionId];
        }
        return updated;
      });
    } catch (error) {
      setDashboardConnected(false);
      if (!quiet) setNotice({ tone: 'error', text: 'Dashboard mất kết nối; đang tự kết nối lại. ' + (error instanceof Error ? error.message : String(error)) });
    } finally {
      if (!quiet) setLoading(false);
    }
  }, []);

  useEffect(() => {
    void reload();
    const timer = window.setInterval(() => void reload(true), 8_000);
    return () => window.clearInterval(timer);
  }, [reload]);

  const selected = useMemo<Route | undefined>(() => state.routes.find((route) => route.id === selectedRoute), [state.routes, selectedRoute]);
  const readyAccounts = state.accounts.filter((account) => account.status === 'ready').length;
  const activeTerminals = state.terminals.filter((terminal) => terminal.running).length;

  async function action(path: string, body?: unknown, success?: string) {
    if (!dashboardConnected) {
      setNotice({ tone: 'error', text: 'Dashboard mất kết nối; đang tự kết nối lại. Vui lòng thử lại sau khi kết nối phục hồi.' });
      return;
    }
    const key = path + JSON.stringify(body ?? {});
    setBusy(key);
    try {
      await api(path, { method: 'POST', body: JSON.stringify(body ?? {}) });
      setNotice({ tone: 'ok', text: success || 'Đã thực hiện.' });
      await new Promise((resolve) => window.setTimeout(resolve, 550));
      await reload(true);
    } catch (error) {
      setNotice({ tone: 'error', text: error instanceof Error ? error.message : String(error) });
    } finally {
      setBusy(null);
    }
  }

  async function deleteSession(session: ClaudeSession) {
    const confirmed = window.confirm(`Xóa session "${session.name}" khỏi Claude CLI?\n\nSession sẽ được chuyển vào thùng rác cục bộ để có thể khôi phục, không bị xóa vĩnh viễn.`);
    if (!confirmed) return;
    await action('/api/sessions/delete', { sessionId: session.id, confirmation: session.id }, `Đã chuyển ${session.name} vào thùng rác cục bộ.`);
  }

  async function clearClosedTerminals() {
    const confirmed = window.confirm('Xóa mọi mục terminal đã đóng khỏi danh sách gần đây?\n\nThao tác này không tắt terminal đang chạy, không xóa session và không xóa transcript.');
    if (!confirmed) return;
    await action('/api/terminals/clear-closed', { confirmation: 'clear-closed-terminals' }, 'Đã dọn các mục terminal đã đóng.');
  }

  async function deleteAccount(account: Account) {
    const noun = account.kind === 'api' ? 'provider' : 'tài khoản';
    const confirmed = window.confirm(`Xóa ${noun} "${account.label}" khỏi dự án?\n\nDữ liệu sẽ được chuyển vào thùng rác cục bộ để có thể khôi phục. Hãy đóng mọi terminal Claude trước khi xóa.`);
    if (!confirmed) return;
    await action('/api/accounts/remove', { accountId: account.id, confirmation: account.id }, `Đã chuyển ${account.label} vào thùng rác cục bộ.`);
  }

  return (
    <div className="app-shell">
      <header className="topbar">
        <div className="brand">
          <div className="brand-glyph"><span /><span /><span /></div>
          <div><strong>Claude CLI Control Room</strong><small>Độc lập trong claude_CLI-V · localhost</small></div>
        </div>
        <div className="service-pills">
          <span><i className={dashboardConnected ? 'live' : 'idle'} /> Dashboard {dashboardConnected ? 'đang kết nối' : 'mất kết nối'}</span>
          <span><i className={state.services.router === 'running' ? 'live' : 'idle'} /> Router {state.services.router === 'running' ? 'đang chạy' : 'đang nghỉ'}</span>
          <button className="quiet-button" onClick={() => void reload()} disabled={loading}>↻ Đồng bộ</button>
        </div>
      </header>

      {!dashboardConnected && <div className="connection-banner" role="alert"><strong>Dashboard mất kết nối</strong><span>{loading ? 'Đang kết nối…' : 'Đang tự kết nối lại… Các nút hành động sẽ mở lại khi kết nối phục hồi.'}</span></div>}

      <main>
        <section className="hero">
          <div>
            <div className="eyebrow coral">BẢNG ĐIỀU KHIỂN CỤC BỘ</div>
            <h1>Một nơi để chọn tài khoản,<br /><span>model và hạn mức.</span></h1>
            <p>Mỗi terminal dùng route riêng theo lựa chọn của bạn. Nhiều terminal có thể dùng cùng tài khoản hoặc các tài khoản khác nhau; cùng tài khoản vẫn chia sẻ một hạn mức.</p>
          </div>
          <div className="summary-grid">
            <div><strong>{readyAccounts}</strong><span>Tài khoản sẵn sàng</span></div>
            <div><strong>{state.routes.length}</strong><span>Route model</span></div>
            <div><strong>{activeTerminals}</strong><span>Terminal đang chạy</span></div>
          </div>
        </section>

        <section className="launch-deck">
          <div className="launch-copy">
            <div className="section-icon">›_</div>
            <div><h2>Mở phiên Claude mới</h2><p>Terminal mới không thay đổi tài khoản của những terminal đang chạy.</p></div>
          </div>
          <div className="launch-controls">
            <label><span>TÊN SESSION (TÙY CHỌN)</span><input value={sessionName} maxLength={80} placeholder="Ví dụ: sửa website buổi sáng" onChange={(event) => setSessionName(event.target.value)} /></label>
            <label><span>TÀI KHOẢN / MODEL</span><select value={selectedRoute} onChange={(event) => setSelectedRoute(event.target.value)} disabled={!state.routes.length}>{state.routes.map((route) => <option key={route.id} value={route.id}>{route.name}</option>)}</select></label>
            <button className="primary-button" disabled={!dashboardConnected || !selected || busy !== null} onClick={() => void action('/api/launch', { routeId: selected?.id, name: sessionName }, `Đã mở terminal với ${selected?.model}.`)}><span>＋</span> Mở terminal</button>
          </div>
        </section>

        <section className="section-block">
          <div className="section-heading">
            <div><div className="eyebrow">TÀI KHOẢN & HẠN MỨC</div><h2>Tình trạng hiện tại</h2></div>
            <button className="quiet-button" disabled={!dashboardConnected || busy !== null || !readyAccounts} onClick={() => void action('/api/usage/refresh-all', {}, 'Đã làm mới các hạn mức có thể đọc.')}>↻ Làm mới tất cả</button>
          </div>
          <p className="section-note">Dashboard tự đọc lại mỗi 5 phút. Quota 5 giờ/tuần tự reset theo nhà cung cấp; bucket tín dụng tháng được hiển thị riêng và không bị gọi là quota tuần.</p>
          <div className="account-grid">
            {state.accounts.map((account) => <AccountCard
              key={account.id}
              account={account}
              busy={busy !== null}
              connected={dashboardConnected}
              onRefresh={(accountId) => void action('/api/usage/refresh', { accountId }, `Đã làm mới ${account.label}.`)}
              onResume={(target) => void (target.kind === 'codex'
                ? action('/api/accounts/codex/resume', { resumeKey: target.resumeKey }, `Đã mở cửa sổ hoàn tất ${target.label}.`)
                : action('/api/accounts/google', { slot: target.id.replace('google:', '') }, `Đã mở lại đăng nhập ${target.label}.`))}
              onOpenQuota={(target) => void action('/api/providers/quota/open', { providerKey: target.providerKey }, `Đã mở trang quota của ${target.label}.`)}
              onDelete={(target) => void deleteAccount(target)}
            />)}
          </div>
        </section>

        <section className="management-grid">
          <article className="manage-card">
            <div className="manage-head"><span className="badge openai">O</span><div><h3>Thêm tài khoản Codex</h3><p>Đăng nhập chính thức bằng trình duyệt và 2FA.</p></div></div>
            <div className="button-row"><button disabled={!dashboardConnected || busy !== null} onClick={() => void action('/api/accounts/codex', { plan: 'free' }, 'Đã mở cửa sổ đăng nhập Codex Free.')}>＋ Codex Free</button><button disabled={!dashboardConnected || busy !== null} onClick={() => void action('/api/accounts/codex', { plan: 'plus' }, 'Đã mở cửa sổ đăng nhập Codex Plus.')}>＋ Codex Plus</button></div>
          </article>
          <article className="manage-card">
            <div className="manage-head"><span className="badge google">G</span><div><h3>Thêm Google AI Pro</h3><p>Nhập email để trang Google ưu tiên đúng tài khoản; mật khẩu và 2FA chỉ nhập trên Google.</p></div></div>
            <input value={googleLoginHint} placeholder="ten-tai-khoan@gmail.com (tùy chọn)" onChange={(event) => setGoogleLoginHint(event.target.value)} />
            <button className="wide-button" disabled={!dashboardConnected || busy !== null} onClick={() => void action('/api/accounts/google', { loginHint: googleLoginHint }, 'Đã mở đăng nhập cho slot Google kế tiếp.')}>＋ Thêm tài khoản Google</button>
            <button className="wide-button secondary" disabled={!dashboardConnected || busy !== null || !state.accounts.some((account) => account.kind === 'google' && account.status === 'ready')} onClick={() => void action('/api/google/models/refresh-all', {}, 'Đã đồng bộ model Google từ catalog hiện tại.')}>↻ Đồng bộ model Google</button>
          </article>
          <article className="manage-card compact">
            <div className="manage-head"><span className="badge api">{`{}`}</span><div><h3>API endpoint</h3><p>Key chỉ nằm trong setting.json bị Git bỏ qua.</p></div></div>
            <button className="wide-button" disabled={!dashboardConnected || busy !== null} onClick={() => void action('/api/settings/open', {}, 'Đã mở setting.json.')}>Mở setting.json</button>
          </article>
        </section>

        <section className="terminal-section">
          <div className="section-heading"><div><div className="eyebrow">SESSION CỤC BỘ</div><h2>Mở lại công việc cũ</h2></div></div>
          <p className="section-note">Nội dung session nằm trong <code>.runtime/claude-home</code> và không được đưa lên Git. Các session cũ đã được sao chép vào đây mà không xóa bản gốc.</p>
          <div className="terminal-table">
            {state.sessions.length === 0 ? <div className="table-empty">Chưa có session Claude nào trong dự án.</div> : state.sessions.slice(0, 20).map((session) => (
              <div className="terminal-row session-row" key={session.id}><span className="terminal-state ended" /><strong>{session.name}</strong><span>{session.model || session.routeName}</span><span>{session.migrated ? 'Đã nhập từ cấu hình cũ' : 'Session mới'}</span><time>{new Date(session.lastOpenedAt).toLocaleString('vi-VN')}</time><label className="session-route-choice"><span>Mở lại bằng</span><select value={resumeRoutes[session.id] || ''} aria-label={`Mở lại bằng ${session.name}`} disabled={!dashboardConnected || busy !== null || !state.routes.length} onChange={(event) => setResumeRoutes((current) => ({ ...current, [session.id]: event.target.value }))}><option value="" disabled>Chọn route</option>{state.routes.map((route) => <option key={route.id} value={route.id}>{route.name}</option>)}</select></label><div className="session-actions"><button disabled={!dashboardConnected || busy !== null || !resumeRoutes[session.id]} onClick={() => void action('/api/sessions/resume', { sessionId: session.id, routeId: resumeRoutes[session.id] }, `Đã mở lại ${session.name}.`)}>Mở lại</button><button className="session-delete-button" disabled={!dashboardConnected || busy !== null} onClick={() => void deleteSession(session)}>Xóa</button></div></div>
            ))}
          </div>
        </section>

        <section className="terminal-section update-section">
          <div className="section-heading"><div><div className="eyebrow">CẬP NHẬT CÓ KIỂM SOÁT</div><h2>Chỉ kiểm tra, không tự merge</h2></div><button className="quiet-button" disabled={!dashboardConnected || busy !== null} onClick={() => void action('/api/updates/check', {}, 'Đã kiểm tra bản phát hành mới; không có gì được tự cập nhật.')}>↻ Kiểm tra cập nhật</button></div>
          <p className="section-note">Lần cập nhật project gần nhất: {state.updates.lastProjectUpdateAt ? new Date(state.updates.lastProjectUpdateAt).toLocaleString('vi-VN') : 'chưa xác định'}. Lần kiểm tra mạng: {state.updates.checkedAt ? new Date(state.updates.checkedAt).toLocaleString('vi-VN') : 'chưa kiểm tra'}.</p>
          <div className="update-grid">
            {state.updates.components.map((component) => <article className="update-card" key={component.id}><div><strong>{component.label}</strong><small>{component.source}</small></div><span className={`update-status ${component.status}`} title={component.errorMessage || undefined}>{component.status === 'available' ? 'Có bản mới' : component.status === 'current' ? 'Đang mới nhất' : component.status === 'error' ? 'Lỗi kiểm tra' : 'Chưa kiểm tra'}</span>{component.errorMessage && <p className="update-error-note" title={component.errorMessage}>{component.errorMessage}</p>}<dl><div><dt>Đang dùng</dt><dd>{component.localVersion}</dd></div><div><dt>Mới nhất</dt><dd>{component.latestVersion || '—'}</dd></div><div><dt>Đã duyệt/build</dt><dd>{component.lastUpdatedAt || '—'}</dd></div></dl></article>)}
          </div>
        </section>

        <section className="terminal-section">
          <div className="section-heading"><div><div className="eyebrow">PHIÊN ĐANG CHẠY</div><h2>Terminal gần đây</h2></div><button className="quiet-button" disabled={!dashboardConnected || busy !== null || !state.terminals.some((terminal) => !terminal.running)} onClick={() => void clearClosedTerminals()}>Xóa mục đã đóng</button></div>
          <div className="terminal-table">
            {state.terminals.length === 0 ? <div className="table-empty">Chưa có terminal nào được mở từ dashboard.</div> : state.terminals.map((terminal) => (
              <div className="terminal-row" key={`${terminal.pid}-${terminal.startedAt}`}><span className={`terminal-state ${terminal.running ? 'live' : 'ended'}`} /><strong>{terminal.routeName}</strong><span>{terminal.model}</span><span>PID {terminal.pid}</span><time>{new Date(terminal.startedAt).toLocaleString('vi-VN')}</time><em>{terminal.running ? 'Đang chạy' : 'Đã đóng'}</em></div>
            ))}
          </div>
        </section>
      </main>

      <footer className="app-footer"><span>Claude {state.services.claudeVersion} · CCR {state.services.routerVersion}</span><span>127.0.0.1:18320 · Không gửi token ra frontend · Fallback tự động mặc định tắt</span></footer>
      {loading && <div className="loading-bar"><span /></div>}
      {notice && <button className={`toast ${notice.tone}`} onClick={() => setNotice(null)}>{notice.text}<span>×</span></button>}
    </div>
  );
}

createRoot(document.getElementById('root')!).render(<React.StrictMode><App /></React.StrictMode>);
