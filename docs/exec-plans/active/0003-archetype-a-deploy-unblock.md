---
title: Archetype A standardization + coordinated v3.0.0 suite reset
status: active
created: 2026-04-29
owner: human (the meta-repo operator)
resolves: plan 0002 §Item 10 (publisher-on-worker semantics)
release-target: v3.0.0 (coordinated suite cut — no backwards compatibility)
---

# Archetype A standardization + coordinated v3.0.0 suite reset

The cross-repo coordination plan that locks down the manifest-and-discovery
contract and ships it as a clean v3.0.0 suite release.

The trigger: the coordinator can't currently round-trip a signed manifest
with the secure-orch console (schema mismatch + canonicalization
mismatch). The fix touches several submodules and resolves an open
architectural question (Item 10 in [plan
0002](./0002-suite-wide-alignment.md)) about whether workers may
self-publish to the registry.

## Scope: clean reset, no backwards compatibility

Confirmed 2026-04-29: nothing in this suite has external users, no
on-chain `serviceURI` is written against any operator's coordinator
URL, and all internal test state can be wiped. **Every component is
free to make breaking changes in a single coordinated v3.0.0 cut.**

What this allows:

- **Wire-format rename `models[]` → `offerings[]` is in scope.** No
  v2-schema-bump conversation; the modules-project bumps the manifest
  to **`schema_version: 3`** (mirrors the suite version cut so all
  numbers line up) as part of v3.0.0.
- **No data migrations.** Coordinator's `state.db`, secure-orch's
  `state.db`, payment-daemon's BoltDB, protocol-daemon's BoltDB,
  service-registry-daemon's stores — all wiped and reinitialized.
  Fresh `0001_init.sql` files with the final shape; no
  `0002_*.sql` reshape steps.
- **No alias paths or compat shims.** The coordinator serves
  `/.well-known/livepeer-registry.json` only. No `/manifest.json` alias.
  Worker `worker.yaml` parsers refuse the old shape with a clear error.
  `service_registry_publisher` blocks in any worker.yaml are a startup
  error, not a "deprecated, will be removed" warning.
- **Single coordinated tag wave.** Every submodule cuts a v3.0.0 tag
  in the same release window. The meta-repo bumps every pin to its
  v3.0.0 in one commit and tags the suite v3.0.0.

## Resolved decisions

These are now suite-wide commitments. Any future submodule must conform.

### 1. Archetype A is the only deploy pattern

Operator gets a signed manifest published as follows:

```
worker fleet ── (operator's eyes / Prom scrape) ──▶ orch-coordinator (roster + SPA)
                                                            │
                                              workers.yaml proposal
                                              (operator hand-carries)
                                                            ▼
                                                 secure-orch console
                                                            │
                                              Publisher.BuildAndSign (gRPC)
                                                            ▼
                                              service-registry-daemon (publisher)
                                              — HOLDS THE COLD KEY
                                                            │
                                            signed registry-manifest.json
                                            (operator hand-carries back)
                                                            ▼
                                              orch-coordinator
                                              POST /api/manifest/upload → verify → swap
                                                            │
                                              GET /.well-known/livepeer-registry.json
                                              (public, unauthenticated)
```

**Archetype B is dead.** Workers do not self-publish. Workers do not dial
publisher daemons. Workers are registry-invisible.

This resolves [plan 0002 Item 10](./0002-suite-wide-alignment.md#item-10--document-publisher-on-worker-semantics).

### 2. Discovery is uniform: `service-registry-daemon` resolver gRPC sidecar

Every gateway in the suite uses the modules-project's
`service-registry-daemon` in resolver mode as a co-located sidecar over a
unix socket, calling `Resolver.Select(capability, offering, tier, geo,
weight)`. (The pre-v3.0.0 RPC named the second parameter `model`; it is
renamed to `offering` in the v3.0.0 proto rev — see §Decision 4.)
Gateways do **not** fetch
`<serviceURI>/.well-known/livepeer-registry.json` directly; the resolver
does.

Confirmed in code:

- `livepeer-openai-gateway/packages/livepeer-openai-gateway/src/main.ts`
- `livepeer-video-platform/apps/api/src/providers/workerResolver/grpcServiceRegistryWorkerResolver.ts`
- `livepeer-vtuber-gateway/src/providers/serviceRegistry/grpc.ts`
- `livepeer-gateway-console` mounts the same sidecar.

### 3. Pricing flows: orchs publish wholesale, gateways read it, gateways own retail

One unified pattern, suite-wide:

1. **Orch publishes a wholesale price** per offering in its signed
   manifest, at `nodes[].capabilities[].offerings[].price_per_work_unit_wei`
   (wei per work-unit). The orch is asserting *"I will accept payment
   at this rate."* Wei because that's the unit the on-chain
   TicketBroker settles in.
2. **Gateway reads the price from the manifest** via the resolver's
   `Select` response. This is the only place the gateway gets the
   wholesale rate — no off-chain rate-card column duplicates it.
3. **Gateway converts to retail** for its customers — USD, ETH, free
   tier, whatever the gateway's product charges in. The retail layer
   (margin policy, ETH/USD conversion, fixed-cost amortization) is
   gateway-owned and never on the manifest. Bridges keep their
   customer-facing rate cards for retail; what they *don't* keep is a
   second source of wholesale truth that drifts from the manifest.
4. **Empty wholesale price** = orch is opting that offering out of the
   routable pool. Gateways skip workers with no price (fail-closed).
   There is no "free on chain" semantic; the gateway has no margin
   policy to apply against an absent rate.

In v3.0.0 this becomes uniform across the suite. Pre-v3.0.0 the
openai-gateway used a Postgres-stored wholesale rate that ignored the
manifest, and the video-gateway was fixed-cost; v3.0.0 brings both in
line with the vtuber-gateway pattern (read manifest pricing as the
wholesale input). See §G for the per-gateway code change.

### 4. "Offering" is the term everywhere — wire format AND operator-facing

The clean reset (no backwards compat) lets us rename across the wire too.
The modules canonical schema bumps to a new `schema_version` and
renames:

- `nodes[].capabilities[].models[]` → `nodes[].capabilities[].offerings[]`
- `nodes[].capabilities[].models[].id` → `nodes[].capabilities[].offerings[].id`
- All proto field carriers (`Capability.Model` → `Capability.Offering`,
  `pricePerWorkUnitWei` stays at the offering level)
- **`Resolver.SelectRequest.model` → `Resolver.SelectRequest.offering`**
  (the gRPC parameter the gateway sends to filter against the offerings
  list — see §Decision 2)
- All worker.yaml parsers (`models:` → `offerings:`, `model:` →
  `offering:` per item)
- All resolver gRPC client code (`node.capabilities[].models` →
  `node.capabilities[].offerings`; `Select(capability, model, ...)`
  call sites → `Select(capability, offering, ...)`)
- All worker `/registry/offerings` endpoint bodies (already named
  correctly per §Decision 5)

There is no naming wart left after v3.0.0.

### 5. Workers expose two endpoints: workload-native `/capabilities` + uniform `/registry/offerings`

Each worker exposes both:

- **`/capabilities`** — workload-native. Serves whatever its local
  consumers need (bridge, dispatcher, diagnostics) in whatever shape
  fits that workload. Not constrained by the modules schema.
- **`/registry/offerings`** — uniform across all workers. Returns
  the modules-canonical `capabilities[]` fragment that this worker
  contributes to its orch's manifest. Body shape:
  ```json
  {
    "capabilities": [
      {
        "name": "openai:/v1/chat/completions",
        "work_unit": "token",
        "offerings": [
          { "id": "gpt-oss-20b", "price_per_work_unit_wei": "1250000" }
        ],
        "extra": { /* optional, opaque, workload-specific */ }
      }
    ]
  }
  ```
  The worker does not know its own `id`/`url`/`region`/`lat`/`lon`
  (operator-chosen identity + topology); those are filled in by the
  coordinator's roster row at proposal-compose time.

The orch-coordinator scrapes `/registry/offerings` when the operator
adds or refreshes a worker, presents the result as a **draft roster
entry**, and saves only what the operator confirms. This eliminates
operator drift (worker self-describes its offerings) while preserving
operator control over what publishes (operator can edit prices, add
`extra`, drop offerings before saving).

Both workers and the coordinator run on the public internet, so the
scrape happens over public HTTPS (operator's reverse proxy in front).
Auth on the endpoint is **optional, off by default**:

- **Worker:** new env `OFFERINGS_AUTH_TOKEN`. If set, the endpoint
  requires `Authorization: Bearer <token>`; otherwise plain.
- **Coordinator:** per-worker `offerings_auth_token` field on the
  `fleet_workers` row (operator types it in the SPA next to the URL).
  Sent as a bearer if present, omitted otherwise.

The data isn't secret (it ends up in the public signed manifest
anyway), so default-off is fine. The optional token gives operators a
small additional access barrier without forcing token management on
anyone who doesn't want it.

This is **the contract** for any worker that wants to be coordinator-
discoverable. New workloads implementing this endpoint are
operator-friendly out of the box; new workloads that don't ship it
fall back to fully-manual roster entry.

### 6. New workloads onramp recipe

Documented as a recipe (see Per-repo changes §A.3 below). The path is:

1. Pick a capability name following
   [`workload-agnostic-strings.md`](../../../livepeer-modules/service-registry-daemon/docs/design-docs/workload-agnostic-strings.md)
   conventions.
2. Pick a `work_unit`.
3. Decide pricing pattern (embed-in-manifest vs bridge-mediated).
4. Build a worker (HTTP service + payment-daemon socket); template from
   `openai-worker-node` / `vtuber-worker-node` / transcode-worker-node.
5. Optionally build a bridge (resolver sidecar + customer-facing API +
   own pricing layer).
6. Drop into archetype A — operator adds workers to the coordinator's
   roster, secure-orch signs, manifest publishes.

No coordinator change is needed for new workloads. No modules-project
change is needed for new workloads. The capability string is opaque.

## Per-repo change inventory

Repos are listed in dependency order. Within each, files are
deploy-relevant only — incidental cleanups go in each repo's own
exec-plan.

### A. livepeer-modules — schema bump + code release (major)

Pinned at `v1.0.0`. Cuts `v3.0.0` (suite-aligned).

**Schema + proto changes:**

1. **Bump manifest `schema_version` to `3`** in `service-registry-daemon/docs/design-docs/manifest-schema.md`;
   update the "Top-level shape" example and the "Validation order"
   rule that recognizes only the new version.
2. **Rename in proto** at `service-registry-daemon/proto/livepeer/registry/v1/types.proto`
   (or wherever `Capability` and `Model` are defined): `Model` →
   `Offering`, the field carrying `models` repeated → `offerings`
   repeated. **Also rename `SelectRequest.model` → `SelectRequest.offering`**
   in the resolver service proto so the gateway-facing RPC parameter
   matches the response shape. Regenerate Go stubs (`make proto`).
3. **Update the publisher's manifest builder + signer** to emit
   `offerings` instead of `models`, with the new `schema_version`.
4. **Update the resolver's parser + Select handler** to recognize the
   new schema and the new RPC field name; reject the old one (no
   compat code). Update audit logs / metric labels that mention
   `model` to `offering`.
5. **Update `livepeer-registry-refresh` CLI's `workerFile` struct** at
   `service-registry-daemon/cmd/livepeer-registry-refresh/main.go`:
   `Models` → `Offerings`, JSON/YAML tags too (`models` → `offerings`).
6. **Update `registry.example.yaml`, `examples/static-overlay-only/nodes.yaml`,
   and the manifest example doc** at
   `service-registry-daemon/docs/generated/manifest-example.md` to use
   `offerings`.
7. **Update worker.yaml example** in
   `deploy/secure-orch/README.md` (the workers.yaml skeleton) to use
   `offerings`.

**Architecture docs:**

8. **Update host-archetype docs** in
   `service-registry-daemon/docs/design-docs/` and any sibling
   `docs/operations/` archetype guides to mark **archetype A as the
   only supported deployment**. Drop or strike-through any reference
   to the worker-publisher pattern as a permitted variation.
9. **Add a new design-doc** at
   `service-registry-daemon/docs/design-docs/adding-a-new-workload.md`
   summarizing the onramp recipe (Decision 6 above), with links into
   the worker, bridge, and coordinator repos. Single-page, ~1 page.
10. **Add a new design-doc** at
    `service-registry-daemon/docs/design-docs/worker-offerings-endpoint.md`
    defining the `/registry/offerings` convention from Decision 5:
    body shape, optional bearer auth, semantics of "draft → operator
    confirms → published in manifest." This is the contract every
    workload-author implements so the coordinator can do its scrape +
    draft flow.

After landing, network-suite repins this submodule.

### B. livepeer-orch-coordinator (deploy blocker — major)

Cuts `v3.0.0`. Covered by [`docs/exec-plans/active/0002-modules-format-alignment.md`](../../../livepeer-orch-coordinator/docs/exec-plans/active/0002-modules-format-alignment.md).
Updates to that plan land alongside this master plan:

- §step 1 (`SignedManifestSchema`): use the new `offerings[]` field name
  directly; bump expected `schema_version` to whatever modules-project
  chose. No legacy parsing.
- §step 4b: roster column carries the canonical `offerings[]` shape
  with optional `price_per_work_unit_wei`. **No Drizzle migration** —
  rewrite `migrations/0001_init.sql` to the final schema; wipe state.db
  on next install.
- §step 4b: SPA roster editor uses **"Offering"** end-to-end. No
  wire-format compat footnote — the wire and the SPA agree.
- **§new step 4c — Scrape-and-draft workflow.** Add a
  `WorkerOfferingsScraper` provider that fetches `/registry/offerings`
  from a worker URL (alongside the existing Prom scrape), with optional
  bearer auth via the existing `PROM_SCRAPE_TOKEN` env. Service-layer
  function: `fetchDraftOfferings(workerId)` returns the parsed body.
  SPA flow on add-worker: operator submits URL → coordinator scrapes
  `/registry/offerings` → SPA renders the returned `capabilities[]` as
  a pre-filled, editable form → operator reviews/edits/confirms →
  saved to `fleet_workers.capabilities`. SPA also gets a "Refresh
  offerings" button on each worker drilldown (mirrors the existing
  Prom "Refresh" button) that re-scrapes and shows a diff against the
  saved roster row, letting the operator opt into changes.
- Cross-link to this master plan in the depends-on header.
- §step 6: manual-staging runbook lives at
  `docs/operations/manifest-roundtrip-smoke.md` after merge.

The six sub-deliverables (schema, canonicalization, public path,
proposal format + offering-shaped roster, scrape-and-draft workflow,
secure-orch SPA fix, manual verification) ship under coordinator
plan 0002.

### C. livepeer-secure-orch-console — schema + SPA + doc

Cuts `v3.0.0`. Pinned at `v0.1.3`.

1. **`src/types/registry.ts`:** rename `Model` → `Offering`; rename
   `models` → `offerings` field-by-field in `CapabilitySchema` and
   `WorkersYamlSchema`. Bump any version constants.
2. **`src/providers/serviceRegistry/grpc.ts`:** regenerate proto stubs
   against modules v3.0.0; rename `toProtoModel` → `toProtoOffering`,
   `modelsToProto` → `offeringsToProto`; update field references.
3. **`admin-ui/admin/components/admin-manifest-publish.js`,
   `_download(res)`:** replace
   `JSON.stringify({...res.manifest, signature: res.signature}, null, 2)`
   with `JSON.stringify(res.manifest, null, 2)`. The daemon's
   `manifestJson` already carries the canonical
   `signature: {alg, value, signed_canonical_bytes_sha256}` object;
   the spread+overwrite was destroying it.
4. **`workers.yaml.example`:** rename `models:` → `offerings:` and
   `model:` → `offering:` per item. Regenerate help-text comments.
5. **Wipe state.db** on next install — rewrite
   `migrations/0001_init.sql` if needed; no migration step.
6. **Vitest fixtures:** update sample manifests to the new shape.
   Round-trip test against modules canonical-bytes verifier.
7. **Doc refresh:** `DESIGN.md` and `README.md` mention archetype A
   explicitly as the deploy pattern this console supports. Drop any
   "the SPA flattens the signature for coordinator-side simplicity"
   language — that's now factually wrong.

### D. Split `livepeer-video-platform` → `livepeer-video-gateway` + `video-worker-node` (structural + worker rework)

The monorepo split (network-suite plan 0002 §Item 1) is in scope for
v3.0.0 — it lands as part of this wave, not as a separate later cut.
After the split, `livepeer-video-platform` is retired and the meta-repo
pins drop it in favor of two new submodules.

#### D.1 — `Cloud-SPE/livepeer-video-gateway` (extraction in flight; v3.0.0 alignment pending)

Repo exists as of 2026-04-29 and the extraction from
`livepeer-video-platform/apps/api/` is **mostly complete** under that
repo's own [`0014-extract-gateway-from-platform.md`](../../../livepeer-video-gateway/docs/exec-plans/active/0014-extract-gateway-from-platform.md).
Active content: `apps/api/`, `apps/playback-origin/`, `packages/shared/`,
`web-ui/`, `infra/`. Most §A–§E checkboxes in 0014 are ticked; one
doc-gardening sweep remains.

The v3.0.0 alignment is captured in
[`0015-v3-offerings-rename-and-manifest-pricing.md`](../../../livepeer-video-gateway/docs/exec-plans/active/0015-v3-offerings-rename-and-manifest-pricing.md):

1. Resolver proto regen against modules v3.0.0.
2. Rename `models` → `offerings`, `Model` → `Offering`,
   `SelectRequest.model` → `SelectRequest.offering` across
   `apps/api/src/providers/workerResolver/grpcServiceRegistryWorkerResolver.ts`,
   `apps/api/src/providers/_grpc/capabilities.ts`, and tests.
3. **Adopt manifest pricing.** Today the gateway is fixed-cost; under
   v3.0.0 it reads `offerings[i].pricePerWorkUnitWei` from the
   resolver response and uses it as the wholesale price input to its
   routing decision (vtuber-gateway pattern). Workers without a
   published price are skipped — fail-closed (`503 no_priced_orchs_for_offering`).
4. DESIGN.md confirms archetype A, manifest pricing adoption, and the
   resolver-sidecar discovery contract.

Local plan 0015 cuts `v3.0.0` for this repo. Sequencing dependency:
modules-project plan 0004 must land first so the proto regen has a
v3.0.0 contract to target.

#### D.2 — `Cloud-SPE/video-worker-node` (extraction Phase 1 done; code lift pending)

Repo exists as of 2026-04-29 with **pillar docs only** (`AGENTS.md`,
`DESIGN.md`, `PRODUCT_SENSE.md`, `PLANS.md`, `README.md`,
`docs/`). **No Go code yet** — it sits at Phase 1 of its own
[`0001-extract-from-platform.md`](../../../video-worker-node/docs/exec-plans/active/0001-extract-from-platform.md).
Phases 2–5 (code lift, doc lift, self-sufficient verification) are
still pending in that plan.

The v3.0.0 archetype-A alignment is captured in
[`0002-v3-archetype-a-alignment.md`](../../../video-worker-node/docs/exec-plans/active/0002-v3-archetype-a-alignment.md),
which **stacks on top of** plan 0001 with two valid orderings (inline
during Phase 2 lift vs sequential after it closes — the local plan's
"Sequencing relative to plan 0001" section calls this out). Defaults
to inline so the same code isn't lifted-then-deleted.

Plan 0002 covers:

1. **Strip self-publishing** during the lift: do NOT bring
   `internal/service/capabilityreporter/` or
   `internal/providers/registryclient/` into this repo (or delete
   them immediately if already lifted). Drop `--registry-socket` /
   `--registry-refresh` CLI flags and the `registry_socket:`,
   `registry_refresh:`, `node_id:`, `public_url:`,
   `operator_address:`, `price_wei_per_unit:` config fields.
2. **Implement `/registry/offerings`** — uniform modules-canonical
   capability fragment (per master plan §Decision 5). Optional bearer
   auth via `OFFERINGS_AUTH_TOKEN` env. Default off.
3. **Rename `models:` → `offerings:`** in worker.yaml parser.
4. **Doc updates**: archetype-A framing in `DESIGN.md`/`README.md`,
   strike-through any tech-debt items about registry integration.

The workload-native `/capabilities` response shape (modes, codecs,
presets, etc.) is **plan 0001 Phase 2's call** — not dictated by this
master plan. Plan 0002 explicitly inherits whatever 0001 lands.

Plan 0002 cuts `v3.0.0` for this repo. Sequencing dependency:
modules-project plan 0004 must land first so `/registry/offerings`'s
body shape matches the v3.0.0 canonical capability fragment.

#### D.3 — `livepeer-video-platform` left as-is

After D.1 and D.2 land their v3.0.0 tags, network-suite drops the
`livepeer-video-platform` submodule pin and adds the two new pins.
The legacy repo itself is left in place; the operator handles
archival/deletion manually outside this plan's scope.

### E. vtuber-worker-node (worker — small)

Cuts `v3.0.0`. Pinned at `52a0336` (no tag). Currently at "M1 — skeleton
only" per network-suite README.

Deliver a separate exec-plan in this repo:
**`docs/exec-plans/active/00NN-archetype-a-alignment.md`**. Contents:

1. **Delete `internal/providers/publisherdaemon/`** (the gRPC client to
   the publisher daemon).
2. **Delete the conditional wiring** in
   `cmd/vtuber-worker-node/main.go:165-175` and around `:360` that
   loads + invokes the publisher when `worker.service_registry_publisher`
   is set.
3. **Strip the `service_registry_publisher` block** entirely from
   `worker.example.yaml` (lines 67-92).
4. **Worker.yaml schema:** unknown fields are an error at parse time
   (already standard Zod-style behavior in Go via `yaml.KnownFields(true)`).
   No need for a special-case "deprecated" branch — `service_registry_publisher`
   simply isn't recognized.
5. **Rename `models:` → `offerings:`** in the `capabilities[]` block of
   `worker.example.yaml` and the worker config parser to match the
   modules v3.0.0 schema.
6. **Implement `/registry/offerings`** (per master plan §Decision 5)
   that emits the modules-canonical capability fragment built from the
   worker's `capabilities[]` config (capability name, work_unit,
   offerings[id, price_per_work_unit_wei], plus the streaming-session
   knobs in `extra` — `debit_cadence_seconds`, `sufficient_min_runway_seconds`,
   `sufficient_grace_seconds`). Optional bearer auth via the same
   token convention as `/metrics`.
7. **Doc updates** in `DESIGN.md`, `README.md`: same archetype-A
   framing as transcode-worker §7.

After landing, network-suite repins this submodule.

### F. livepeer-network-suite (this repo)

1. **Resolve plan 0002 Item 10** — strike-through Item 10's open status
   in [`0002-suite-wide-alignment.md`](./0002-suite-wide-alignment.md)
   with a back-pointer to this plan. Do **not** modify the plan body
   beyond that strike-through; history is immutable.
2. **Update `docs/design-docs/suite-architecture.md`** to call out
   archetype A as the canonical deploy pattern, with the diagram from
   Decision 1 above. Add a one-paragraph note that worker
   self-publishing is dead.
3. **Update `docs/design-docs/suite-conventions.md`** if it references
   the worker-publisher pattern as a permitted variation.
4. **Submodule additions + repins in one commit:**
   - **Add as new submodules** (created 2026-04-29):
     - `Cloud-SPE/livepeer-video-gateway` at `livepeer-video-gateway/`
     - `Cloud-SPE/video-worker-node` at `video-worker-node/`
   - **Drop the `livepeer-video-platform` pin** in the same commit.
   - **Advance every other submodule pin to its v3.0.0** in the same
     commit. There is no graceful order — every consumer of the modules
     schema (gateways, coordinator, secure-orch, workers) was updated
     together; pinning them out of order would just break the meta-repo's
     `submodule update` for whoever pulls mid-flight. One commit, all
     pins.
5. **Tag the suite v3.0.0** in the same release window. Update
   `release-process.md` with the v3.0.0 release notes covering the
   schema bump and archetype-A standardization.

### G. Consumer code + doc refresh (proto regen across every gRPC client)

Every gateway and console that holds a generated proto stub for the
modules service-registry must regenerate against the v3.0.0 proto and
update field references (`models` → `offerings`, `Model` → `Offering`,
etc.). These cuts ship at v3.0.0 too, in the same release window.

`livepeer-up` is covered separately in §H below because its template
changes span every host role.

| Repo | Code change | Doc change |
|---|---|---|
| `openai-worker-node` (pinned `v1.1.3`) | Cuts `v3.0.0`. Rename `capabilities[].models[]` → `capabilities[].offerings[]` in `worker.yaml` parser + `/capabilities` HTTP response (this worker's `/capabilities` shape closely tracks modules canonical, so the rename cascades through it). **Implement `/registry/offerings`** per master plan §Decision 5 (mirror the `/capabilities` body re-shaped into the modules-canonical fragment — `backend_url` stays omitted, same as today's `/capabilities`). Optional bearer auth via existing token convention. | README: "registry-invisible by design; bridge owns customer-facing routing; archetype A on the operator side. The orch-coordinator scrapes `/registry/offerings` to pre-fill the operator's roster." |
| `livepeer-openai-gateway` + `-core` | Cuts `v3.0.0`. Regen resolver proto stubs; rename `models`→`offerings` references in `src/main.ts` and gateway-core resolver client. **Adopt manifest pricing.** The bridge keeps its USD rate card for customer-facing prices, but the orch *wholesale* price input to routing comes from `offerings[i].pricePerWorkUnitWei` in the resolver response — replace the Postgres rate-card-driven wholesale-price logic in `src/service/pricing/` with a manifest-priced read. Workers with empty offering price are skipped (vtuber-gateway pattern). | DESIGN: "customer pricing remains bridge-controlled USD rate card; orch wholesale pricing is read from manifest `offerings[].pricePerWorkUnitWei` and used as the routing-decision input." |
| `livepeer-vtuber-project` | None — Python pipeline doesn't consume the registry proto directly. Doc-only confirmation. | ADR-009 confirms vtuber-gateway as the canonical embed-pricing pattern; no edits needed beyond a v3.0.0 version-bump note. |
| `livepeer-vtuber-gateway` | Cuts `v3.0.0`. Regen resolver proto stubs; rename `models`→`offerings`; update `pricePerWorkUnitWei` reader in `src/providers/serviceRegistry/grpc.ts`. | DESIGN: "manifest pricing is the canonical pattern; we read `offerings[i].pricePerWorkUnitWei` directly" |
| `livepeer-gateway-console` | Cuts `v3.0.0`. Regen resolver proto stubs; rename in capability-search code; update SPA labels to use "Offering" in any capability/pricing UI. | DESIGN confirms archetype A on the gateway-operator side |

### H. livepeer-up (scaffolding CLI — LAST in the wave)

Pinned at `v0.1.0`. Cuts `v3.0.0`. **Sequencing: must land last** —
its templates pin every other component's v3.0.0 image, so it can
only be authored after all other repos in §A through §G have tagged
v3.0.0. See Phase 2.5 in the Sequencing block below. Four host-role
templates live at
`internal/repo/templates/templates/{secure-orch,worker,gateway,coordinator}/`.
Each role gets `compose.yaml` + `env.tmpl` + `NEXT-STEPS.md` (and
`console-compose.yaml` for secure-orch and gateway).

Local exec-plan covers:

1. **`coordinator/` template:**
   - `NEXT-STEPS.md` — operator-facing manifest URL is
     `https://<host>/.well-known/livepeer-registry.json` (was
     `/manifest.json` in pre-v3.0.0). Drop any reference to the legacy
     path.
   - `compose.yaml` — pin `livepeer-orch-coordinator` image to
     `v3.0.0` (or whatever the suite's image-version pinning
     convention lands on per network-suite plan 0002 §Item 6).
   - `env.tmpl` — confirm env vars match the v3.0.0 coordinator's
     config schema (no `MANIFEST_SERVE_PATH` references to legacy
     filenames).

2. **`secure-orch/` template:**
   - `NEXT-STEPS.md` — `workers.yaml` skeleton uses `offerings:` not
     `models:` per modules v3.0.0; field names match
     `livepeer-secure-orch-console`'s `WorkersYamlSchema`.
   - `compose.yaml` + `console-compose.yaml` — pin daemon images
     (modules `service-registry-daemon`, `protocol-daemon`,
     `payment-daemon`) and `livepeer-secure-orch-console` to v3.0.0.

3. **`worker/` template:**
   - `compose.yaml` — pin `payment-daemon` image to v3.0.0; pin worker
     images (openai-worker-node v3.0.0, video-worker-node v3.0.0,
     vtuber-worker-node v3.0.0) per the role/workload variant the
     scaffold generates.
   - `NEXT-STEPS.md` — worker.yaml example uses `offerings:` per
     workload's v3.0.0 schema. **Drop any reference to
     `service_registry_publisher` or `registry_socket`** — archetype A
     means workers do not self-publish.
   - `env.tmpl` — confirm vars match each worker's v3.0.0 config.

4. **`gateway/` template:**
   - `compose.yaml` + `console-compose.yaml` — pin `service-registry-daemon`
     (resolver mode), `payment-daemon` (sender mode), and
     `livepeer-gateway-console` to v3.0.0.
   - `NEXT-STEPS.md` — gateway operator runbook references the
     resolver-sidecar pattern; "Offering" vocabulary in any capability
     descriptions.

5. **`templates.lock.json`** — regenerate after templates change so
   the lockfile hash reflects the v3.0.0 content.

6. **Daemon image pinning** — hardcoded `v3.0.0` references for
   every component (every other repo in §A through §G is at v3.0.0
   by the time §H lands; no version uncertainty). Network-suite plan
   0002 §Item 6 (single source of truth for image versions) is a
   later consolidation, not a prerequisite for this cut.

7. **DESIGN.md / README.md** updates: "scaffolds archetype A only;
   workers are registry-invisible; coordinator is the manifest source."

After landing, network-suite repins this submodule.

## Sequencing

Two phases. Modules-project lands first (its proto + schema are the
contract everyone else generates against); then everyone else lands in
parallel against modules v3.0.0 + tags v3.0.0; meta-repo repins all in
one commit and tags suite v3.0.0.

```
PHASE 1 ── modules-project schema + proto bump ──────────────────────
  livepeer-modules:
    - bump schema_version
    - rename Model → Offering in proto
    - regen Go stubs
    - update publisher daemon, resolver, livepeer-registry-refresh
    - update example files + docs
    - update host-archetype docs (archetype A only)
    - add adding-a-new-workload.md design doc
    - tag v3.0.0

PHASE 2 ── consumer cuts (parallel against modules v3.0.0) ──────────
  livepeer-orch-coordinator:
    - implement coordinator plan 0002 (full)
    - rewrite migrations/0001_init.sql; no data migration
    - SPA "Offering" everywhere
    - WorkerOfferingsScraper provider + scrape-and-draft SPA flow
    - tag v3.0.0

  livepeer-secure-orch-console:
    - rename in WorkersYamlSchema + grpc client
    - regen proto
    - drop SPA flatten in admin-manifest-publish.js
    - rewrite migrations/0001_init.sql
    - update workers.yaml.example
    - tag v3.0.0

  livepeer-video-platform → SPLIT into two new repos (§D):
    a) livepeer-video-gateway (NEW, from apps/api):
       - regen proto, rename references
       - adopt manifest pricing (read offerings[].pricePerWorkUnitWei)
       - tag v3.0.0
    b) video-worker-node (NEW, from apps/transcode-worker-node):
       - delete capabilityreporter, registryclient
       - drop registry CLI flags + config fields
       - design + ship workload-native /capabilities shape
       - implement /registry/offerings (modules-canonical fragment)
       - tag v3.0.0
    livepeer-video-platform: ARCHIVED after extraction.

  vtuber-worker-node:
    - delete publisherdaemon provider + wiring
    - strip service_registry_publisher block from example yaml
    - rename models → offerings in capabilities config
    - implement /registry/offerings (modules-canonical fragment;
      streaming-session knobs in extra)
    - tag v3.0.0

  openai-worker-node:
    - rename models → offerings in worker.yaml + /capabilities
    - implement /registry/offerings (modules-canonical fragment;
      backend_url omitted as today)
    - tag v3.0.0

  livepeer-openai-gateway + -core:
    - regen proto, rename references
    - adopt manifest pricing (read offerings[].pricePerWorkUnitWei
      as the wholesale price input; keep USD rate card for
      customer-facing prices)
    - tag v3.0.0

  livepeer-vtuber-gateway:
    - regen proto, rename references in price reader
    - tag v3.0.0

  livepeer-gateway-console:
    - regen proto, rename references; "Offering" in SPA
    - tag v3.0.0

PHASE 2.5 ── livepeer-up cut (LAST consumer; pins everything else) ──
  livepeer-up:
    - update all four host-role templates (§H)
    - rename models → offerings in worker NEXT-STEPS.md
    - move coordinator manifest path to /.well-known/livepeer-registry.json
    - pin all daemon + console + worker images to v3.0.0
      (every other consumer is at v3.0.0 by this point — no
       tech-debt entry needed for image-pinning convention)
    - regenerate templates.lock.json
    - tag v3.0.0

PHASE 3 ── meta-repo coordinated cut ────────────────────────────────
  livepeer-network-suite:
    - repin every submodule to v3.0.0 in ONE commit
    - drop livepeer-video-platform pin; add livepeer-video-gateway
      and video-worker-node pins
    - strike Item 10 in plan 0002 with backlink to plan 0003
    - close plan 0002 §Item 1 (split video-platform) since it
      lands in this wave
    - update suite-architecture.md
    - tag suite v3.0.0
    - update release-process.md with v3.0.0 release notes

DEPLOY GATE (after Phase 3) — manual end-to-end testing ─────────────
  Operator-driven, runbook lives at
  livepeer-orch-coordinator/docs/operations/manifest-roundtrip-smoke.md
  (authored as part of coordinator plan 0002 §6). Walks through:

    1. Stand up secure-orch host: protocol-daemon + service-registry
       publisher + secure-orch-console (compose stack).
    2. Stand up coordinator host: orch-coordinator (compose stack)
       behind a public-ish reverse proxy.
    3. Stand up at least one worker per workload type that this orch
       advertises: openai-worker-node, vtuber-worker-node,
       video-worker-node — each with payment-daemon (receiver mode)
       co-located.
    4. Stand up at least one gateway running the resolver sidecar:
       livepeer-openai-gateway, livepeer-vtuber-gateway, or
       livepeer-video-gateway.
    5. Operator round-trip: add workers to coordinator's roster
       (scrape /registry/offerings → confirm draft → save) →
       compose-proposal → workers.yaml downloaded → upload to
       secure-orch → BuildAndSign → registry-manifest.json downloaded
       → upload to coordinator → atomic-swap → public
       /.well-known/livepeer-registry.json serves the new bytes.
    6. Resolver verification: gateway's resolver sidecar (or modules
       examples/minimal-e2e) fetches the manifest, validates the
       signature against ORCH_ADDRESS, parses offerings, returns
       Select() responses with non-zero offerings[].pricePerWorkUnitWei.
    7. Pricing smoke: video-gateway and openai-gateway both route a
       request that exercises the manifest-priced wholesale lookup.

  Green = production deploy unblocked.
```

## Acceptance criteria

The deploy ships when **all** of:

1. **`livepeer-modules` v3.0.0** tagged with the schema bump + proto
   rename + archetype-A docs + new-workloads design doc.
2. **`livepeer-orch-coordinator` v3.0.0** tagged — coordinator plan
   0002 §1-§6 all checked off; fresh `migrations/0001_init.sql`;
   "Offering" used end-to-end (wire + SPA).
3. **`livepeer-secure-orch-console` v3.0.0** tagged — schema rename,
   SPA flatten removed, fresh `migrations/0001_init.sql`,
   workers.yaml.example uses `offerings:`.
4. **`livepeer-video-platform` split landed:**
   `livepeer-video-gateway` and `video-worker-node` exist as standalone
   repos, both tagged v3.0.0; `livepeer-video-platform` archived.
   `livepeer-video-gateway` adopts manifest pricing.
   `video-worker-node` ships its workload-native `/capabilities`
   response.
5. **`vtuber-worker-node` v3.0.0** tagged — alignment plan checked
   off; `service_registry_publisher` block gone; `offerings:` in
   worker.yaml.
6. **`openai-worker-node` v3.0.0** tagged — `models` → `offerings`
   rename in worker.yaml + `/capabilities`.
7. **`livepeer-openai-gateway` + `-core` v3.0.0** tagged — proto regen,
   rename, manifest-pricing adoption (wholesale price from
   `offerings[].pricePerWorkUnitWei`).
8. **`livepeer-vtuber-gateway` v3.0.0** tagged — proto regen, rename.
9. **`livepeer-gateway-console` v3.0.0** tagged — proto regen, rename,
   "Offering" in SPA.
10. **`livepeer-up` v3.0.0** tagged — all four templates updated;
    `templates.lock.json` regenerated; daemon image pins at v3.0.0.
11. **`livepeer-network-suite` plan 0002 Item 10** struck through with
    plan 0003 linked; **plan 0002 Item 1 (video-platform split) closed**
    in this wave; `suite-architecture.md` reflects archetype A.
12. **Every submodule pin** in network-suite advanced to v3.0.0 in one
    commit (with the video-platform → video-gateway+video-worker-node
    pin swap); suite tagged v3.0.0.
13. **Manual staging round-trip** (per coordinator plan 0002 §6) green:
    secure-orch publishes a workers.yaml → coordinator serves at
    `/.well-known/livepeer-registry.json` → modules `examples/minimal-e2e`
    resolver verifies the orch end-to-end. **Plus pricing-adoption smoke:**
    a video-gateway and openai-gateway both read
    `offerings[].pricePerWorkUnitWei` from the resolver response and
    route correctly.

## Open items deferred (not blocking deploy)

(none — all previously-deferred items pulled into v3.0.0 scope on
2026-04-29 per operator direction)

## Decisions log

### 2026-04-29 — Archetype B is not a permitted variation

Reason: enabling worker self-publishing as a parallel path doubles the
operator surface area, doubles the security model (cold-key vs hot-key
custody on the same network), and doubles the documentation burden for
new workload authors who otherwise have a single recipe to follow. The
existing worker-publisher integrations (transcode + vtuber) were
opportunistic — the coordinator + secure-orch path landed later and is
the better-thought-out story. Killing archetype B is a one-time cost
that simplifies the suite permanently.

### 2026-04-29 — `offering` rename across the wire, not just operator-facing (revised)

Originally drafted as operator-facing-only with the wire-format `models[]`
left untouched, deferring the rename to "the next v2 schema bump."
Revised after confirmation 2026-04-29 that the suite has no external
users and every component can break compatibility in a coordinated
v3.0.0 cut. Once the coordination cost is paid by the v3.0.0 wave
itself, there's no reason to leave the naming wart in the wire format.
The rename happens once, everywhere, and the suite ships clean.

### 2026-04-29 — Pricing is universal: orchs publish wholesale, gateways read it, gateways own retail

Reason: an earlier draft framed manifest pricing as opt-in per workload
to accommodate the openai-gateway's Postgres-stored wholesale rate
card. On reflection that pattern was duplicating wholesale truth in
two places (manifest + rate card) and silently relying on the
operator typing matching numbers in both — a drift bug waiting to
happen. v3.0.0 fixes it by making the manifest the single wholesale
source, with bridges keeping their rate cards for *retail* prices
only (USD per million tokens, etc. — the gateway's customer-facing
product). Empty wholesale price = orch opts out of routing for that
offering; gateways skip rather than imply free-tier semantics.

### 2026-04-29 — Clean reset, no backwards compatibility, no migrations

Reason: confirmed no external users, no on-chain `serviceURI` writes,
no production state to preserve. Every shred of compat code (alias
paths, dual-mode parsers, deprecation warnings, data-reshape
migrations) costs implementation + test + doc work for no real benefit.
A coordinated v3.0.0 cut is cheaper, ships faster, and leaves the suite
in a cleaner state than any progressive-rollout strategy. The cost is
"every test environment must wipe its state.db and re-run setup" —
acceptable since these are dev/test environments only.

### 2026-04-29 — Workers expose `/registry/offerings`; coordinator scrapes + operator confirms

Reason: pure operator-curated roster (the original §Decision 5 framing)
puts every capability/offering string on the operator to type by hand,
which is friction-heavy and drift-prone (operator types `gpt-oss-20b`
but worker actually serves `gemma4:26b`). Workload-type adapters in
the coordinator were rejected as cross-repo coupling that ages
poorly. The clean answer is a **dedicated uniform endpoint per worker**
(`/registry/offerings`) emitting the modules-canonical capability
fragment, with workload-specific bits in `extra`. Workers' workload-
native `/capabilities` stays unchanged. Coordinator scrapes the
uniform endpoint, presents a draft to the operator, operator
reviews/edits/confirms before save. This eliminates drift while
preserving operator control. Cost: ~30 lines of HTTP route + JSON
marshalling per worker repo.

### 2026-04-29 — Pull all three previously-deferred items into v3.0.0 scope

Reason: operator direction 2026-04-29. Originally the plan deferred
(a) manifest-pricing adoption by openai-gateway and video-gateway,
(b) the transcode-worker `/capabilities` shape redesign, and
(c) the `livepeer-video-platform` split into shell + worker repos.
Once the suite is doing a clean v3.0.0 reset anyway, deferring these
items just means a second cross-repo coordination wave a few weeks
later. Cheaper to land all of them in the v3.0.0 cut and ship the
suite in its final shape on the first try. The video-platform split
in particular is structurally cleanest done now: the v3.0.0 cut is
the natural moment to retire the monorepo, and doing it as a separate
later wave would mean cutting v3.0.0 against a doomed monorepo and
churning everything again.

