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
  providerKey?: string;
  quotaPageAvailable?: boolean;
  plan: string;
  status: 'ready' | 'not_signed_in' | 'incomplete' | 'disabled';
  models: string[];
  routes: string[];
  catalog?: {
    status: 'available' | 'unknown' | 'error';
    observedAt: string | null;
    source: string;
    routableCount?: number;
    error?: string;
  };
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
  kind: 'codex' | 'google' | 'api';
};

export type TerminalRecord = {
  pid: number;
  sessionId?: string;
  sessionName?: string;
  routeId: string;
  routeName: string;
  model: string;
  startedAt: string;
  running: boolean;
};

export type ClaudeSession = {
  id: string;
  name: string;
  routeId: string;
  routeName: string;
  model: string;
  originRouteId: string;
  originRouteName: string;
  originModel: string;
  lastRouteId: string;
  lastRouteName: string;
  lastModel: string;
  createdAt: string;
  lastOpenedAt: string;
  migrated: boolean;
};

export type UpdateComponent = {
  id: string;
  label: string;
  localVersion: string;
  latestVersion: string | null;
  lastUpdatedAt: string | null;
  source: string;
  status: 'unchecked' | 'current' | 'available' | 'error';
  errorMessage?: string;
};

export type DashboardState = {
  schemaVersion: number;
  generatedAt: string;
  project: { name: string; rootLabel: string; isolation: string };
  accounts: Account[];
  routes: Route[];
  sessions: ClaudeSession[];
  terminals: TerminalRecord[];
  updates: {
    checkedAt: string | null;
    lastProjectUpdateAt: string | null;
    components: UpdateComponent[];
  };
  services: {
    dashboard: string;
    router: 'running' | 'stopped' | 'unknown';
    claudeVersion: string;
    routerVersion: string;
  };
};
