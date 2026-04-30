---
title: Suite-wide alignment — converge conventions across submodules
status: active
created: 2026-04-28
owner: human (the meta-repo operator)
---

# Suite-wide alignment

A consolidated punch-list for converging conventions across the 14
submodules. Sourced from the drift map in
[`design-docs/suite-conventions.md`](../../design-docs/suite-conventions.md).

Pair this with the upstream-naming-cleanup plan
([`active/0001-upstream-naming-cleanup.md`](./0001-upstream-naming-cleanup.md)) —
they overlap in places (renames cascade through code, configs, and docs).

## Priority order

Group by leverage. Items at the top unblock or simplify items below them.

1. **High leverage** (fix once, ripples through everything else):
   - ~~Item 1 — split `livepeer-video-platform`~~ (RESOLVED 2026-04-29 — see plan 0003 §D)
   - Item 2 — create `livepeer-modules-conventions` (or kill the references)
   - Item 3 — share daemon protos
2. **Medium leverage** (visible drift, mechanical fixes):
   - Item 4 — align layer-stack order on the TS side
   - Item 5 — pick one admin-auth header convention
   - Item 6 — pin daemon image versions to a single source of truth
3. **Lower leverage** (correctness, but bounded blast radius):
   - Item 7 — tag every untagged submodule
   - Item 8 — resolve license TBDs
   - Item 9 — pick a documentation style (in-repo vs upstream-canonical)
4. **Open architectural decisions** (need a real call before alignment):
   - Item 10 — publisher-on-worker semantics
   - Item 11 — engine + shell pattern: required for every workload?
   - Item 12 — "no shared code" pattern at scale

---

## ~~Item 1 — split `livepeer-video-platform` into shell + worker repos~~ (RESOLVED 2026-04-29)

**Resolution:** done in plan 0003 §D as part of the v3.0.0 coordinated
cut. `livepeer-video-platform/apps/api/` was extracted to
`Cloud-SPE/livepeer-video-gateway` (Option A) and
`livepeer-video-platform/apps/transcode-worker-node/` was extracted to
`Cloud-SPE/video-worker-node` (worker drops the `livepeer-` prefix per
convention). The meta-repo dropped the `livepeer-video-platform` pin and
added the two new pins in the v3.0.0 wave (commits 878b981, 00243f7).
The bundle dev-stack (`infra/compose.yaml`) moved into
`livepeer-video-gateway`.

See [`0003-archetype-a-deploy-unblock.md`](./0003-archetype-a-deploy-unblock.md)
§D for the full extraction record.

## Item 2 — resolve the missing `livepeer-modules-conventions` repo

Three submodule READMEs link to it. It doesn't exist. **Pick one:**

- **Create it.** A minimal repo (or doc tree inside `livepeer-modules`)
  containing: cross-suite metric naming + namespacing, port allocation
  per daemon/worker, shared lint catalog, naming conventions, host-
  archetype variations (including the publisher-on-worker note from
  Item 10), the engine + shell pattern itself.
- **Kill the references.** Inline what's needed in each README; remove
  the broken links. Lower effort but doesn't address that the suite
  clearly *wants* a conventions home.

Recommendation: create it. It would also be a natural home for shared
daemon protos (Item 3), the suite-wide lint catalog, and this very
conventions doc as a public artifact.

## Item 3 — share daemon protos instead of vendoring per consumer

Today every consumer of the daemons vendors the `.proto` files
independently:

- `livepeer-modules/payment-daemon/...` (canonical)
- `openai-worker-node/internal/proto/livepeer/payments/v1/`
- `livepeer-openai-gateway/src/providers/payerDaemon/gen/`
- `livepeer-gateway-console/src/providers/payerDaemon/gen/` + `resolver/gen/`
- `livepeer-vtuber-gateway` (uses `npm run proto:gen`)
- `vtuber-worker-node/internal/proto/...`
- `video-worker-node/internal/proto/...`

**Move:** publish daemon protos as a package. Two routes:

- **TS side:** `@cloudspe/livepeer-daemon-protos` on npm, consumed by
  every TS shell + console. Generated once per release.
- **Go side:** a versioned Go module (e.g.,
  `github.com/Cloud-SPE/livepeer-modules/protos`) consumed by every
  Go worker.

Both routes can share a single source of truth in
`livepeer-modules/<daemon>/proto/`. Generation is per-language but the
`.proto` is shared.

Once this lands, retire the path-discrepancy gotcha (Item in tech-debt
about `../livepeer-modules-project/` sibling expectations) — consumers
no longer need a sibling checkout.

## Item 4 — align the layered-architecture order on the TS side

Two orderings observed:

- `livepeer-openai-gateway`: `types → config → providers → repo → service → runtime → main`
- consoles: `types → config → repo → service → runtime → providers → utils`

Semantic difference: providers-below-repo means repo can use providers;
providers-above-repo means providers compose repos.

**Move:** pick one. Recommend the openai-gateway order (providers below
repo) — it's slightly more permissive and matches what the engines do
internally. Update each repo's custom `layer-check` lint to match.

## Item 5 — pick one admin-auth header

- `livepeer-openai-gateway` admin endpoints use `X-Admin-Token`.
- The 3 operator consoles use `Authorization: Bearer`.

Same security model, different wire shape. **Move:** pick one
(recommend `Authorization: Bearer` — fewer custom headers, plays nicer
with proxies + tooling). Update the openai-gateway's `/admin/*` routes
+ tests + customer-facing docs.

## Item 6 — pin daemon image versions to a single source of truth

Three anchors observed today:

- `livepeer-modules` README: `v1.0.0`
- `livepeer-openai-gateway` compose: `v1.4.0`
- User memory (formerly): `v0.8.10`

**Move:** the canonical daemon-image version is whatever
`livepeer-modules` publishes most recently. Every other consumer
references it transitively (via env var, via a shared compose snippet,
or via the `livepeer-modules-conventions` repo from Item 2).

Cap with: `scripts/sync-submodules.sh --verify` parses the consumer
compose files and asserts the daemon image tags match the
`livepeer-modules` pin. (Already in tech-debt as a script extension.)

## Item 7 — tag every untagged submodule

Five submodules currently have no version tag:

- `livepeer-gateway-console` (M9 functionally complete) → `v0.1.0`
- `livepeer-openai-gateway` (production with rolling Docker tag `v0.8.10`) → `v0.8.10` git tag at the same SHA
- `livepeer-vtuber-project` (mid-realignment) → `v0.1.0` once realignment stabilizes
- `livepeer-vtuber-gateway` (M9 complete) → `v0.1.0`
- `vtuber-worker-node` (M1 skeleton) → `v0.1.0` once M2-M4 land

After tagging, repin each in this meta-repo. `scripts/sync-submodules.sh --check`
will report drift if a tag move requires it.

## Item 8 — resolve license TBDs

These submodules ship without a license today:

- `livepeer-vtuber-project` ("TBD before first external release")
- `livepeer-vtuber-gateway` ("TBD before first external release")
- `vtuber-worker-node` ("TBD before first external release")
- `video-worker-node` ("license TBD")
- `openai-worker-node` (no LICENSE file)

The pattern across the suite is: **engines MIT, shells proprietary,
workers ?**. Workers are the missing decision. Pick one (likely either
matches engines (MIT) for ecosystem, or matches shells (proprietary)
for control), and apply uniformly.

## Item 9 — pick a documentation style: in-repo vs upstream-canonical

Two observed patterns:

- **In-repo design** (OpenAI side): every repo has its own
  `DESIGN.md`, `PRODUCT_SENSE.md`, etc.
- **Upstream-canonical** (vtuber side): `livepeer-vtuber-project` holds
  all design; `livepeer-vtuber-gateway` and `vtuber-worker-node` have
  intentionally minimal `docs/` and link upstream.

Both are defensible:

- In-repo is more navigable when working on one component in isolation.
- Upstream-canonical avoids drift across siblings of the same workload.

**Move:** the user picks. Recommendation: upstream-canonical at the
*workload* level — one repo holds design for a workload type, the
implementation repos link to it. Generalizes the vtuber pattern.

If we go that way, retroactively: extract the OpenAI workload's
canonical design to a `livepeer-openai-project` repo (or fold into
`livepeer-modules-conventions` from Item 2), and have `livepeer-openai-gateway`
+ `openai-worker-node` link to it.

## ~~Item 10 — document publisher-on-worker semantics~~ (RESOLVED 2026-04-29)

**Resolved by [plan 0003](./0003-archetype-a-deploy-unblock.md):**
worker self-publishing is dead. Workers (openai-worker-node,
vtuber-worker-node, video-worker-node) are registry-invisible under
archetype A; the orch-coordinator scrapes `/registry/offerings` and
the secure-orch console signs the manifest. The pre-v3.0.0
capabilityreporter / publisherdaemon paths have been deleted from the
worker repos.

Original (now-superseded) text follows for history:

## Item 10 (HISTORICAL) — document publisher-on-worker semantics

Two workload workers (the pre-v3.0.0
`livepeer-video-platform/apps/transcode-worker-node/` and
`vtuber-worker-node`) co-located `service-registry-daemon` in
publisher mode, which contradicted `livepeer-modules`'s host-archetype
model.

**Move:** read the publisher's gRPC surface to confirm whether worker
publishers sign leaf manifests (per-worker capability fragments) while
secure-orch publishers sign rooted manifests. Then either:

- Update `livepeer-modules`'s host-archetype docs to acknowledge the
  worker-publisher pattern as a real variation.
- Or, if it's actually a misuse, fix the worker compose stacks.

This unblocks future workload types — they need to know which model to
follow.

## Item 11 — engine + shell pattern: required for every workload?

OpenAI has an engine (`livepeer-openai-gateway-core`); video has an
engine (`livepeer-video-core`); vtuber doesn't (the gateway is direct).
Question for the suite: is the engine required for every workload, or
optional?

**Move:** decide. Two paths:

- **Engine required.** Extract `livepeer-vtuber-gateway-core` from the
  current vtuber gateway. Pre-1.0 the way the others are. Keeps the
  pattern uniform; trades dev cost for consistency.
- **Engine optional.** Document when an engine is worth it. Likely:
  when a third party might build their own shell, OR when there are
  multiple shells of the same workload type.

Vtuber today has one shell, presumably no third-party shell builders.
Engine would be premature. So in practice the answer is "engine
optional, extract when there's a second consumer." Worth writing down.

## Item 12 — "no shared code" pattern at scale

ADR-003 in `livepeer-vtuber-project` mandates that sibling repos
(OpenAI gateway ↔ vtuber gateway, OpenAI worker ↔ vtuber worker) share
**zero source code**, with byte-equivalence pinned via property tests.
Same pattern as vendoring daemon protos.

Works for two workload pairs. Likely to break at four. **Move:** decide
the inflection point. Options:

- Hold the line — accept manual coordination cost as the price of zero
  coupling.
- Extract shared TS-side primitives (auth, Stripe top-up, Drizzle
  config wiring) into a `@cloudspe/livepeer-shell-toolkit` package
  consumed by every shell. Pre-1.0 the way the engines are.

Probably the answer is "extract once we have a third workload." VTuber
is the third — but it copied from OpenAI, not from a shared package.
Worth revisiting before adding a fourth.

---

## Tracking progress

- Each item gets a row added or moved to "completed" when shipped.
- `livepeer-network-suite` gets a re-pin (and possibly a release tag) as
  alignment items land.
- Recount drift counters in `suite-conventions.md` after each major
  item.
