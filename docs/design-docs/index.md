# Design docs

Cross-cutting design decisions for the Livepeer Network Suite as a whole.

| Doc | Status | What it covers |
|---|---|---|
| [core-beliefs.md](./core-beliefs.md) | active | Invariants every change must uphold |
| [suite-architecture.md](./suite-architecture.md) | living | How the submodules layer together (updated as each is added) |
| [suite-conventions.md](./suite-conventions.md) | living | Patterns that emerged across submodules + drift map. Pairs with `exec-plans/active/0002-suite-wide-alignment.md` |

Submodule-local designs live inside their respective submodules. Promote a doc here only when
it binds *more than one* submodule. If a doc only describes one submodule, it belongs in that
submodule's own `docs/`, not here.
