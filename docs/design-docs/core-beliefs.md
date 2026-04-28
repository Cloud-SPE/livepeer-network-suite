# Core beliefs

Invariants any change to this meta-repo must uphold. These exist because past incidents (or
strong stakeholder preference) made them load-bearing. If you want to change one, open a plan
in `exec-plans/active/` first — don't sneak it in alongside other work.

## 1. The meta-repo coordinates; it does not contain

Submodules are the unit of code. This repo holds **pins, docs, and sync tooling**. If you find
yourself adding implementation here, stop and put it in a submodule.

## 2. Pinned SHAs are the release artifact

A release tag in this repo is a frozen, verified combination of submodule SHAs. Don't move
pins outside the release process. Don't push a tag without running the sync verification.

## 3. Mainnet-only — no Livepeer testnets

Livepeer-related submodules deploy and smoke-test against **Arbitrum One from day one**.
Mitigate risk with dust amounts, not testnets. Testnets have repeatedly diverged from mainnet
in ways that mask real failures.

## 4. Image tags are not bumped silently

When republishing a Cloud-SPE image, **overwrite the existing named tag** rather than
inventing a new version. Version bumps require explicit approval. The current pin convention
across Cloud-SPE images is `v0.8.10` — match that unless told otherwise.

## 5. Documentation is enforced, not aspirational

Stale docs are worse than missing docs. Update docs in the same PR that changes the behavior
they describe. CI should lint the knowledge base; a doc-gardening agent should run on a
cadence and open fix-up PRs. If a rule isn't enforceable mechanically, either promote it to a
lint or accept that it will rot — don't write it down and hope.

## 6. Throughput-friendly merge gates

Short-lived PRs. Minimal blocking checks. Test flakes get follow-up runs, not indefinite
blocks. Corrections are cheap; waiting is expensive.

## 7. Progressive disclosure beats encyclopedic AGENTS.md files

`AGENTS.md` is a *map* (~100 lines), not a manual. Push detail into `docs/` and link from the
map. When everything is "important," nothing is.
