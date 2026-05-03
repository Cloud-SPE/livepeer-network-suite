# Suite conventions and drift map

A **descriptive** snapshot of what's actually true across the 14 submodules
today, with drift called out. Not prescriptive — alignment work is tracked
in [`exec-plans/active/0002-suite-wide-alignment.md`](../exec-plans/active/0002-suite-wide-alignment.md).

This doc is the input to that alignment plan. Update both together.

## Naming conventions

| Slot | Pattern | Examples | Drift |
|---|---|---|---|
| On-chain control plane | `livepeer-modules` (umbrella) | — | none |
| Operator scaffolding CLI | `livepeer-up-installer` (repo); `livepeer-up` (binary) | — | none |
| Operator consoles | `livepeer-<role>-console` | `livepeer-secure-orch-console`, `livepeer-orch-coordinator` _(no -console suffix)_, `livepeer-gateway-console` | `orch-coordinator` doesn't end in `-console` even though it is one |
| Workload engines (OSS, npm) | `<workload>-core` or `livepeer-<workload>-gateway-core` | `livepeer-openai-gateway-core`, `livepeer-video-core` | inconsistent prefix — OpenAI engine has `livepeer-` and `-gateway-core`; video is just `<workload>-core` |
| Workload gateways (payer side) | `livepeer-<workload>-gateway` | `livepeer-openai-gateway`, `livepeer-video-gateway`, `livepeer-vtuber-gateway` | none — convention now uniform after the v3.0.0 video-platform split |
| Workload workers (payee side) | `<workload>-worker-node` (no `livepeer-` prefix) | `openai-worker-node`, `video-worker-node`, `vtuber-worker-node` | none — convention now uniform after the v3.0.0 video-platform split |
| Consumer applications | _no fixed pattern yet_ | `livepeer-vtuber-project` | only one example; convention not established |

**Retired terms** (per
[`exec-plans/active/0001-upstream-naming-cleanup.md`](../exec-plans/active/0001-upstream-naming-cleanup.md)):
- `bridge` → `gateway`
- `BYOC` → `OpenAI adapter` / `paid HTTP adapter` / `workload binaries`
- `livepeer-modules-project` → `livepeer-modules`
- `livepeer-payment-library` → `payment-daemon`
- `openai-livepeer-bridge` → `livepeer-openai-gateway`

## Repo strategy per workload type

Split repos are the suite-wide convention. As of v3.0.0:

| Workload | Engine | Shell | Worker | Strategy |
|---|---|---|---|---|
| OpenAI | `livepeer-openai-gateway-core` (own repo) | `livepeer-openai-gateway` (own repo) | `openai-worker-node` (own repo) | ✅ split |
| Video | `livepeer-video-core` (own repo) | `livepeer-video-gateway` (own repo) | `video-worker-node` (own repo) | ✅ split |
| VTuber | _(no engine yet)_ | `livepeer-vtuber-gateway` (own repo) | `vtuber-worker-node` (own repo) | ✅ split (no engine) |

The pre-v3.0.0 monorepo `livepeer-video-platform` (which bundled
shell + worker under one tag) was retired in v3.0.0 §D.

## Languages by component role

| Component role | Language | Submodules |
|---|---|---|
| On-chain daemons + chain-glue lib | Go | `livepeer-modules` |
| Scaffolding CLI | Go | `livepeer-up-installer` |
| Workload workers (payee) | Go | `openai-worker-node`, `video-worker-node`, `vtuber-worker-node` |
| Workload engines (npm OSS) | TypeScript | `livepeer-openai-gateway-core`, `livepeer-video-core` |
| Workload shells (gateways) | TypeScript | `livepeer-openai-gateway`, `livepeer-video-gateway`, `livepeer-vtuber-gateway` |
| Operator consoles | TypeScript | `livepeer-secure-orch-console`, `livepeer-orch-coordinator`, `livepeer-gateway-console` |
| Consumer applications | Python (+ minimal TS for browser) | `livepeer-vtuber-project` |

**Pattern is consistent**: Go for performance-sensitive payment + chain
paths, TS for HTTP-fronting business logic, Python for application code.

## Web frameworks

| Framework | Used by |
|---|---|
| Fastify | All TS shells + all consoles + both engines (as optional adapter) |
| Express / Hono / h3 | None used; engines support them via the framework-free dispatcher pattern |
| Standard `net/http` (Go) | All Go HTTP surfaces |

Consistent.

## Frontend stack (when there is one)

| Stack | Used by |
|---|---|
| Lit + Vite SPA | The 3 operator consoles + `livepeer-openai-gateway`'s customer + admin SPAs + `livepeer-vtuber-gateway`'s admin (presumed; same template) |
| Vanilla TS (no Lit/RxJS/Vite) | `livepeer-video-core`'s optional `/admin/ops/*` dashboard |
| Browser TS (custom) | `livepeer-vtuber-project` avatar-renderer (~26 KB) |

**Drift:** the video engine deliberately rejects Lit + Vite for its
optional dashboard. Plausible: it ships as an OSS library, so heavier
frontend deps would be imposed on every adopter. Worth keeping but
documenting as a deliberate choice.

## Persistence

| Store | Used by | Why |
|---|---|---|
| Postgres + Drizzle | All shells (`livepeer-openai-gateway`, `livepeer-vtuber-gateway`, video shell) | Customer billing ledger — atomic `SELECT … FOR UPDATE`, durable |
| SQLite (better-sqlite3) + Drizzle | All operator consoles | Local audit + cache; per-host, no cross-host sharing needed |
| BoltDB | All `livepeer-modules` daemons | Daemon-local replay protection, durable tx-intent journal, per-daemon |

**Pattern is intentional and well-matched to access pattern.** No drift.

## Cache / queue

| Tool | Used by |
|---|---|
| Redis | All shells (rate limiter + general cache) |
| ioredis | (driver of choice) |

Consistent.

## Schema validation

**Zod at boundaries** is a hard invariant in `livepeer-openai-gateway`
(core belief #2) and is mandated by both engines for any input crossing
into the `service/` layer. Consoles follow the same pattern.

Custom ESLint rule `zod-at-boundary` enforces this in the openai shell.
Consistent.

## Layered architecture (TS side)

The harness PDF's "rigid architecture, mechanically enforced" pattern is
universal on the TS side. **But the layer order varies** between repos:

| Repo | Layer order |
|---|---|
| `livepeer-openai-gateway` | `types → config → providers → repo → service → runtime → main` |
| `livepeer-up-installer` | `cmd → runtime/cli → service → repo → providers → config → types → utils` |
| `livepeer-orch-coordinator` | `types → config → repo → service → runtime → providers → utils` |
| `livepeer-gateway-console` | `types → config → repo → service → runtime → providers → utils` |
| `livepeer-video-core` (engine internal) | not declared in README |
| `livepeer-vtuber-gateway` | (assumed inherited from openai-gateway template) |

**Drift:** providers comes before repo in openai-gateway, after repo
elsewhere. The semantic difference matters: when providers are below
repo, repo can use providers (e.g., a provider gives a Drizzle handle).
When providers are above repo, providers can compose repos. Both are
defensible; suite needs to pick one and align.

## Custom lint plugins

| Repo | Lint name | Approach |
|---|---|---|
| `livepeer-openai-gateway` | `eslint-plugin-livepeer-bridge` _(retired-term, pending rename)_ — six rules incl. `layer-check`, `no-cross-cutting-import`, `zod-at-boundary` | Custom JS, error messages inject remediation hints (per harness PDF) |
| `livepeer-orch-coordinator`, `livepeer-gateway-console` | "six rules with remediation hints" (presumably similar) | Same shape |
| `livepeer-up-installer` | `lint/layer-check/` (Go) | Custom Go analyzer |
| `openai-worker-node` | (none flagged in README) | — |
| `vtuber-worker-node` | `lint/payment-middleware-check/` | Custom golangci-lint analyzer |
| `livepeer-modules` | (per-component lints, not deeply surveyed) | — |

**Pattern:** every component has at least one custom lint. **Drift:**
the rule names don't form a coherent set across repos. Opportunity to
publish a shared lint catalog as part of the missing
`livepeer-modules-conventions` (see below).

## Coverage gates

**75% lines/branches/functions/statements** is universal where declared
(`livepeer-modules`, `livepeer-openai-gateway`, both engines,
`livepeer-up-installer`, `livepeer-video-gateway`, `video-worker-node`).
The few repos without explicit coverage gates inherit it from the template.

Consistent.

## Auth conventions

| Surface | Header | Used by |
|---|---|---|
| Customer API | `Authorization: Bearer <api-key>` | `livepeer-openai-gateway`, `livepeer-vtuber-gateway` |
| Operator admin endpoints | **`Authorization: Bearer <admin-token>`** | `livepeer-openai-gateway` + the 3 operator consoles |
| Session-scoped child bearers | `Authorization: Bearer vtbs_*` (HMAC + pepper) | `livepeer-vtuber-gateway` WebSocket `/control` |
| Worker-side WebSocket | `Authorization: Bearer vtbsw_*` (deterministic HMAC from `(pepper, session_id)`) | `livepeer-vtuber-gateway` WebSocket `/worker-control` |

**Current rule:** admin/operator shells use bearer auth. Optional
`X-Admin-Actor`-style headers are attribution metadata only, not auth.

**Pattern worth promoting:** the `vtbs_*` session-scoped child bearer
(ADR-005 in `livepeer-vtuber-project`) is generalizable to any
long-running connection — limits blast radius if a long-lived token
leaks. Worth lifting into a suite convention for future
WebSocket/streaming surfaces.

## Network posture

**Consistent across all operator-facing services and shells:**

- Bind to `127.0.0.1` only (no public exposure from the app itself).
- Operator brings their own reverse proxy (Traefik / nginx / Caddy /
  cloudflared / Tailscale Funnel) for TLS + public ingress.
- App handles bearer-token auth at the application layer — no OIDC,
  sessions, or cookies.
- A `compose.prod.yaml` overlay ships Traefik labels assuming an
  external `ingress` Docker network — ignorable if you front it
  another way.

This is a strong invariant. No drift.

## Versioning across submodules

| Submodule | Pinned at | Status |
|---|---|---|
| `livepeer-modules` | `v4.0.2` (`a061b5a`) | ✅ |
| `livepeer-up-installer` | `v4.0.1` (`6e16246`) | ✅ |
| `livepeer-secure-orch-console` | `v4.0.1` (`5d2ccc5`) | ✅ |
| `livepeer-orch-coordinator` | `v4.0.1` (`b767bfe`) | ✅ |
| `livepeer-gateway-console` | `v4.0.1` (`08e9063`) | ✅ |
| `openai-worker-node` | `v4.0.1` (`80b2347`) | ✅ |
| `livepeer-openai-gateway` | `v4.0.1` (`098a2f3`) | ✅ |
| `livepeer-openai-gateway-core` | `v4.0.1` (`8737750`) | ✅ |
| `livepeer-video-core` | `v4.0.1` (`cd2a139`) | ✅ repo tag; package still pre-1.0 |
| `livepeer-video-gateway` | `v4.0.1` (`111c9f5`) | ✅ |
| `video-worker-node` | `v4.0.1` (`b32951b`) | ✅ |
| `livepeer-vtuber-gateway` | `v4.0.1` (`d5cf095`) | ✅ |
| `vtuber-worker-node` | `v4.0.1` (`633049f`) | ✅ same commit also carries legacy tag `v3.0.11` |
| `livepeer-vtuber-project` | `v4.0.1` (`5dc46d2`) | ✅ |

**Drift:** the suite is now largely on the `v4.x` line. The main
remaining asymmetry is that `livepeer-modules` has already advanced to
`v4.0.2`.

**Engine versioning:** `livepeer-video-core` is still pre-1.0 and may
take breaking changes in minor bumps. Shells should still pin exactly
rather than auto-update.

## Image registry + image versions

| Image namespace | Used by | Version anchors observed |
|---|---|---|
| `tztcloud/livepeer-payment-daemon` | `livepeer-modules`, all gateway shells, all worker repos | **`v0.8.10` (user memory)**, **`v1.0.0` (`livepeer-modules` README)**, **`v1.4.0` (`livepeer-openai-gateway` compose)** — three different anchors |
| `tztcloud/livepeer-service-registry-daemon` | same | same drift |
| `tztcloud/livepeer-protocol-daemon` | `livepeer-modules` only | `v1.0.0` |
| `tztcloud/livepeer-openai-gateway` | `livepeer-openai-gateway` | `v0.8.10` (rolling tag) |
| `tztcloud/livepeer-up:dev` | `livepeer-up-installer` | `dev` |

**Significant drift:** the daemon image versions disagree across the
suite. Already in tech-debt.

## Daemon proto sharing

The `payment-daemon` and `service-registry-daemon` `.proto` files are
**vendored independently** in every consumer:

- `livepeer-modules/payment-daemon/...` (canonical)
- `openai-worker-node/internal/proto/livepeer/payments/v1/`
- `livepeer-openai-gateway/src/providers/payerDaemon/gen/`
- `livepeer-gateway-console/src/providers/payerDaemon/gen/` + `resolver/gen/`
- `livepeer-vtuber-gateway` (presumed; uses `npm run proto:gen`)
- `vtuber-worker-node/internal/proto/...` (presumed)

**Drift risk grows with consumer count.** Already in tech-debt:
promote to a shared package or shared submodule before more consumers
appear. **`livepeer-modules-conventions`** would be a natural home if
it existed (see below).

## Cross-suite conventions ("the missing repo")

Three submodule READMEs reference
`https://github.com/livepeer-modules-project/livepeer-modules-conventions`
or `Cloud-SPE/livepeer-modules-conventions` as the home for cross-suite
metric naming + port allocation conventions:

- `livepeer-openai-gateway-core` — README "Ecosystem integration"
- `livepeer-video-core` — README "Cross-ecosystem metric naming + port allocation conventions"
- `vtuber-worker-node` — README "Cross-repo conventions (metrics, ports)"

**The repo doesn't exist.** Three submodules are pointing at a phantom.
This is a real opportunity:

- The conventions clearly need a home — they're being referenced.
- The conventions are scattered today (in `livepeer-modules/docs/conventions/`).
- A real `livepeer-modules-conventions` repo (or sub-doc) could become
  the home for: metric naming, port allocation, daemon protos (shared
  package), shared lint rules, the engine + shell pattern itself,
  worker manifest schemas, naming conventions, host-archetype
  variations.

## Documentation patterns (harness PDF)

Most submodules follow the harness PDF pattern:

- Short `AGENTS.md` (~100 lines) as a map.
- `docs/` with `design-docs/`, `exec-plans/active/`, `exec-plans/completed/`,
  `tech-debt-tracker.md`, `references/`.
- Top-level `DESIGN.md`, `PRODUCT_SENSE.md`, `PLANS.md`, `FRONTEND.md` (consoles).
- Custom lints, `doc-gardener` jobs, "core beliefs" lists.

**Drift in two stylistic choices:**

1. **Where canonical design lives.** The OpenAI side keeps
   `DESIGN.md` + `PRODUCT_SENSE.md` in each repo. The vtuber side
   concentrates them in `livepeer-vtuber-project`; the gateway and
   worker repos have intentionally minimal `docs/` and link upstream.
   Two valid patterns; suite should pick one for future workloads.

2. **Whether the harness PDF is in `docs/references/`.** Some repos
   include it (`livepeer-openai-gateway`, this meta-repo);
   others link to OpenAI's hosted version. Either is fine — but if
   the meta-repo's copy is canonical, the rest can de-duplicate.

## "No shared code" coordination pattern (ADR-003)

A unique-to-Cloud-SPE pattern is visible across the workload pairs:
the OpenAI and vtuber sibling repos **share zero source code**, even
though they were forked from each other's skeletons. ADR-003 in
`livepeer-vtuber-project` mandates this. Coordination happens through:

- A `sibling-integration.md` table documenting common patterns.
- Property tests pinning byte-shapes (e.g., `vtbs_*` token format) so
  siblings can be checked byte-equivalent.

**Trade-off:** less coupling, more manual coordination. Same trade-off
`livepeer-modules` made by vendoring its proto files.

**Worth deciding suite-wide:** is this the convention going forward,
or should we consolidate as the suite grows? Three or four workload
pairs is the inflection point — beyond that, "byte-equivalence via
property tests" doesn't scale.

## Architectural patterns worth lifting into convention

These are patterns that emerged organically and could be promoted to
suite-wide invariants:

### 1. Engine + shell + worker per workload

Every workload type follows this shape:

- **Engine** (OSS, framework-free, npm) — owns the request pipeline,
  exposes adapter interfaces.
- **Shell** (proprietary deployable) — wires production adapters into
  the engine.
- **Worker** (payee-side process) — satisfies the engine's capability +
  payment-ticket protocol on a worker-orch host.

Two workloads in the suite have an explicit engine; one (vtuber)
doesn't yet. Worth deciding whether vtuber gets its own engine or
stays direct.

### 2. Customer-facing API as the gateway boundary

Internal Cloud-SPE products consume gateways the **same way external
customers do** — with `Authorization: Bearer <api-key>` over HTTPS.
`livepeer-vtuber-project` (Pipeline) hits both `livepeer-vtuber-gateway`
and `livepeer-openai-gateway` exactly like an external customer would.

Strong invariant: **no internal-only sockets between application code
and gateways.** Gateways are public-facing; internal use traverses the
same auth + rate-limit + billing path as external use.

### 3. Defense in depth on signed manifests

The signed registry manifest is verified twice:

- Once when `orch-coordinator` accepts the upload from `secure-orch`.
- Again when each gateway resolver fetches `/manifest.json`.

**Worth generalizing to a suite-wide pattern:** any signed artifact
crossing trust boundaries gets verified by every consumer, even if the
producer also verified.

### 4. Boundary discipline: the app handles auth, the operator handles ingress

Every operator-facing app: 127.0.0.1 bind, bearer-token auth at app
layer, BYO reverse proxy. **Already universal**. Just worth writing
down explicitly so it doesn't drift later.

### 5. Session-scoped child bearers for long-running connections

The `vtbs_*` pattern (ADR-005) — short-lived bearer minted from a
long-lived API key, scoped to one connection — is generalizable. Any
future long-running surface (WebSocket, SSE, streaming POST) should
adopt it.

## Open architectural divergences worth resolving

1. ~~**Publisher-mode `service-registry-daemon` on workers**~~ —
   resolved in v3.0.0. Archetype A is the only deploy pattern: workers
   are registry-invisible and never run a publisher. See
   [`exec-plans/active/0003-archetype-a-deploy-unblock.md`](../exec-plans/active/0003-archetype-a-deploy-unblock.md)
   §1 (resolves [plan 0002 §Item 10](../exec-plans/active/0002-suite-wide-alignment.md#item-10--document-publisher-on-worker-semantics)).
2. **Engine optional vs required.** OpenAI requires `payment-daemon`
   sidecar; video deliberately doesn't (delegates to operator's
   `WorkerClient` adapter). Pattern divergence — both can coexist, but
   should be explicit per engine.
3. **Many-engines-per-shell.** `livepeer-video-gateway` plans phase-2
   AI features that will consume `livepeer-openai-gateway-core`
   alongside `livepeer-video-core`. The engine + shell mental model
   needs an update — shells can compose multiple engines.

## Revision history

- 2026-04-28: Initial snapshot from 13 submodules. Drift items rolled
  into [`exec-plans/active/0002-suite-wide-alignment.md`](../exec-plans/active/0002-suite-wide-alignment.md).
- 2026-04-29: v3.0.0 cut — `livepeer-video-platform` retired and
  replaced by `livepeer-video-gateway` + `video-worker-node`; submodule
  count is now 14. Publisher-on-worker divergence (Item 10) resolved
  by archetype-A standardization.
