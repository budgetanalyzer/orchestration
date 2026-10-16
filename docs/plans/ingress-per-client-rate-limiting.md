# Per-Client Rate Limiting at Istio Ingress

Replace the shared auth-ingress bucket described in the
[bug report](../../../budget-analyzer-api-tests/docs/bugs/auth-ingress-shared-rate-limit-bucket.md)
with Envoy local rate limiting at Istio ingress for both auth and API traffic.
Keep four independently configured policies: login initiation, login completion,
session operations, and API requests. Remove NGINX's blanket API limiter after
the ingress replacement is verified.

The accepted design uses per-client, per-policy counters local to each ingress
Envoy instance. It does not promise a shared allowance across replicas or across
proxy restarts. Document a shared rate-limit service as a future option when
consistent enforcement across replicas becomes a requirement; do not implement
that service, new Redis state, per-user quotas, or a generic policy framework.

Keep the work proportional: reuse the existing identity probes and browser
tooling, add focused behavioral assertions, and avoid a new load-testing system
or exhaustive endpoint-by-endpoint burst tests. Numerical limits must follow an
explicit browser-concurrency assumption and backend cost, not test-suite size.

Execution follows each phase's repository instructions. Orchestration phases
may read sibling sources but must not edit sibling service or harness code.
Phase 3 switches to the API-test repository for its own changes. Before live
orchestration work run
`./scripts/bootstrap/check-agent-vm-prerequisites.sh --native-runtime`; use the
repository's exact local Kind guard before every mutation. Public browser tests
target only `https://app.budgetanalyzer.localhost` with normal TLS verification.
Missing prerequisites stop the affected phase. No production access, TLS writes,
Git writes, security bypasses, or edits to archived documents or ADRs.

## Phase 1: Implement and document the ingress policy contract

### Workspace

.

### Goal

Provide a reviewable local/production configuration with independent per-client
policies and a documented capacity model.

### Scope

Ingress EnvoyFilter, production overlay, focused configuration checks, and the
canonical security documentation. Keep NGINX's existing API limit until Phase 2
proves the ingress replacement; document this temporary overlap explicitly.

### Non-goals

Routing changes, service logic, distributed enforcement, additional infrastructure,
separate budgets for every session endpoint, and unrequested backend quotas.

### Required context

- `AGENTS.md`, `docs/OWNERSHIP.md`, `docs/architecture/security-architecture.md`
- `docs/architecture/session-edge-authorization-pattern.md`
- `docs/architecture/autonomous-ai-execution.md`
- `kubernetes/istio/ingress-rate-limit.yaml`, `kubernetes/istio/ext-authz-policy.yaml`
- `kubernetes/gateway/auth-httproute.yaml`, `kubernetes/gateway/api-httproute.yaml`
- `kubernetes/production/istio-ingress-policies/kustomization.yaml`
- `nginx/nginx.k8s.conf`, `nginx/nginx.production.k8s.conf`
- `scripts/smoketest/verify-api-rate-limit-identity.sh`
- `../budget-analyzer-web/src/hooks/useSessionHeartbeat.ts`
- `../budget-analyzer-api-tests/docs/bugs/auth-ingress-shared-rate-limit-bucket.md`

### Execution steps

1. Confirm the checked-in Istio/Envoy version and supported local-rate-limit
   fields before choosing configuration syntax. Inspect local and production
   client-address propagation, including the production source-preserving NLB
   path. Use the ingress-established client address; do not trust raw incoming
   forwarding headers or use cookies, query strings, or claimed identity as keys.
2. Add a rate-limiting section to `docs/architecture/security-architecture.md`
   as the canonical owner and register that detail in `docs/OWNERSHIP.md`.
   Define four stable policy names and their routing boundaries:

   | Policy | Intended operations |
   | --- | --- |
   | Login initiation | `/oauth2/authorization/idp` |
   | Login completion | `/login/oauth2/code/idp` |
   | Session operations | `/auth/v1/user`, `/auth/v1/session`, `/logout` |
   | API | `/api/*` |

   Specify bounded fallback handling for unknown paths and unsupported methods
   within the existing auth/API families, without creating more policy classes
   or changing the service's response contract. Bare `/login` stays a frontend
   page outside the OAuth-initiation budget. Query strings must not create new
   buckets. Match path boundaries so similarly named frontend routes are not
   accidentally classified; document the treatment of bare family roots.
3. Select and document each policy's sustained rate, burst capacity, and refill
   interval. Keep the current API sustained rate of 10 requests/second as the
   starting point and explicitly account for differences between NGINX's
   `burst=50` behavior and Envoy token capacity. Size session traffic from the
   actual frontend behavior, including its current two-minute heartbeat default,
   initial requests, multiple tabs, and a stated shared-IP concurrency assumption.
   Give callback completion independent burst headroom. Prefer incremental
   refills over replenishing a whole minute's allowance at once.
4. Replace the constant auth descriptor with per-policy/client descriptors and
   enforce them before `envoy.filters.http.ext_authz`. Preserve authorization
   policy and route ownership. Use the simplest configuration supported by the
   pinned version; do not assume insertion before the router establishes the
   required order.
5. Remove incidental global coupling: audit default-token-bucket consumption,
   unmatched requests, virtual-host scope, and overlapping descriptor matches.
   Do not retain the current 10,000-token shared ceiling as an undocumented
   fallback. Configure bounded dynamic-descriptor storage deliberately and
   document eviction/restart limitations and shared-NAT behavior. Do not add an
   aggregate overload quota without a separate capacity requirement.
6. Provide a non-secret rejection marker identifying the policy and usable
   per-policy accepted/rejected metrics. Add accurate retry guidance only using
   supported semantics; do not invent a fixed reset time or require an Envoy
   upgrade solely for a convenience header. Avoid per-client metric labels and
   logging credentials, cookies, authorization codes, or OAuth state.
7. Update the production authority patch and any resource-name references.
   Keep the same policy semantics in local and production render paths.
8. Document the current per-instance enforcement and its limits alongside this
   future option: Envoy's global rate-limit filter plus a shared rate-limit
   service/storage when a consistent allowance across gateway replicas is
   required. Note the additional latency, availability dependency, and explicit
   failure-policy decision. This is an evolution path, not unfinished work.

### Implementation notes

Rate limiting protects capacity; it does not authenticate a callback or replace
OAuth state validation. Separate initiation/completion allowances prevent one
class consuming the other's budget but do not guarantee availability against a
caller attacking the callback allowance itself. Session operations intentionally
share one budget; no claim of independent logout availability under session-budget
exhaustion should appear in documentation.

Keep detailed numbers in the manifest and canonical security section. Summaries
and future harness guidance should link there rather than copy the full policy.

### Validation

- Render `kubectl kustomize kubernetes/production/istio-ingress-policies` offline
  and inspect the local manifest and production output structurally. Check all
  four policies, varying client identity, authorities, capacity settings,
  markers, default-bucket behavior, and filter insertion target.
- Exercise a small matcher table covering each policy, query variants, unknown
  family paths, unsupported methods, `/login`, and lookalike paths. Assertions
  must check behavior/structure, not merely the presence of strings in YAML.
- Confirm compatibility with the pinned Envoy version. Live acceptance and
  actual filter order are Phase 2 gates; rendering alone does not prove them.
- Run `bash -n` and `shellcheck` on every shell script changed in this phase.

### Completion criteria

All four policies are defined in local and production configuration, numerical
choices and limitations are documented, and focused offline checks pass. NGINX's
temporary overlap is explicit; live isolation and cutover remain Phase 2 work.

## Phase 2: Prove isolation and remove the duplicate API limiter

### Workspace

.

### Goal

Make ingress the sole owner of general API/auth rate limiting, backed by focused
proof that excessive traffic does not consume unrelated capacity.

### Scope

Local runtime verification, existing smoke-test integration, NGINX cutover in
both configurations, and affected orchestration documentation.

### Non-goals

Production execution, sustained stress testing, a new browser-login framework,
per-endpoint test duplication, dashboards, and harness-code changes.

### Required context

- `AGENTS.md`, `docs/architecture/security-architecture.md`
- `docs/architecture/autonomous-ai-execution.md`, `docs/development/getting-started.md`
- `scripts/README.md`, `scripts/lib/local-kubernetes-target.sh`
- `scripts/smoketest/verify-api-rate-limit-identity.sh`
- `scripts/smoketest/verify-istio-ingress.sh`
- `scripts/smoketest/verify-edge-browser-hardening.sh`
- `docs/architecture/session-edge-authorization-pattern.md`, `nginx/README.md`
- `docs/agents-md-checkstyle.md`

### Execution steps

1. Run native prerequisites, reconcile through the supported local runtime,
   and confirm Envoy accepts the configuration. Inspect the live listener/filter
   chain and route configuration to prove limiter-before-`ext_authz` order and
   the intended client identity. Do not infer identity from the apparent source
   of requests sent through a host tunnel or port-forward.
2. Extend the existing two-client identity verifier into one focused ingress
   rate-limit verifier, renaming it if appropriate and updating callers. Reuse
   its controlled clients, TLS setup, cleanup, and bounded bursts. Apply the
   exact local target guard before setup and cleanup mutations. Retain NGINX
   forwarded-identity coverage where it serves an independent contract.
3. Add a small behavioral matrix against the real ingress configuration:

   | Scenario | Required result |
   | --- | --- |
   | Client A exhausts login initiation | Policy-marked `429`; client B can still initiate login through the same Envoy instance |
   | A rotates forged forwarding headers | A remains in its exhausted bucket |
   | A exhausts initiation | A's callback and normal session operations remain independently available |
   | A exhausts API allowance | API marker identifies ingress rejection; B's API allowance and A's session allowance remain usable |
   | Ordinary session workload | User reads, heartbeats, and logout succeed within the documented concurrency/burst assumptions |
   | Callback or session allowance exhausted | Correct policy marker; unrelated policy remains usable |
   | Refill after exhaustion | Requests recover according to the configured refill behavior |

   Use representative routes rather than bursting every endpoint. Establish
   baseline responses first, distinguish expected service errors from rate-limit
   rejection, and keep refill waits bounded and derived from the actual policy.
4. Prove that ingress-rejected API requests do not invoke `ext_authz`, using
   live filter order plus bounded counter/log evidence during the controlled
   probe. Verify the policy also covers unauthenticated API abuse, which the old
   post-authorization NGINX limiter could not protect against.
5. Include one bounded browser-assisted proof with a disposable local identity:
   start a real OAuth login, exhaust that same client's initiation allowance
   without following the extra redirects to the identity provider, then complete
   the original callback and confirm the authenticated user response. Use the
   existing browser tooling and public login flow. An invalid-state callback that
   merely avoids `429` is a useful routing check but is not this completion proof.
   Keep raw OAuth state, codes, and cookies out of evidence. Do not add a second
   reusable login framework or change sibling code to run this proof.
6. Verify replica semantics with a bounded two-ingress-instance local check:
   preserve the client identity and select each instance deterministically,
   confirming that exhaustion on one does not consume the other's allowance.
   Do not rely on random load balancing. Restore the repo-defined replica count
   and remove temporary probe resources even on failure. This proves the stated
   per-instance limitation, not a cluster-wide quota.
7. Once ingress enforcement passes, remove blanket API `limit_req` directives
   and the unused zone from both NGINX configurations. Preserve routing,
   authorization, real-client forwarding, and unrelated headers. Do not add
   replacement backend-specific limits without a demonstrated requirement.
8. Replace the old auth checks that equate any burst `429` with success. Have the
   existing ingress/browser-hardening entry points use the focused verifier
   without duplicating bursts and sleeps. Include focused structural checks for
   local/production policy parity and absence of the removed blanket NGINX limit.
9. Update the canonical security section first, then affected summaries and
   links in `AGENTS.md`, `nginx/README.md`, the session-edge document, system
   overview, port reference, local-environment guide, Tilt runbook, script
   catalog, and production documentation as needed. Remove temporary overlap
   wording. Follow AGENTS checkstyle and leave ADRs/archives untouched. Record a
   concise, non-secret verification result in the affected operational docs;
   keep detailed generated output in ignored local artifacts.

### Implementation notes

Keep deliberate exhaustion in this controlled orchestration verifier. Use fresh
probe clients and bounded request counts to avoid interference with normal local
development. The browser completion probe must preserve the original login's
cookies/state; use a separate cookie jar for the extra initiation requests from
the same client IP so the test does not invalidate its own OAuth transaction.

### Validation

- Run the focused ingress verifier against the final configuration after NGINX
  removal. Confirm it fails on wrong client identity or cross-policy coupling,
  rather than passing solely because some requests receive `429`.
- Validate both NGINX configurations using the repository's supported config
  validation/render paths; run `nginx -t` in the local gateway for the active
  configuration. Render the production ingress overlay without deployment.
- Run the affected ingress/browser-hardening regression entry points once after
  final changes; avoid rerunning their transitive checks separately.
- Run `bash -n` and `shellcheck` on every modified/new shell script.
- Confirm temporary clients, policies, and replica changes are cleaned up.

### Completion criteria

The final local deployment enforces per-client policies before authorization,
demonstrates client and policy isolation including a real callback completion,
and exposes useful policy diagnostics. Both NGINX configurations have relinquished
blanket limiting. Replica behavior is verified and documentation describes the
actual final architecture and future shared-service option.

## Phase 3: Align public harness pacing and close the regression

### Workspace

../budget-analyzer-api-tests

### Goal

Remove the harness's compatibility model of the defective shared bucket and
verify normal public browser/API behavior against the corrected deployment.

### Scope

Harness pacing, existing browser integration, focused unit coverage, current
harness guidance, and the bug report. The deployed Phase 2 contract is prerequisite.

### Non-goals

Orchestration/service edits, direct Redis or Kubernetes access, deliberate abuse
tests in the normal black-box suite, per-test sleeps, automatic `429` retries,
identity spoofing, and environment-specific exceptions.

### Required context

- `AGENTS.md`, `README.md`, `pyproject.toml`
- `docs/bugs/auth-ingress-shared-rate-limit-bucket.md`
- `src/api_tests/client.py`, `src/api_tests/browser_login.py`
- `tests/unit/test_client.py`, relevant existing browser/auth unit tests
- `tests/api/session_gateway/`, `tests/api/auth/`
- `../orchestration/docs/architecture/security-architecture.md`
- `../orchestration/kubernetes/istio/ingress-rate-limit.yaml`
- `../orchestration/docs/agents-md-checkstyle.md`

### Execution steps

1. Confirm the documented Phase 2 contract and the exact local environment/TLS
   prerequisites. Read the final policy values rather than assuming the old
   NGINX or auth budgets. Do not change deployment from this workspace.
2. Replace the single auth-sensitive pacing bucket with a small explicit
   classification matching the four public policies. Reuse existing pacing
   primitives or simplify to conservative fixed-rate pacing below each sustained
   allowance; do not simulate Envoy internals or build a generic quota engine.
   All primary, secondary, unauthenticated, and same-origin browser requests in
   one process must share the applicable per-client pacer. Do not partition by
   account or cookie, and do not throttle identity-provider origins as app traffic.
3. Remove obsolete minute-long first-use waits, callback-timeout padding, and
   constants introduced solely for the old ten-token policy. Preserve legitimate
   browser timeouts and diagnostics. Document that independent processes/external
   callers sharing an IP are not coordinated by an in-process pacer.
4. Add focused fake-clock tests for policy classification, sharing across clients
   and browser requests, and independence between initiation, callback, session,
   and API pacing. Cover query variants and `/login` without copying every route
   test or implementing a second rate limiter in the test code.
5. Update active `AGENTS.md`/README guidance and any current pacing-specific docs
   to link to the orchestration contract. The old requirements to preserve the
   shared ten-token bucket are superseded by this fix. Keep public-lane and TLS
   constraints intact; use the AGENTS authoring standard.
6. Run the focused public Session Gateway suite twice consecutively, including
   primary/secondary authentication, normal OAuth lifecycle, session/user reads,
   and logout, without an artificial between-run cooldown. Run a representative
   authenticated API regression in the same workflow. Any unexpected `429`
   remains a failure to investigate, not an excuse for retries or larger limits.
7. Update the bug report with the resolution, links to canonical policy and
   orchestration isolation proof, and redacted validation results. Preserve the
   original defect evidence and explain the accepted local/per-instance semantics.
   Close the report only when all required regression checks pass.

### Implementation notes

The harness demonstrates normal public behavior; the orchestration verifier owns
intentional exhaustion and replica selection. Keep this separation so ordinary
test runs cannot accidentally reproduce the original availability incident.
Do not edit this execution plan from the sibling workspace or during an active
AI Session Handler invocation; use the owning repository's result artifacts.

### Validation

- Run the repository's unit suite, Ruff format/lint, and mypy gates for the change.
- Run normal API collection/coverage checks affected by any test changes.
- Use `./run-tests` with the existing Session Gateway and auth selectors for the
  consecutive public runs; record the exact selection and results. Do not count
  skipped authentication or lifecycle scenarios as successful coverage.
- Confirm the representative API requests succeed under the shared pacing path
  and no obsolete `auth-sensitive` bucket assumptions remain in active guidance.

### Completion criteria

The public harness matches the corrected policy, focused quality gates pass,
both consecutive browser/session runs and the API regression pass without
unexpected `429`, and the bug report records the verified resolution. No harness
workaround retains the original shared-bucket contract.
