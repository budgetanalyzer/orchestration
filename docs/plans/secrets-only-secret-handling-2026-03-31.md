# Secrets-Only Secret Handling Plan

Date: 2026-03-31

## Goal

Make the orchestration repo treat only actual secret material as Kubernetes
`Secret` data.

After this work:

1. non-secret runtime settings live in checked-in manifests or explicit config
   render paths
2. Kubernetes `Secret` objects contain only values that are actually sensitive
3. `.env.example` remains a local input file, but values sourced from `.env`
   are classified correctly before they are rendered into Kubernetes objects
4. docs and verification make this boundary explicit so it does not drift again

## Non-Goals

- Do not redesign the full production secret-management system in this plan.
- Do not remove legitimate local secret generation for Kind/Tilt.
- Do not treat "came from `.env`" as equivalent to "must be a Kubernetes
  `Secret`".

## Current State

The repo currently mixes secret and non-secret values in at least one clear
place:

- [`Tiltfile`](/workspace/orchestration/Tiltfile#L312) renders
  `Secret/auth0-credentials` with:
  - `AUTH0_CLIENT_SECRET` — secret
  - `AUTH0_CLIENT_ID` — non-secret config
  - `AUTH0_ISSUER_URI` — non-secret config
  - `IDP_AUDIENCE` — non-secret config
  - `IDP_LOGOUT_RETURN_TO` — non-secret config

This happened because the local `.env` path became the producer for both
configuration and secrets, and the Kubernetes rendering boundary was not kept
clean.

We already removed one instance of this drift:

- [`ConfigMap/session-gateway-config`](/workspace/orchestration/kubernetes/services/session-gateway/configmap.yaml#L1)
  now carries `SESSION_TTL_SECONDS`, which is ordinary runtime config rather
  than a secret.

## Classification Rules

Use these rules consistently:

- Secret: passwords, client secrets, API keys, tokens, private keys, and any
  value whose exposure would meaningfully compromise access
- Non-secret config: hostnames, ports, usernames, issuer URIs, audiences,
  logout return URLs, feature flags, TTLs, cookie names, and protocol settings
- Mixed bundles are not allowed just for convenience. Split them.

Concrete interpretation for current Auth0 inputs:

- `AUTH0_CLIENT_SECRET` stays secret
- `AUTH0_CLIENT_ID` moves to non-secret config
- `AUTH0_ISSUER_URI` moves to non-secret config
- `IDP_AUDIENCE` moves to non-secret config
- `IDP_LOGOUT_RETURN_TO` moves to non-secret config

## Target Shape

Session Gateway should consume two different sources:

1. a secret source for actual secrets only
2. a config source for non-secret IDP/runtime settings

Recommended target:

- keep `Secret/auth0-credentials`, but reduce it to the true secret payload
  only
- add a checked-in Session Gateway config object for non-secret IDP settings
- keep the Auth0 Istio egress render/apply step driven by the same
  `AUTH0_ISSUER_URI` value, but stop storing that value in a Kubernetes
  `Secret`

This preserves the existing "one issuer source of truth" contract without
misclassifying the value.

## Work Plan

### 1. Inventory every rendered secret payload

Audit all `create_secret(...)` calls and raw Secret YAML generation in
[`Tiltfile`](/workspace/orchestration/Tiltfile) and checked-in manifests.

For each key, classify it as:

- secret
- non-secret config
- derived mixed payload that must be split

Primary files:

- [`Tiltfile`](/workspace/orchestration/Tiltfile)
- [`kubernetes/`](/workspace/orchestration/kubernetes)

Required outcome:

- there is a checked-in inventory of which current secret keys are valid and
  which are misclassified

### 2. Split Session Gateway Auth0 config from secret material

Refactor the current `auth0-credentials` bundle so Session Gateway no longer
reads non-secret Auth0/IDP values from a Kubernetes `Secret`.

Files expected to change:

- [`Tiltfile`](/workspace/orchestration/Tiltfile)
- [`kubernetes/services/session-gateway/deployment.yaml`](/workspace/orchestration/kubernetes/services/session-gateway/deployment.yaml)
- [`kubernetes/services/session-gateway/configmap.yaml`](/workspace/orchestration/kubernetes/services/session-gateway/configmap.yaml)
- related docs that currently describe `auth0-credentials`

Required outcome:

- `AUTH0_CLIENT_SECRET` remains secret-backed
- `AUTH0_CLIENT_ID`, `AUTH0_ISSUER_URI`, `IDP_AUDIENCE`, and
  `IDP_LOGOUT_RETURN_TO` move to config, not secret data

### 3. Audit service credential bundles for other non-secret fields

The repo also stores non-secret helpers inside credential secrets for
convenience, such as hosts, ports, usernames, virtual hosts, and JDBC URLs.
That may be acceptable operationally in a few places, but it violates the
stated boundary if the goal is "only treat secrets as secrets."

Audit examples:

- PostgreSQL per-service secrets containing `username` and `url`
- Redis per-service secrets containing `host`, `port`, and `username`
- RabbitMQ per-service secrets containing `host`, `amqp-port`, `username`, and
  `virtual-host`

Decision required for this phase:

- either split these into config plus secret consistently
- or explicitly document a narrower rule such as "credential bundles may
  include connection metadata"

Recommendation:

- split them. The stricter rule is clearer and easier to enforce.

### 4. Align `.env.example` with the rendering boundary

Keep `.env.example` as the developer-facing input contract, but stop implying
that every value listed there becomes a secret.

Required outcomes:

- comments distinguish secret inputs from ordinary config inputs
- non-secret config is documented as config even if local Tilt reads it from
  `.env`
- setup docs stop teaching secret terminology for non-secret settings

Primary files:

- [`.env.example`](/workspace/orchestration/.env.example)
- [`README.md`](/workspace/orchestration/README.md)
- [`docs/development/getting-started.md`](/workspace/orchestration/docs/development/getting-started.md)
- [`docs/development/local-environment.md`](/workspace/orchestration/docs/development/local-environment.md)
- [`docs/setup/auth0-setup.md`](/workspace/orchestration/docs/setup/auth0-setup.md)
- [`AGENTS.md`](/workspace/orchestration/AGENTS.md)

### 5. Add verification so this does not regress

Add a lightweight static check that fails if clearly non-secret keys are added
to Kubernetes `Secret` payloads without an explicit exception.

Initial minimum guardrails:

- flag `AUTH0_ISSUER_URI`, `IDP_AUDIENCE`, `IDP_LOGOUT_RETURN_TO`,
  `SESSION_TTL_SECONDS`, and similar runtime knobs if they appear in a rendered
  secret payload
- require any intentional mixed bundle to be documented with a rationale if we
  keep one temporarily

Possible implementation points:

- `scripts/dev/`
- existing static verification entrypoints

Required outcome:

- future convenience-driven secret bundling is caught in review and local
  verification

## Verification

Before closing this plan:

1. `kubectl apply --dry-run=client` succeeds for all changed manifests
2. local Tilt still renders and applies the required secrets/config objects
3. Session Gateway still reads Auth0 config correctly after the split
4. the Auth0 egress render/apply path still uses the same `AUTH0_ISSUER_URI`
   source of truth
5. docs describe the secret/config split accurately

## Recommended Order

1. Inventory current secret payloads.
2. Split Session Gateway Auth0 config from `auth0-credentials`.
3. Decide whether service connection bundles will be fully split or explicitly
   grandfathered.
4. Update docs and `.env.example`.
5. Add static verification.

## Recommendation

Do not stop at the obvious Auth0 cleanup.

If the repo’s rule is "only treat secrets as secrets," then hostnames, ports,
usernames, audiences, issuer URIs, and return URLs should not remain inside
credential secrets anywhere in the tree just because that wiring is convenient.
