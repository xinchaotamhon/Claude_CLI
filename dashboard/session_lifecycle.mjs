function text(value, fallback = '') {
  return typeof value === 'string' && value.trim() ? value.trim() : fallback;
}

export function normalizeSessionRecord(record, originTerminal = null) {
  const originRouteId = text(record?.originRouteId, text(originTerminal?.routeId, text(record?.routeId)));
  const originRouteName = text(record?.originRouteName, text(originTerminal?.routeName, text(record?.routeName, originRouteId)));
  const originModel = text(record?.originModel, text(originTerminal?.model, text(record?.model)));
  const lastRouteId = text(record?.lastRouteId, text(record?.routeId, originRouteId));
  const lastRouteName = text(record?.lastRouteName, text(record?.routeName, originRouteName));
  const lastModel = text(record?.lastModel, text(record?.model, originModel));
  return {
    ...record,
    routeId: originRouteId,
    routeName: originRouteName,
    model: originModel,
    originRouteId,
    originRouteName,
    originModel,
    lastRouteId,
    lastRouteName,
    lastModel,
  };
}

export function createSessionRecord({ id, name, route, now, migrated = false }) {
  return normalizeSessionRecord({
    id,
    name,
    routeId: route.id,
    routeName: route.name,
    model: route.model,
    originRouteId: route.id,
    originRouteName: route.name,
    originModel: route.model,
    lastRouteId: route.id,
    lastRouteName: route.name,
    lastModel: route.model,
    createdAt: now,
    lastOpenedAt: now,
    migrated,
  });
}

export function resumeSessionRecord(record, route, now) {
  const normalized = normalizeSessionRecord(record);
  return {
    ...normalized,
    lastRouteId: route.id,
    lastRouteName: route.name,
    lastModel: route.model,
    lastOpenedAt: now,
  };
}

export function sessionLaunchConflicts(sessionId, terminals, pendingSessionIds) {
  if (pendingSessionIds?.has(sessionId)) return true;
  return Array.isArray(terminals) && terminals.some((terminal) => terminal?.sessionId === sessionId && terminal?.running === true);
}
