---
title: Streaming workload pattern
status: accepted
last-reviewed: 2026-05-02
---

# Streaming workload pattern

Cross-workload blueprint for long-lived, continuously-metered workloads on
the Livepeer network. This is the suite-level pattern new streaming
workloads should adopt unless they have a strong, explicit reason to do
something else.

Examples:

- VTuber sessions
- live video sessions
- realtime voice / agent sessions
- other long-lived capability executions where usage accrues over time

This doc is intentionally cross-cutting. It binds the gateway shell, the
worker, and both payment-daemon roles.

## Scope

This pattern is for **streaming** workloads, not the existing
request/response pattern used by the OpenAI gateway family.

Request/response pattern:

- one request
- one routing decision
- one payment envelope
- one worker response
- one customer-ledger commit

Streaming pattern:

- one session open
- one or more customer-initiated topups
- many worker-side debit ticks
- many worker-to-gateway usage events
- one terminal close

## Pattern B summary

The canonical streaming pattern is:

- gateway resolves worker + offering and mints credit
- worker credits a receiver-side session balance
- worker debits that balance locally on cadence
- worker emits idempotent usage events to the gateway
- gateway updates the customer-facing billing ledger from accepted events

Short version:

- worker-side meter for runtime enforcement
- gateway-side ledger for customer accounting

This split is deliberate. The runtime-critical balance check lives next to
the actual session runtime, while the customer ledger remains centralized
and auditable.

## Why this is the suite default

Advantages:

- the worker can keep enforcing runway even if the gateway is briefly slow
  or unavailable
- the debit loop does not depend on a worker-to-gateway round trip
- low-balance and grace handling live beside the actual session runtime
- customer billing remains centralized and auditable at the gateway
- the same shape applies across multiple workload families

Tradeoffs:

- worker/gateway reconciliation is more complex than a purely
  gateway-owned meter
- the worker and gateway need a durable idempotent event contract
- topup correlation and final reconciliation must be explicit

## Roles

### Gateway

The gateway is the customer-facing commercial system.

Responsibilities:

- authenticate the customer
- create and persist the commercial session row
- resolve a worker and offering
- compute initial credit and topup credit in wei
- mint payment blobs via the sender-side payment daemon
- forward session-open and topup requests to the worker
- ingest worker usage and control-plane events
- update the customer billing ledger from accepted worker events
- surface low-balance, refilled, error, and ended states to the customer

The gateway is **not** the runtime-critical debit loop owner.

### Sender-side payment daemon

The sender-side payment daemon is co-located with the gateway.

Responsibilities:

- mint wire-format payment blobs
- encapsulate payee ticket-params lookup and ticket signing
- expose `CreatePayment(face_value, recipient, capability, offering)`

It does **not** own the long-lived session meter.

### Worker

The worker is the runtime owner of the streaming session.

Responsibilities:

- accept session-open and topup requests from the gateway
- validate incoming payment blobs via the co-located receiver daemon
- own the runtime session state machine
- debit usage locally on cadence
- check runway locally
- emit idempotent usage and control-plane events to the gateway
- close receiver-side payment state when the session ends

### Receiver-side payment daemon

The receiver-side payment daemon is co-located with the worker.

Responsibilities:

- validate incoming payments with `ProcessPayment`
- hold per-session balance keyed by `(sender, work_id)`
- debit balance with `DebitBalance`
- report headroom with `SufficientBalance`
- release per-session state with `CloseSession`

It is the authoritative runtime allowance store for the session.

## Core identifiers

Every conforming streaming workload must define and persist:

- `gateway_session_id`
- `worker_session_id`
- `work_id`
- `usage_seq`
- `capability`
- `offering`
- `recipient_eth_address`
- `sender_eth_address`

Recommended meaning:

- `gateway_session_id` = customer-facing commercial session identity
- `worker_session_id` = worker runtime identity
- `work_id` = receiver-daemon balance key for this live session

The mapping between them must be explicit and durable on both sides.

## Canonical lifecycle

### 1. Resolve

The gateway resolves a worker and offering.

Required resolved data:

- `worker_url`
- `recipient_eth_address`
- `capability`
- `offering`
- `price_per_work_unit_wei`
- `work_unit`

### 2. Open

The gateway computes an initial pre-credit amount in wei and calls:

- `CreatePayment(face_value, recipient, capability, offering)`

The gateway then calls the worker session-open endpoint with:

- `gateway_session_id`
- workload params
- control-plane params
- payment blob in the payment header

The worker:

- chooses or derives `work_id`
- calls `ProcessPayment(payment_bytes, work_id)`
- creates `worker_session_id`
- persists `gateway_session_id <-> worker_session_id <-> work_id`
- starts the runtime
- returns an accepted response

The open response must include at least:

- `gateway_session_id`
- `worker_session_id`
- `work_id`
- `sender_eth_address`
- `recipient_eth_address`
- any child bearer / session token needed for the long-lived control plane

Without that contract the gateway cannot safely top up, audit, or close
the session later.

### 3. Debit loop

The worker runs a local debit loop on a fixed cadence.

Recommended default:

- cadence: 5 seconds

At each tick the worker:

1. computes units consumed since the previous tick
2. increments `usage_seq`
3. calls `DebitBalance(sender, work_id, units)`
4. calls `SufficientBalance(sender, work_id, min_runway_units)`
5. writes the corresponding usage event to a durable local outbox
6. delivers or retries delivery of that event to the gateway

The worker must treat negative post-debit balance as fatal.

### 4. Watermark and grace

If `SufficientBalance` reports insufficient runway:

- worker enters low-balance state
- worker emits `session.balance.low`
- worker starts a grace timer

If balance recovers before grace expiry:

- worker clears low-balance state
- worker emits `session.balance.refilled`

If grace expires without recovery:

- worker emits terminal error and ended events
- worker stops the workload
- worker closes the payment session

Recommended defaults:

- min runway: 30 seconds
- grace: 60 seconds

### 5. Topup

Topup is customer-initiated at the gateway.

The gateway:

1. verifies the commercial session is still eligible for topup
2. computes topup `face_value`
3. calls `CreatePayment(face_value, recipient, capability, offering)`
4. forwards the resulting payment blob to the worker topup endpoint

The worker:

1. resolves the request to the existing live session
2. reuses the existing `work_id`
3. calls `ProcessPayment(payment_bytes, work_id)`
4. emits `session.balance.refilled` if the session exits low-balance state

Topup must credit the **same** receiver-side `work_id` already associated
with the live session.

### 6. Close

On graceful or fatal termination, the worker:

- stops the runtime
- emits terminal events
- calls `CloseSession(sender, work_id)`

The gateway:

- marks the commercial session ended
- finalizes customer billing state
- persists terminal reason and final usage

## Face-value sizing

This blueprint requires a single gateway-side pricing rule across
workloads:

`requested_spend_wei = target_credit_units * price_per_work_unit_wei`

Where:

- `target_credit_units` is the amount of future runway the gateway wants
  to buy up front or via topup
- `price_per_work_unit_wei` comes from the resolved offering

Workloads may choose different target runway policies, but they must do so
explicitly. For example:

- initial credit sized to 60 seconds
- topup credit sized to 60 seconds
- low-balance watermark at 30 seconds

In the current quote-free modules flow, that sender-side field is still
named `face_value`, but semantically it is a **requested spend / target
expected value** request. The receiver may answer with:

- a larger actual winning-ticket `FaceValue`, and
- a lower `win_prob`

so the ticket remains redeemable while the expected spend still matches
the gateway's requested amount.

If sender/payee ticket economics require a larger redeemable winning
ticket than the exact commercial target, that adjustment belongs inside
the payment-daemon ticket-params flow, not in workload-specific ad hoc
math. The workload-level invariant remains: customer credit and worker
debit are derived from the resolved `price_per_work_unit_wei` and the
consumed work units.

See [`payment-daemon-interactions.md`](./payment-daemon-interactions.md)
for the full sender/receiver economic model.

## Required worker-to-gateway event contract

Each streaming workload must define an idempotent usage event shape.

Recommended canonical event:

```json
{
  "type": "session.usage.tick",
  "gateway_session_id": "ses_123",
  "worker_session_id": "wrk_456",
  "work_id": "wid_789",
  "usage_seq": 12,
  "units": 5,
  "unit_type": "second",
  "remaining_runway_units": 25,
  "low_balance": true,
  "occurred_at": "2026-05-02T10:00:00Z"
}
```

Gateway requirements:

- persist idempotently by `(gateway_session_id, worker_session_id, usage_seq)`
- reject duplicates as no-ops
- bill customer usage only from accepted unique ticks

Worker requirements:

- `usage_seq` must be monotonic within a live session
- retries must preserve the same `usage_seq` and payload semantics
- delivered events must come from a durable outbox, not only process memory

## Reconciliation requirements

This is the part that turns the architecture into an implementation
blueprint.

The worker and gateway must behave as an **at-least-once** event pipeline:

- the worker may deliver a usage tick more than once
- the gateway must treat duplicates as no-ops
- the worker must be able to replay not-yet-acknowledged events after restart

Every session must also emit a terminal reconciliation record. At minimum,
the terminal event or terminal read-model must include:

- final `usage_seq`
- cumulative consumed units
- terminal reason
- final observed runway / balance state if available

This is what lets operators explain and reconcile:

- worker-enforced units
- gateway-billed units
- session close reason

Without this contract, “worker-side enforcement + gateway-side audit” is
not actually durable under crash/retry conditions.

## Separation of concerns

Streaming workloads require a strict split between:

- runtime allowance enforcement
- customer billing ledger

Runtime allowance enforcement:

- worker
- receiver-side payment daemon

Customer billing ledger:

- gateway DB
- gateway billing services

The gateway must **not** be required on the runtime-critical path of every
debit.

The worker must **not** be the sole keeper of the customer-commercial
ledger.

## Failure handling

### Sender-side mint failure

If `CreatePayment` fails:

- gateway must fail closed
- no workload request is sent without payment

### Worker cannot process payment

If `ProcessPayment` fails on open:

- worker rejects session-open
- gateway marks the commercial session failed

If `ProcessPayment` fails on topup:

- worker leaves the existing session running if it still has runway
- gateway surfaces topup failure to the customer

### Gateway temporarily unavailable during usage delivery

Worker behavior:

- local debit loop continues
- usage events are retried from durable storage
- retries preserve `usage_seq`

Gateway behavior:

- accepted events are idempotent
- duplicates are safe

### Receiver-side daemon unavailable mid-session

Worker behavior:

- treat as payment-path degradation
- retry on a bounded budget
- after grace, terminate the session if balance enforcement cannot continue
  safely

## Best-practice conformance rules

Any workload claiming conformance with the suite streaming pattern must
satisfy:

1. Payment credit is minted by sender-side `CreatePayment(face_value, recipient, capability, offering)`.
2. Runtime allowance is held receiver-side and credited by `ProcessPayment`.
3. Worker debits locally on cadence with `DebitBalance`.
4. Worker checks runway locally with `SufficientBalance`.
5. Topup credits the same live `work_id`.
6. Worker emits idempotent usage ticks to the gateway.
7. Worker persists unacknowledged usage ticks durably for replay.
8. Gateway persists customer billing from accepted usage ticks.
9. Worker and gateway both persist the correlation identifiers.
10. The debit loop does not require a worker-to-gateway round trip to continue safely.
11. Terminal session state closes receiver-side payment state exactly once.
12. Terminal session state includes enough data for worker/gateway reconciliation.

## Recommended logical API surface

This doc does not mandate exact paths, but recommends these logical
operations:

Gateway to worker:

- session open
- session topup
- session end

Worker to gateway:

- session ready
- session usage tick
- session balance low
- session balance refilled
- session error
- session ended

Worker to receiver-side daemon:

- `ProcessPayment`
- `DebitBalance`
- `SufficientBalance`
- `CloseSession`

Gateway to sender-side daemon:

- `CreatePayment`

## Relationship to existing suite workloads

- `livepeer-openai-gateway` remains the canonical **request/response**
  pattern.
- VTuber, live video, and future realtime workloads should use this
  streaming pattern.
- Older docs that mention `GET /quote`, `StartSession`, or custom
  `OpenStreamingSession` / `TopUpStreamingSession` session RPCs are
  historical and should be treated as superseded by this document.
