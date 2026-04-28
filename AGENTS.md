# AGENTS.md

This repo coordinates the **Livepeer Network Suite** — a meta-repo of git submodules that
ship together. You (the agent) are working in the *coordinator*, not in any one component.
Almost all code lives inside submodules.

## Operating principles

This repo follows the agent-first harness pattern described in
[`docs/references/openai-harness.pdf`](./docs/references/openai-harness.pdf). The short version:

- **You steer; the agent executes.** Humans set intent; tools and feedback loops do the rest.
- **The repo is the system of record.** If it isn't checked in, it doesn't exist to the agent.
- **Progressive disclosure.** This file is a *map*, not a manual. Click through to deeper sources.
- **Enforce invariants, not implementations.** Constraints live in lints/CI; choices live in submodules.
- **Throughput over ceremony.** Short-lived PRs, fix-forward over block, automerge what can be automerged.

Read [`docs/design-docs/core-beliefs.md`](./docs/design-docs/core-beliefs.md) before making
cross-submodule decisions.

## Where to look

| Question | File |
|---|---|
| What is this repo and what does each submodule do? | [`README.md`](./README.md) |
| What invariants must any change uphold? | [`docs/design-docs/core-beliefs.md`](./docs/design-docs/core-beliefs.md) |
| How do the submodules fit together? | [`docs/design-docs/suite-architecture.md`](./docs/design-docs/suite-architecture.md) |
| What conventions hold across submodules and where do they drift? | [`docs/design-docs/suite-conventions.md`](./docs/design-docs/suite-conventions.md) |
| What design work is in flight? | [`docs/exec-plans/active/`](./docs/exec-plans/active/) |
| What design work has shipped? | [`docs/exec-plans/completed/`](./docs/exec-plans/completed/) |
| What known tech debt are we tracking? | [`docs/exec-plans/tech-debt-tracker.md`](./docs/exec-plans/tech-debt-tracker.md) |
| How do I cut a synchronized release across submodules? | [`docs/release-process.md`](./docs/release-process.md) |
| How do I bump a submodule pin? | `scripts/sync-submodules.sh --help` |
| Reference material (papers, PDFs, external docs)? | [`docs/references/`](./docs/references/) |
| Auto-generated reference (dep graphs, SBOMs)? | [`docs/generated/`](./docs/generated/) |

## Doing work in this repo

- **Submodule changes belong in the submodule, not here.** This repo only updates pins.
- **A pin bump is a real change.** If it crosses submodule boundaries, open a plan in
  `docs/exec-plans/active/` first.
- **Never edit submodule contents from this checkout.** `cd` into the submodule, branch, PR,
  bump the pin from the meta-repo as a separate step.
- **Release tags here pin a coherent set of submodule SHAs.** Treat the tag as the release artifact.

## What lives in submodules (not here)

Implementation, tests, deploy manifests, runtime configs, per-component CI. This repo is
intentionally small — it should rarely contain anything that isn't a pin, a doc, or a script.

## Doc-gardening expectations

Stale docs are worse than missing docs. When you change a process or an invariant, update the
doc in the same PR. A recurring agent will eventually scan for drift and open fix-up PRs;
until that's wired up, the responsibility falls on whoever opens the PR.
