export type UsageWindow = {
  id: string;
  label: string;
  remainingPercent: number | null;
  resetAt: string | null;
  detail?: string;
};

export type UsageGroup = {
  id: string;
  label: string;
  status: 'available' | 'unknown' | 'error';
  windows: UsageWindow[];
  reason?: string;
};

export type Account = {
  id: string;
  kind: 'codex' | 'google' | 'api';
  label: string;
  resumeKey?: string;
  plan: string;
  status: 'ready' | 'not_signed_in' | 'incomplete' | 'disabled';
  models: string[];
  routes: string[];
  usage: {
    status: 'idle' | 'available' | 'unknown' | 'error';
    observedAt: string | null;
    source: string;
    experimental: boolean;
    credits?: { balance: number | null; hasCredits: boolean };
    resetCreditsAvailable?: number;
    detectedPlan?: string | null;
    groups: UsageGroup[];
    message?: string;
  };
};

export type Route = {
  id: string;
  name: string;
  provider: string;
  model: string;
  kind: 'codex' | 'api';
};

export type TerminalRecord = {
  pid: number;
  routeId: string;
  routeName: string;
  model: string;
  startedAt: string;
  running: boolean;
};

export type DashboardState = {
  schemaVersion: number;
  generatedAt: string;
  project: { name: string; rootLabel: string; isolation: string };
  accounts: Account[];
  routes: Route[];
  terminals: TerminalRecord[];
  services: {
    dashboard: string;
    router: 'running' | 'stopped' | 'unknown';
    claudeVersion: string;
    routerVersion: string;
  };
};
