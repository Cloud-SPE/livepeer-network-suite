---
title: Payment-daemon interactions
status: accepted
last-reviewed: 2026-05-02
---

# Payment-daemon interactions

Cross-workload guide to how the suite uses `livepeer-payment-daemon` and
`service-registry-daemon` together. This is the doc new workload authors
should read before inventing any payment flow of their own.

The goal is to make three things explicit:

- what the gateway sends
- what the worker / receiver actually validates and credits
- which config knobs affect retail price vs ticket redeemability

## Scope

This doc applies to both suite interaction models:

- **request/response** workloads like `livepeer-openai-gateway`
- **streaming** workloads using the worker-metered / gateway-ledger split
  defined in
  [streaming-workload-pattern.md](./streaming-workload-pattern.md)

The payment primitives are shared. What changes between the two models is
who owns the long-lived session meter and when customer-ledger commits
happen.

## The two daemon roles

### Sender mode

The gateway runs `payment-daemon` in `--mode=sender`.

Its job is to:

- accept `CreatePayment(face_value, recipient, capability, offering)`
- resolve the recipient to a worker URL via the local
  `service-registry-daemon`
- fetch canonical ticket params from the worker-side
  `/v1/payment/ticket-params` path
- sign a wire-format `Payment` blob

The sender daemon is not a pricing engine. It does not decide retail
price. It turns a gateway pricing decision into a valid ticket.

### Receiver mode

The worker runs `payment-daemon` in `--mode=receiver`.

Its job is to:

- publish capability / offering prices from `worker.yaml`
- synthesize truthful ticket params for the incoming payment request
- validate `Payment` blobs with `ProcessPayment`
- credit and debit per-session balance
- redeem winning tickets on-chain

The receiver daemon is both:

- the cryptographic authority for payee-issued ticket params, and
- the runtime allowance store for receiver-side balances

## End-to-end quote-free flow

This is the canonical v3 flow used by suite workloads.

### 1. Resolve route and retail price

The gateway resolves through `service-registry-daemon`:

- worker URL
- recipient ETH address
- capability
- offering
- `price_per_work_unit_wei`
- `work_unit`

The resolver result tells the gateway **what the worker advertises for
retail charging**.

### 2. Compute the requested spend

The gateway computes a wei-denominated request amount from the resolved
price:

`requested_face_value_wei = target_units * price_per_work_unit_wei`

For request/response workloads, `target_units` is usually the gateway's
best estimate of the single request cost.

For streaming workloads, `target_units` is the amount of runway the
gateway wants to pre-credit or top up.

Important: in the current quote-free protocol, the sender-side field is
still named `face_value`, but semantically it is the gateway's **target
spend request** or **requested expected value**, not necessarily the final
winning-ticket face value the receiver will choose.

## 3. CreatePayment does not mean “final face value is fixed”

The gateway calls:

- `CreatePayment(face_value, recipient, capability, offering)`

The sender daemon then:

1. resolves the recipient to a worker URL via the local resolver
2. calls the worker-side ticket-params endpoint
3. receives receiver-chosen `TicketParams`
4. signs a `Payment`

This is why the service registry matters to payment correctness: sender
mode needs a route to the worker so it can fetch canonical ticket params
for that exact payee.

## 4. Requested spend vs actual winning-ticket face value

These terms are not interchangeable:

| Term | Chosen by | Meaning |
|---|---|---|
| `price_per_work_unit_wei` | worker config (`worker.yaml`) | published retail price for one work unit |
| requested `face_value` in `CreatePayment(...)` | gateway | target spend / requested EV for this payment |
| actual ticket `FaceValue` inside returned `TicketParams` | receiver daemon | winning-ticket size chosen so redemption remains truthful |
| `win_prob` | receiver daemon | probability chosen so `FaceValue × win_prob` matches the requested spend |
| credited EV from `ProcessPayment` | receiver daemon | expected value actually credited to the `(sender, work_id)` balance |

The recent modules change is the load-bearing semantic shift:

- the gateway may request a small spend amount
- the receiver may return a **larger** winning-ticket face value
- the receiver lowers `win_prob` so expected spend still matches the
  gateway's request

That lets small retail requests succeed **without lying** about redemption
economics.

## Why this exists

An individually redeemable winning ticket must still clear runtime
economics:

- receiver EV target
- redemption gas assumptions
- gas price multiplier
- sender `MaxFloat` / reserve availability

So the worker may publish a correct retail price and still refuse some
requests if the sender cannot support the redeemable winning-ticket size
the receiver needs.

## What changes retail price vs what changes acceptance floor

This is the most important operator distinction.

### Retail price

Retail charge comes from `worker.yaml` offerings:

- `capability`
- `work_unit`
- `offerings[].id`
- `offerings[].price_per_work_unit_wei`

Changing these changes what gateways should charge for work.

### Acceptance floor / redeemability

Ticket acceptability comes from receiver runtime economics, especially:

- `--receiver-ev`
- `--redeem-gas`
- gas price and `--gas-price-multiplier-pct`
- `--receiver-tx-cost-multiplier`
- sender reserve / `MaxFloat`

Changing these affects whether a small requested spend can be turned into
a truthful redeemable ticket.

This is why “make the YAML price lower” is usually the wrong fix when
small requests fail. Lowering published price changes customer billing;
it does not necessarily make the resulting ticket redeemable.

## The sender/receiver success path

### Gateway / sender side

For a workload author, the required sequence is:

1. resolve worker + offering
2. compute requested spend from resolved price
3. call `CreatePayment(face_value, recipient, capability, offering)`
4. attach returned `payment_bytes` to the worker request
5. fail closed if the daemon cannot mint payment

### Worker / receiver side

For a worker author, the required sequence is:

1. accept the payment blob
2. call `ProcessPayment(payment_bytes, work_id)`
3. persist the returned sender identity and the chosen `work_id`
4. debit usage with `DebitBalance(sender, work_id, units)`
5. check watermark / runway with `SufficientBalance(...)`
6. close receiver-side session state with `CloseSession(sender, work_id)`

## Request/response workloads

For request/response workloads like OpenAI:

- one request normally carries one payment envelope
- `ProcessPayment` validates and credits EV
- the worker consumes the request
- the gateway settles its customer ledger after the request returns

The worker may over-debit or under-debit relative to the gateway's
estimate depending on the workload's accounting model, but the network
payment path is still built around `CreatePayment` → `ProcessPayment`.

## Streaming workloads

For streaming workloads:

- the gateway uses the same `CreatePayment` primitive
- the worker uses `ProcessPayment` to seed or top up the live balance
- the worker owns the debit cadence with `DebitBalance`
- the gateway does not sit on the hot path of every balance check

See [streaming-workload-pattern.md](./streaming-workload-pattern.md) for
the full lifecycle.

## Service-registry interaction

`service-registry-daemon` and `payment-daemon` are coupled at one crucial
point:

- the resolver is the sender daemon's route-to-worker source of truth

The gateway does not hand the sender daemon a worker URL directly in the
normal production path. It hands over:

- recipient ETH address
- capability
- offering

Sender mode then uses the local resolver to map recipient → worker URL and
fetch `/v1/payment/ticket-params` there.

Implications:

- route/offering correctness matters to payment correctness
- recipient address drift breaks payment minting even if HTTP routing still
  looks superficially healthy
- service-registry pricing and payment-daemon pricing assumptions must stay
  aligned

## Hot/cold identity split

Receiver-side redemption commonly uses:

- hot signer wallet for gas and tx signing
- cold orchestrator address as the ticket recipient

This is safe because TicketBroker pays `faceValue` to `ticket.Recipient`
and does not require the recipient itself to sign redemption.

Suite docs should therefore keep these roles distinct:

- **signer wallet** = operational key the receiver daemon uses
- **recipient / orch identity** = on-chain identity that receives payouts

## Workload-author checklist

A new workload is not ready until its docs and implementation answer all
of these clearly:

1. What capability string does it advertise?
2. What offering string does it route on?
3. What `work_unit` does it meter in?
4. How does the gateway compute requested spend from that unit price?
5. Which side owns the live meter: gateway or worker?
6. What `work_id` is used for receiver-side balance correlation?
7. How does topup reuse the same `work_id`, if the workload streams?
8. What operator knobs affect retail pricing?
9. What operator knobs affect redeemability / minimum truthful ticket size?
10. What should the operator inspect first when `CreatePayment` or `ProcessPayment` fails?

## Practical debugging map

If the worker advertises the right price but minting still fails, inspect:

1. `worker.yaml` published `price_per_work_unit_wei`
2. gateway-computed requested spend
3. receiver runtime economics:
   `--receiver-ev`, `--redeem-gas`, `--receiver-tx-cost-multiplier`,
   gas-price multiplier
4. sender reserve / `MaxFloat`
5. resolver route correctness for the target recipient
6. worker `/v1/payment/ticket-params` reachability and auth

If the ticket mints but runtime charging behaves incorrectly, inspect:

1. worker `ProcessPayment(...)` result and credited EV
2. `work_id` reuse across session open and topup
3. `DebitBalance(...)` units emitted by the workload
4. `SufficientBalance(...)` watermark policy
5. gateway-side customer-ledger reconciliation

## Relationship to modules docs

This is a suite-level translation layer, not the authoritative daemon
operator reference.

For the primary source material, see:

- `livepeer-modules/payment-daemon/docs/operations/running-the-daemon.md`
- `livepeer-modules/payment-daemon/docs/design-docs/payment-daemon-config.md`
- `livepeer-modules/payment-daemon/proto/livepeer/payments/v1/*.proto`

