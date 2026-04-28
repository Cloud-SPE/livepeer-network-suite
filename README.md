# Livepeer Network Suite

A meta-repo coordinating the Livepeer Network components that ship together. Each component
lives in its own git submodule with its own release cycle; this repo pins a coherent set of
SHAs and documents how they fit together.

> **For agents:** start at [`AGENTS.md`](./AGENTS.md). The README below is a human-oriented overview.

## Submodules

This table is the canonical list of components in the suite. Edit it whenever a submodule is
added, removed, or repinned.

| Submodule | Path | Role in the suite | Tracked branch | Pinned at |
|---|---|---|---|---|
| [`livepeer-modules`](./livepeer-modules) | `livepeer-modules/` | On-chain control plane: `chain-commons` lib + `payment-daemon`, `service-registry-daemon`, `protocol-daemon` (gRPC over unix sockets, Arbitrum One) | `main` | `v1.0.0` (`a109687`) |
| [`livepeer-up-installer`](./livepeer-up-installer) | `livepeer-up-installer/` | Operator scaffolding CLI (`livepeer-up`) — drops `compose.yaml` + `.env` template + placeholder keystore + `NEXT-STEPS.md` for each host role; **writes files only** | `main` | `v0.1.0` (`fb6b3a2`) |
| [`livepeer-secure-orch-console`](./livepeer-secure-orch-console) | `livepeer-secure-orch-console/` | LAN-only admin console for the cold-key custodian on `secure-orch`: round/reward status, `Publisher.BuildAndSign`, force-action buttons. Mounts `protocol-daemon` + `service-registry-daemon` (publisher) sockets. Bearer-token auth | `main` | `v0.1.3` (`806e55f`) |
| [`livepeer-orch-coordinator`](./livepeer-orch-coordinator) | `livepeer-orch-coordinator/` | Public-facing fleet dashboard + signed-manifest hosting at the on-chain `serviceURI`. **No keys, no daemon sockets.** Verifies sig against on-chain orch identity. Worker Prometheus scraping; daily-ops console | `main` | `v0.1.1` (`591b491`) |
| [`livepeer-gateway-console`](./livepeer-gateway-console) | `livepeer-gateway-console/` | Gateway operator's routing dashboard. Mounts `service-registry-daemon` (resolver) + `payment-daemon` (sender) sockets. Capability search via `Resolver.Select`, sender wallet + escrow status, manual cache refresh, audit log | `main` | `1bf67d9` (no tag yet) |
| [`openai-worker-node`](./openai-worker-node) | `openai-worker-node/` | Payee-side OpenAI adapter on `worker-orch`. HTTPS in front of local OpenAI-compatible inference backends (vLLM, diffusers, whisper, TTS). Validates payment via co-located `payment-daemon` over unix socket. Capability set: chat, embeddings, image gen/edit, audio speech/transcription | `main` | `v1.1.3` (`72653f9`) |
| [`livepeer-openai-gateway`](./livepeer-openai-gateway) | `livepeer-openai-gateway/` | Payer-side OpenAI adapter on `gateway`. OpenAI-compatible API (chat/embeddings/images/audio) fronting a pool of worker-nodes. Customers pay USD (free tier + prepaid via Stripe); the service pays nodes in ETH via `payment-daemon` (sender). Postgres ledger; customer + admin SPAs; consumes OSS engine `@cloudspe/livepeer-openai-gateway-core` | `main` | `65a1002` (no release tag yet) |
| [`livepeer-openai-gateway-core`](./livepeer-openai-gateway-core) | `livepeer-openai-gateway-core/` | OSS engine that powers `livepeer-openai-gateway`. OpenAI-compatible request engine fronting Livepeer worker pools. Adapter-driven: 5 operator-overridable adapters (Wallet, AuthResolver, RateLimiter, Logger, AdminAuthResolver). Ships an optional Fastify route adapter and read-only operator dashboard | `main` | `v0.2.0` (`bc7557f`) |
| [`livepeer-video-core`](./livepeer-video-core) | `livepeer-video-core/` | OSS video engine — VOD + Live HLS dispatch over Livepeer worker pools. Framework-free; ships an optional Fastify adapter. Adapter-driven (11 adapters: Wallet, AuthResolver, AdminAuthResolver, RateLimiter, Logger, StorageProvider, WebhookSink, WorkerResolver, WorkerClient, EventBus, StreamKeyHasher). Cost model: `time × codec × rendition × tier` | `main` | `v0.2.0` (`3d01c16`) |
| [`livepeer-video-platform`](./livepeer-video-platform) | `livepeer-video-platform/` | Hybrid Go+TS monorepo bundling the **video shell + worker**. Contains `livepeer-video-gateway` (TS shell at `apps/api/`, consumes the engine via npm) and `livepeer-video-worker-node` (Go worker at `apps/transcode-worker-node/`). Mux-inspired feature set (direct uploads, asset playback, live streaming, signed URLs, webhooks) but **not Mux-API-compatible**. Single tag covers shell + worker | `main` | `v0.2.0` (`17dad2e`) |
| [`livepeer-vtuber-project`](./livepeer-vtuber-project) | `livepeer-vtuber-project/` | **Consumer SaaS ("Pipeline") on top of the suite.** Autonomous AI VTuber streamed live to YouTube/RTMP. Customers buy + create VTubers; compute runs on Livepeer; nested LLM/TTS calls go through `livepeer-openai-gateway`. Forks Open-LLM-VTuber. Python (~790 KB) — new language for the suite | `main` | `b1bcdac` (no tag yet) |
| [`livepeer-vtuber-gateway`](./livepeer-vtuber-gateway) | `livepeer-vtuber-gateway/` | Payer-side gateway for the **`livepeer:vtuber-session`** capability. `POST /v1/vtuber/sessions` mints session-scoped child bearers (`vtbs_*`); routes to a `vtuber-worker-node` via the resolver; pays via `payment-daemon` sender. WebSocket relay for `/control` (customer) and `/worker-control` (worker) — usage ticks debit the customer's USD ledger. Stripe top-up. M1-M9 milestones complete; 348 tests passing. Structurally forked from `livepeer-openai-gateway` skeleton (no shared code; byte-equivalence via property tests) | `main` | `7138f39` (no tag yet) |
| [`vtuber-worker-node`](./vtuber-worker-node) | `vtuber-worker-node/` | Payee-side worker for the **`livepeer:vtuber-session`** capability. Hosts the `StreamingModule` interface; payment middleware via co-located `payment-daemon` (receiver); publishes capability via co-located **`service-registry-daemon` (publisher)**; forwards session-open requests to a local `session-runner` backend (housed in `livepeer-vtuber-project`). Go binary, custom `payment-middleware-check` golangci-lint analyzer. **Status: M1 — skeleton only**, contract tests + module impl land in M2-M4 | `main` | `52a0336` (no tag yet) |

For a layered view of how the submodules fit together, see
[`docs/design-docs/suite-architecture.md`](./docs/design-docs/suite-architecture.md).

## Quick start

```bash
# Clone with all submodules in one shot
git clone --recursive <this-repo-url>
cd livepeer-network-suite

# Or, if already cloned without --recursive
git submodule update --init --recursive
```

## Keeping submodules in sync

The meta-repo records a specific commit for each submodule (a "pin"). After pulling new
commits on `main`, your local submodule checkouts may lag the recorded pins.

```bash
# Match every submodule to the recorded pins (most common case)
git submodule update --init --recursive

# Report which submodules drift from their pins
scripts/sync-submodules.sh --check

# Advance pins to each submodule's upstream HEAD (stages a candidate commit)
scripts/sync-submodules.sh --update
```

`scripts/sync-submodules.sh --help` lists every mode.

## Cutting a release

A release of the suite is a tag in this repo that pins a coherent set of submodule SHAs.
The tag *is* the release artifact. Full procedure:
[`docs/release-process.md`](./docs/release-process.md).

TL;DR:

```bash
scripts/sync-submodules.sh --check       # working tree clean, pins match checkouts?
# advance pins as needed (see release-process.md)
scripts/sync-submodules.sh --verify      # release gate
git tag -s vYYYY.MM.DD-NN -m "release notes"
git push origin main --tags
```

## Repository layout

```
.
├── AGENTS.md                 # Entry-point map for coding agents
├── CLAUDE.md                 # Stub pointing Claude Code at AGENTS.md
├── README.md                 # You are here
├── docs/
│   ├── design-docs/          # Cross-submodule design (start at index.md)
│   ├── exec-plans/           # active/, completed/, tech-debt-tracker.md
│   ├── generated/            # Machine-produced reference (dep graphs, SBOMs)
│   ├── references/           # External material (PDFs, papers)
│   └── release-process.md    # How to cut a coherent release
└── scripts/
    └── sync-submodules.sh    # Pin verification, bump, release helpers
```

Submodule contents are out-of-tree from this repo's perspective — `cd` into one to work on it.

## Conventions

See [`docs/design-docs/core-beliefs.md`](./docs/design-docs/core-beliefs.md) for the
non-negotiables. Most relevant to release work:

- **Mainnet-only** for Livepeer-touching submodules. No testnet smoke runs.
- **Image tags are not bumped silently.** Republishing overwrites the existing pin unless a
  version bump is approved.
- **Pinned SHAs are the release artifact.** The tag is canonical.
