# Release process

A release of the Livepeer Network Suite is a **tag in this repo** that pins a coherent set of
submodule SHAs. The tag *is* the release artifact.

## Cadence

Releases are cut on demand, not on a clock. Drivers:

- A submodule ships a feature that other submodules consume.
- A bug fix needs to propagate to all deployments.
- A coordinated config or protocol change spans multiple submodules.

## Workflow

1. **Pre-flight.** From the meta-repo root:
   ```bash
   scripts/sync-submodules.sh --check
   ```
   This confirms the working tree is clean and every submodule's checkout matches its recorded pin.

2. **Advance pins.** For each submodule that needs to move:
   ```bash
   cd <submodule-path>
   git fetch origin
   git checkout <target-ref>           # tag or commit on the submodule's release branch
   cd -
   git add <submodule-path>            # records the new pin in the meta-repo
   ```

3. **Verify coherence.**
   ```bash
   scripts/sync-submodules.sh --verify
   ```
   This is the release gate. Compatibility checks live in the script — extend them as the
   suite grows (e.g., schema compatibility, shared protocol versions).

4. **Document the bump.** Edit `README.md`'s submodule table to reflect the new pins. For
   non-trivial bumps, drop a short note in `docs/exec-plans/completed/`.

5. **Commit and tag.**
   ```bash
   git commit -m "release: <summary>"
   git tag -s vMAJOR.MINOR.PATCH -m "release notes"
   ```
   The suite uses **semver** for release tags — the v3.0.0 coordinated cut
   set the precedent. Submodules tag the same `vMAJOR.MINOR.PATCH` for any
   coordinated wave; the meta-repo tag pins them together.

6. **Push.**
   ```bash
   git push origin main --tags
   ```

## Rollback

A release is just a tag. To roll back, **cut a new tag** pointing at the previous good commit.
Do not delete or move tags that have been pushed — consumers may pin them.

## What this process does not do

- It does not release the **submodules themselves** — each submodule has its own release flow.
- It does not deploy. Deployment manifests live in the relevant submodule.
- It does not bump container image tags. Per
  [`design-docs/core-beliefs.md`](./design-docs/core-beliefs.md), that requires explicit approval.
