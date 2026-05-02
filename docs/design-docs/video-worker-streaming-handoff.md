---
title: Video worker streaming-pattern handoff
status: drafted
last-reviewed: 2026-05-02
---

# Video worker streaming-pattern handoff

This note is for the `video-worker-node` maintainers. The suite-level
streaming blueprint now lives in
[`streaming-workload-pattern.md`](./streaming-workload-pattern.md) and is
the canonical cross-workload pattern for long-lived sessions.

## Why this handoff exists

The current `video-worker-node` local design doc
`docs/design-docs/payment-integration.md` still describes an older
streaming-session model built around:

- `OpenStreamingSession`
- `DebitStreamingSession`
- `TopUpStreamingSession`
- `CloseStreamingSession`

That model no longer matches the suite-level canonical story.

## Requested doc update

Please update `video-worker-node/docs/design-docs/payment-integration.md`
so its live-session section aligns with the suite-level pattern:

- gateway resolves worker + offering
- gateway mints credit with
  `CreatePayment(face_value, recipient, capability, offering)`
- worker credits receiver-side balance with `ProcessPayment(payment_bytes, work_id)`
- worker debits locally with `DebitBalance(sender, work_id, units)`
- worker checks runway with
  `SufficientBalance(sender, work_id, min_runway_units)`
- topups credit the same live `work_id`
- worker emits idempotent usage events to the gateway
- gateway updates the customer ledger from accepted events
- worker closes receiver-side state with `CloseSession(sender, work_id)`

## Important nuance

This handoff is about **documentation alignment**, not an assertion that
the `video-worker-node` implementation is already wrong. The immediate
problem is that the local doc teaches a different conceptual API than the
suite-level blueprint for new streaming workloads.

