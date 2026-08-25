# ADR — Local dashboard owns accounts, quota and bounded fallback

- Date: 2026-08-25
- Status: architecture accepted; live implementation deferred to Phase 2
- Owner intent: manage provider accounts and quota visibly while keeping one
  Claude CLI harness and avoiding session interruption

## Decision

Build one project-local dashboard/control plane around the isolated CLIProxyAPI
challenger. Do not extend CCR's Connect-agent UI or use CCR as the long-term
quota/fallback dashboard. CCR remains the current operational router and
rollback champion until the challenger/dashboard passes live-account gates.

The dashboard will eventually own these explicit user outcomes:

1. Add/remove one isolated provider account through that provider's official
   browser/OAuth flow or add an API endpoint/key.
2. Show account, plan, eligible models, current route, health and quota source.
3. Show weekly quota for every supported provider. For Google AI Pro, display
   separate `gemini_models` and `claude_gpt_models` branches.
4. Show five-hour quota when the provider exposes a trustworthy value. Never
   fabricate it from local request counts.
5. Configure a finite ordered fallback allowlist and require an explicit
   manual/automatic mode choice.
6. Launch only project-local Claude CLI through the selected route; never make
   Codex/Gemini/provider CLIs into the harness.

## Why not CCR for the dashboard

CCR already supplies the current Anthropic-compatible gateway, but this project
has repeatedly had to contain its agent-profile/global-App controls, cold-start
behavior and incomplete account entitlement surface. Its local request usage is
not a provider weekly/five-hour subscription quota. Adding another account UI,
quota adapters and scheduler into the existing patched CCR fork would increase
coupling to the component kept specifically as rollback.

EasyCLIProxyAPI was the strongest feature reference because its upstream
describes lifecycle, OAuth, provider aggregation, quota inspection and auth-file
management. Source intake at `v0.2.61` found app/core update downloads,
system-tray/autostart, global Codex/Claude discovery/configuration and auth-file
inspection paths. More decisively, no license grant was present in the tagged
tree. It is therefore blocked as inspect-only reference: do not copy, modify,
build or distribute its code unless upstream adds a compatible license or the
owner obtains permission. The dashboard implementation will be original code
over the project's usage/fallback contracts unless that blocker is resolved.

## Fallback safety rules

- Weekly availability is required for proactive scheduling.
- If five-hour quota is available, it is also required for proactive
  eligibility. A depleted five-hour window cannot be ignored because weekly is
  healthy.
- If five-hour quota is missing/unknown, proactive selection cannot assume it
  is healthy. Reactive fallback is allowed only after a recognized
  provider quota/rate-limit response and before any upstream output is emitted.
- Never retry automatically after streamed output, a tool call or another
  externally visible side effect. The dashboard must stop and ask the user.
- Preserve session affinity. A new account/model may take over only at a safe
  request boundary and only from the finite owner-configured allowlist.
- Cap attempts; no cyclic fallback, unbounded retry, stealth account rotation
  or claim that fallback increases a provider's allowed quota.
- If model capabilities differ, show the model change before continuing.
- Every quota value is labelled provider-reported, proxy-observed, estimated or
  unknown. Unknown is a valid result.

## Phased implementation

- Phase 1 (current): deterministic local proxy pilot, usage/fallback contracts,
  no OAuth, no real provider traffic and no dashboard binary.
- Phase 2A: source-only audit completed for EasyCLIProxyAPI and blocked it; now
  specify/build a minimal original project-local dashboard control plane.
- Phase 2B: one owner-approved test account, explicit selection only, automatic
  fallback disabled.
- Phase 2C: two accounts, manual switch and quota display provenance.
- Phase 2D: bounded automatic fallback after failure injection and duplicate
  output/tool-side-effect tests.
- Promotion: replace CCR only after cumulative gates pass and rollback is
  rehearsed. Until then, normal use remains `RUN_CLAUDE.bat`.

## Rollback

Stop/remove only the ignored dashboard/challenger runtime and account state.
Continue through CCR. Never delete or import CCR/global Codex App auth as part
of dashboard rollback.
