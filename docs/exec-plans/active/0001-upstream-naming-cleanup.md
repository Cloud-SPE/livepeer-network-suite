---
title: Upstream naming cleanup — retire "bridge" and "BYOC"
status: active
created: 2026-04-28
owner: human (the meta-repo operator)
---

# Upstream naming cleanup — retire "bridge" and "BYOC"

Two terms have been retired across the Livepeer Network Suite but still
appear in upstream submodules. This plan tracks where they need to go.

## Canonical terms

| Retired | Use instead | Notes |
|---|---|---|
| `bridge` | `gateway` | The payer-side service is a **gateway**, not a bridge. The repo `livepeer-openai-gateway` is the canonical name; `openai-livepeer-bridge` is wrong. |
| `BYOC` | `OpenAI adapter` (specific) / `paid HTTP adapter` (generic) | "Bring Your Own Compute" — earlier framing, no longer applicable. |

When a submodule README or piece of code uses either term, it's a bug.
Update upstream and re-pin in this meta-repo.

## Per-submodule status

Counts captured 2026-04-28 from each submodule's pinned commit. Recount
after each cleanup PR.

| Submodule | `bridge` | `BYOC` | Highest-leverage renames |
|---|---:|---:|---|
| `livepeer-modules` | 116 | 19 | README, AGENTS.md, PRODUCT_SENSE.md |
| `livepeer-up-installer` | 15 | 0 | README role/template wording |
| `livepeer-secure-orch-console` | 16 | 1 | README, DESIGN.md, FRONTEND.md, CHANGELOG, compose.prod.yaml |
| `livepeer-orch-coordinator` | 17 | 0 | FRONTEND.md, CHANGELOG.md |
| `livepeer-gateway-console` | 89 | 0 | **`bridge-ui/` → `gateway-ui/`** (cascades to package.json scripts, tsconfig exclude, eslint config) — biggest single move |
| `openai-worker-node` | 92 | 3 | README, AGENTS.md, DESIGN.md, PLANS.md, worker.example.yaml, PRODUCT_SENSE.md (the README's diagram literally says "bridge ──HTTPS──▶ openai-worker-node") |
| `livepeer-openai-gateway` | 1699 | 2 | **`bridge-ui/` → `gateway-ui/`** + **`eslint-plugin-livepeer-bridge` → `eslint-plugin-livepeer-gateway`** (cascades to package.json description/scripts, eslint.config.js, every rule import) |
| `livepeer-openai-gateway-core` | 294 | 0 | README + docs/architecture.md + adapter docs. Also: README's links to `livepeer-modules-project/livepeer-payment-library` and `livepeer-modules-project/service-registry-daemon` are broken (those repos don't exist; the canonical home is `Cloud-SPE/livepeer-modules`). |
| `livepeer-video-core` | 31 | 0 | Light usage — mostly README + docs. Lower-priority sweep. |
| `livepeer-video-gateway` | _(recount)_ | _(recount)_ | Replaces the retired `livepeer-video-platform` (210 / 1) entry after the v3.0.0 split. Inherited the bridge-pattern wording in README; recount after cleanup. |
| `video-worker-node` | _(recount)_ | _(recount)_ | Replaces the retired `livepeer-video-platform/apps/transcode-worker-node/` entry. Skeleton-stage repo; recount once Phase 2 code lift lands. |
| `livepeer-vtuber-project` | **1053** | **65** | Highest BYOC density in the suite. Repo name was already de-BYOC'd but the term still pervades the codebase. README still announces sibling pair under retired-term names (`vtuber-livepeer-bridge` + `openai-livepeer-bridge`); the actual `livepeer-vtuber-gateway` repo has been created with the correct name, but the README in `livepeer-vtuber-project` still references the old names. |
| `livepeer-vtuber-gateway` | 295 | 1 | **The repo's own README internal title says "vtuber-livepeer-bridge"** — the most visible per-repo error. README + design-doc text + `dist/` references throughout. Repo name on GitHub is correct (`livepeer-vtuber-gateway`); just the contents need updating. |
| `vtuber-worker-node` | 143 | 1 | Skeleton-stage repo (M1) — fewer hits, but also fewer files. Most "bridge" references are in the README's siblings/links pointing at retired-named places (e.g., `livepeer-modules-project/...`). Light sweep. |

## Suggested order (do high-leverage cascades first)

1. `livepeer-openai-gateway`
   - Rename `bridge-ui/` → `gateway-ui/` (or your preferred replacement).
   - Rename eslint plugin: `eslint-plugin-livepeer-bridge` → `eslint-plugin-livepeer-gateway`. Update every rule import.
   - Update `package.json` description, scripts (`build:ui`, `dev:ui:portal`, `dev:ui:admin`, `test:ui`).
   - Sweep code, comments, docs.
2. `livepeer-gateway-console` — apply the same `bridge-ui/` rename. ESLint plugin too if used.
3. `openai-worker-node` — README and DESIGN.md sweep. Update the architecture diagram caption.
4. `livepeer-modules` — README + AGENTS.md + PRODUCT_SENSE.md.
5. The three console / installer repos — straight string replace; small surface.

## After each cleanup PR lands

- Repin the submodule in this meta-repo.
- Recount with: `for d in <submodules>; do grep -rIi -c bridge "$d"; done`.
- Update this plan's count column.
- When all counts hit 0, move this plan to `completed/`.

## Meta-repo's own usage

I scrubbed all my own uses of "bridge" and "BYOC" from this repo's docs in
the same session this plan was created. Two upstream-quoted references
remain in `docs/design-docs/suite-architecture.md` (the `bridge-ui/`
directory name and the naming-drift note pointing at this plan) — those
will resolve when the upstream renames land.
