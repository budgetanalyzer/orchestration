# Dependency Update Review Baseline

**Date:** 2026-09-06  
**Status:** Point-in-time research  
**Purpose:** Preserve the manually researched dependency recommendations so
they can be compared with repository-owned Dependabot and Renovate findings
after that automation is enabled.

This is not a version contract or an implementation plan. Upstream current
versions will continue to change. Checked-in build files, manifests, version
catalogs, and `deploy/scripts/lib/version-contract.sh` remain the sources of
truth for selected versions.

## Executive Summary

The highest-priority work is not a blanket migration to every current major.
It is a security patch batch covering Redis, the Spring-managed dependency
stack, External Secrets Operator, Kyverno, the frontend dependency tree,
`go-redis`, the JDK runtime image, and selected observability components.

Several runtime lines are also unsupported or approaching end of support:
Spring Boot 3.5, Node.js 20, Go 1.24, RabbitMQ 3.13, NGINX 1.29, and production
Kubernetes/K3s 1.34. Those should be handled as explicit migration batches
rather than mixed into low-risk security patch updates.

## Security And Maintenance Patch Recommendations

### Redis Server

| Item | Finding |
| --- | --- |
| Checked-in reference | `redis:7-alpine@sha256:7aec734b...` |
| Version resolved from the digest | Redis 7.4.8, image created 2026-04-17 |
| Recommended supported-line patch | Redis 7.4.11 |
| Major migration status | Redis 8 exists, but is not required for support |

Redis 7.4.8 predates the May 2026 security release and is affected by multiple
authenticated memory-safety vulnerabilities, including a `RESTORE` command
issue that may lead to remote code execution. This has practical relevance to
the current ACL model: `session-gateway` and `redis-ops` receive `+@all`, while
the other service identities are substantially narrower.

Recommendation: refresh the Redis 7.4 image to 7.4.11 before considering a
Redis 8 migration. Review whether `session-gateway` needs `+@all` or can use an
explicit command allowlist that excludes administrative commands such as
`RESTORE`.

Primary advisory:
[GHSA-c8h9-259x-jff4](https://github.com/redis/redis/security/advisories/GHSA-c8h9-259x-jff4).

### Spring Boot-Managed Backend Stack

The checked-in Spring Boot 3.5.14 BOM resolves these notable components:

| Component | Boot 3.5.14 | Boot 3.5.16 | Security floor observed in this review |
| --- | --- | --- | --- |
| Spring Framework | 6.2.18 | 6.2.19 | 6.2.19 |
| Spring Security | 6.5.10 | 6.5.11 | No advisory found for 6.5.10 in the queried database |
| Jackson BOM | 2.21.2 | 2.21.4 | 2.21.4 |
| Netty | 4.1.132.Final | 4.1.135.Final | 4.1.137.Final |
| Embedded Tomcat | 10.1.54 | 10.1.55 | 10.1.58 |

Findings include:

- Spring Web 6.2.18 is affected by an `UriComponentsBuilder` SSRF advisory;
  6.2.19 contains the fix.
- Jackson 2.21.2 is affected by deserialization authorization and polymorphic
  type validation issues; the relevant 2.x fixes are present in 2.21.4.
- Netty 4.1.132 is affected by request-smuggling, decompression denial of
  service, CORS bypass, CRLF injection, and resource exhaustion advisories.
- Tomcat 10.1.54 is in the affected ranges for several authorization and
  authentication advisories. The newest reviewed fixes require 10.1.58.

Recommendation: first move the coordinated Java repositories to Spring Boot
3.5.16. Because its BOM still selects Netty 4.1.135 and Tomcat 10.1.55, assess
temporary managed-version overrides to Netty 4.1.137 and Tomcat 10.1.58. Keep
this patch batch separate from the Spring Boot 4 migration.

Applicability caveat: several Tomcat findings concern container-managed
FORM/DIGEST authentication, WebDAV, AJP, or direct HTTP/2 behavior that the
current services do not appear to use. The affected components are still in
the deployed classpath, so patching remains preferable to relying only on
configuration non-use. Netty is directly relevant to the reactive Session
Gateway and other WebFlux/WebClient paths.

Representative advisories:

- [Spring Framework SSRF](https://github.com/advisories/GHSA-7m2p-62gw-p8qq)
- [Tomcat security constraint bypass](https://github.com/advisories/GHSA-5m62-pw8w-7w9f)
- [Tomcat authentication bypass](https://github.com/advisories/GHSA-9xv2-5v5q-p794)
- [Netty request smuggling](https://github.com/advisories/GHSA-38f8-5428-x5cv)
- [Netty CORS header issue](https://github.com/advisories/GHSA-8c42-7qj2-3j46)
- [Jackson polymorphic validation bypass](https://github.com/advisories/GHSA-j3rv-43j4-c7qm)

### External Secrets Operator

| Item | Finding |
| --- | --- |
| Checked-in chart | 2.2.0 |
| Minimum security target identified | 2.4.0 |
| Current chart at review time | 2.10.0 |

External Secrets 2.2.0 is affected by DNS-based secret exfiltration through
the v2 template engine and a namespace-isolation bypass in `CAProvider`
ConfigMap resolution. Because this controller handles production secrets and
has broad cluster authority, it belongs in the critical monitoring tier even
though it was omitted from the former notification guide.

Recommendation: validate a direct move to the current 2.10.0 chart. Do not
remain below 2.4.0.

Advisories:

- [GHSA-r2pg-r6h7-crf3](https://github.com/advisories/GHSA-r2pg-r6h7-crf3)
- [GHSA-wv26-88m5-6h59](https://github.com/advisories/GHSA-wv26-88m5-6h59)

### Kyverno

| Item | Finding |
| --- | --- |
| Checked-in chart/application | 3.8.0 / 1.18.0 |
| Minimum security target identified | Application 1.18.2 |
| Current chart/application at review time | 3.9.0 / 1.19.0 |

Kyverno 1.18.0 and 1.18.1 are affected by a critical cross-namespace resource
generation vulnerability in namespaced CEL policies. The current repository
does not define `NamespacedMutatingPolicy` or `NamespacedGeneratingPolicy`
resources, which reduces present exploitability, but the controller is a
privileged admission component.

Recommendation: update the Helm chart and Kyverno CLI together to the 1.19.0
application line, then render and rerun the existing policy and security
guardrail tests.

Advisory:
[GHSA-79gf-7frw-68m9](https://github.com/kyverno/kyverno/security/advisories/GHSA-79gf-7frw-68m9).

### Frontend Dependency Tree

`npm audit` against the checked-in lockfile reported 20 findings: 3 critical,
13 high, 2 moderate, and 2 low. `npm audit --omit=dev` reported four high
findings associated with Axios, React Router, React Router DOM, and a
transitive Axios dependency.

Recommended patch batch:

| Package | Checked-in/locked baseline | Patch target at review time |
| --- | --- | --- |
| React / React DOM | 19.2.5 | 19.2.8 |
| React Router / React Router DOM | 7.14.2 | 7.18.3 |
| Axios | 1.16.0 | 1.20.0 |
| Vite | 6.4.2 | 6.4.3 or a separately planned major |
| Vitest packages | 3.2.4 | 3.2.7 or a separately planned major |
| PostCSS | 8.5.14 | 8.5.28 |

Refresh the lockfile after updating the direct dependencies so patched
versions of `form-data`, `brace-expansion`, `browserslist`, `flatted`,
`js-yaml`, `nanoid`, `picomatch`, and `ws` are selected.

Applicability caveats:

- The critical Vitest issue requires the Vitest UI server to be listening; it
  is a development-tool risk, not production browser code.
- The reviewed Vite 6.4.2 issue requires a network-exposed Windows dev server.
  The supported container path is Linux, but the patch is still low risk.
- Most React Router findings concern framework, SSR, manifest, or RSC modes.
  The application uses `BrowserRouter`, not those server modes. The open
  redirect advisory is the most relevant browser-side reason to update.
- React Server Component advisories do not apply because no
  `react-server-dom-*` package is installed. React 19.2.8 remains the sensible
  paired patch level.

### ext-authz And go-redis

`govulncheck` found a reachable call path from `ext-authz` to GO-2025-3540 in
`github.com/redis/go-redis/v9` 9.7.0. The issue may cause out-of-order responses
when `CLIENT SETINFO` times out during connection establishment. The first
fixed version is 9.7.3; the current release at review time is 9.22.0.

Recommendation: update within go-redis v9, rerun `go mod tidy`, `go test ./...`,
`govulncheck ./...`, and the shared session-contract verifiers.

Advisory: [GO-2025-3540](https://pkg.go.dev/vuln/GO-2025-3540).

### JDK Runtime Image

The pinned `eclipse-temurin:25-jre-alpine` digest resolves to JDK 25.0.3+9,
created on 2026-04-30. The current Temurin 25 maintenance release is
25.0.4.1+1.

Recommendation: refresh the Temurin digest and verify that the separately
installed Azul Zulu 25 devcontainer package receives the same quarterly CPU
level. Java 25 remains the selected LTS baseline; this is not a Java feature
release migration.

### Istio

| Item | Finding |
| --- | --- |
| Checked-in release | 1.29.2 |
| Latest patch on selected line | 1.29.7 |
| Current minor at review time | 1.31.0 |

Istio 1.29.2 is affected by a medium-severity failure mode in which an
unresolved `BackendTLSPolicy` CA reference can cause sidecars to send upstream
traffic in plaintext. The repository does not currently define a
`BackendTLSPolicy`, so the advisory is not presently reachable through the
checked-in configuration.

Recommendation: take 1.29.7 as the minimum maintenance update and plan a move
to 1.30 or 1.31 with the Kubernetes, Gateway API, and Calico batch. Istio 1.29
is expected to leave support around the end of October 2026.

Sources:

- [Istio advisory GHSA-qm8v-g4f9-qhjx](https://github.com/istio/istio/security/advisories/GHSA-qm8v-g4f9-qhjx)
- [Istio supported releases](https://istio.io/latest/docs/releases/supported-releases/)

### Observability

| Component | Checked-in version | Recommendation |
| --- | --- | --- |
| Prometheus | 3.11.1 | At least 3.11.3; prefer a currently supported line such as 3.13 |
| Grafana | 12.4.2 | Refresh to the latest 12.4 patch, 12.4.10 at review time |
| Prometheus Operator | 0.90.1 via chart 83.4.0 | Review through the chart upgrade |
| kube-prometheus-stack | 83.4.0 | Current chart was 89.2.2; treat as a rendered-manifest migration |
| Jaeger | 2.17.0 | Current was 2.20.0; no directly applicable advisory found |
| Kiali | 2.24.0 | Current chart was 2.31.0; no directly applicable advisory found |

Prometheus 3.11.1 is the last affected release for a stored XSS issue and is
also affected by a remote-read denial-of-service issue fixed in 3.11.3. The
observability services are internal-only and operator access is loopback-only,
which lowers exposure but does not eliminate the need for patching.

Sources:

- [Prometheus stored XSS](https://github.com/advisories/GHSA-vffh-x6r8-xx99)
- [Prometheus remote-read denial of service](https://github.com/prometheus/prometheus/security/advisories/GHSA-8rm2-7qqf-34qm)

### PostgreSQL

The pinned `postgres:16-alpine` digest resolves to PostgreSQL 16.13. The
current patch at review time is 16.15.

Recommendation: refresh to PostgreSQL 16.15 as routine security and bug-fix
maintenance. PostgreSQL 16 remains supported until November 2028, so the
existence of PostgreSQL 18 does not make a database major-version migration
urgent.

## Unsupported Or Approaching-EOL Migration Batches

### Spring 4 Migration

Spring Boot 3.5.16 was the latest 3.5 release found, and the standard 3.5
open-source lifecycle ended in June 2026. Current Spring releases at review
time were Spring Boot 4.1.1, Spring Cloud 2025.1.3, and Spring Security 7.1.1.

Recommendation: complete the Spring Boot 3.5 security patch batch first, then
plan the already identified coupled migration to Spring Boot 4, Spring Cloud
2025.1, Spring Framework 7, Spring Security 7, Spring Modulith 2, SpringDoc 3,
Testcontainers 2, ShedLock 7, and JUnit Platform 6.

### Node.js

The frontend Dockerfiles use Node 20, which reached end of life on 2026-04-30.
The devcontainer already selects Node 22 even though the orchestration docs
still say Node 20.

Recommendation: move production and development frontend builds to Node 24
LTS. Do not target Node 26 until it enters LTS unless there is a deliberate
reason to follow the current feature line.

Source: [Node.js releases](https://nodejs.org/en/about/previous-releases).

### Go

Go 1.24 is outside the supported two-release window. Go 1.27.1 was current at
review time, with Go 1.26 also supported.

Recommendation: choose Go 1.26 for the conservative baseline or Go 1.27 for
the current baseline, and update `ext-authz`, its builder image, and the
devcontainer together. The devcontainer download is also hardcoded to the
amd64 archive and should be made architecture-aware as part of that work.

Source: [Go release policy](https://go.dev/doc/devel/release#policy).

### RabbitMQ

The pinned digest resolves to RabbitMQ 3.13.7. RabbitMQ 3.13 has been out of
community support since September 2024; RabbitMQ 4.3.5 was current at review
time.

Recommendation: create a dedicated stateful migration plan to RabbitMQ 4.3,
covering supported upgrade hops, feature flags, persisted data compatibility,
definitions import, Spring Cloud Stream compatibility, rollback, and backup
evidence.

Source: [RabbitMQ release information](https://www.rabbitmq.com/release-information).

### NGINX

The edge gateway uses NGINX 1.29.4, and the 1.29 mainline is no longer
supported. NGINX 1.30.4 was the stable line and 1.31.5 the mainline release at
review time.

Recommendation: select either stable 1.30.4 or mainline 1.31.5 and update the
unprivileged image, configuration validation, security documentation, and
routing smoke tests together.

### Kubernetes, K3s, And Local Kind

| Component | Checked-in version | Review-time status |
| --- | --- | --- |
| Production K3s | 1.34.6+k3s1 | 1.34.11+k3s1 available; 1.34 EOL expected 2026-10-27 |
| Stable K3s channel | N/A | 1.36.4+k3s1 |
| Local Kind node | Kubernetes 1.35.0 | 1.35.8 current patch; Kubernetes 1.37 current minor |
| Kind binary | 0.31.0 | 0.33.0 current |
| Gateway API | 1.5.1 | 1.6.2 current |
| Calico | 3.32.0 | 3.32.2 current |

Recommendation: patch K3s 1.34 immediately if the minor migration is not
ready, then select a parity target—likely Kubernetes/K3s 1.36—compatible with
Istio 1.31, Gateway API, Calico, kubectl, Kind, Pod Security version labels,
and the production upgrade process.

Sources:

- [K3s release channels](https://update.k3s.io/v1-release/channels)
- [Kubernetes releases](https://kubernetes.io/releases/)
- [Istio supported Kubernetes versions](https://istio.io/latest/docs/releases/supported-releases/)

## Important Major Releases Without Immediate Security Urgency

These should appear in an automated dependency dashboard, but should not
displace the security and EOL work above:

| Area | Major release available at review time | Disposition |
| --- | --- | --- |
| PostgreSQL | 18.6 | Defer; PostgreSQL 16 remains supported |
| Redis | 8.10.1 | Defer until after the Redis 7.4 security patch |
| Helm | 4.2.4 | Deliberate compatibility project; Helm 4 is currently blocked |
| Testcontainers | 2.0.5 | Include with the Spring 4/test-stack migration |
| TypeScript | 7.0.2 | Separate frontend toolchain migration |
| Vite | 8.2.2 | Separate frontend toolchain migration |
| Vitest | 5.0.0 | Keep Vitest packages in lockstep |
| React Router | 8.3.1 | Patch v7 first; evaluate v8 separately |
| Tailwind CSS | 4.3.3 | Separate styling/build migration with CSP validation |
| ESLint | 10.10.0 | Separate lint configuration migration |

React remains on major 19. React Server Component advisories should not be
reported as applicable to the current SPA unless a `react-server-dom-*`
dependency or an RSC-capable server framework is introduced.

## Documentation Drift Found During The Review

The former dependency notification guide is unsuitable as the primary alert
mechanism, but it also contains concrete drift worth preserving before it is
archived:

- It says no known issues are tracked, which is no longer true.
- It omits K3s, External Secrets Operator, cert-manager, the Prometheus stack,
  Grafana, Prometheus, Jaeger, Kiali, Swagger UI, and other deployed images
  from its supposedly complete inventory.
- It records only human-readable image tags, hiding the exact patch version
  frozen behind each digest.
- It says Node 20 will reach EOL in April 2026; that date has passed.
- It treats Go 1.24 and RabbitMQ 3.13 as moderate-priority maintained lines;
  both are unsupported.
- It says Redis 7 is the current major and refers to PostgreSQL 17 as the next
  major; Redis 8 and PostgreSQL 18 are current.
- It says Helm 4 is only a future GA timeline to watch; Helm 4 is already GA.
- Its Istio support description uses an N/N-1 rule. Upstream currently defines
  support until approximately six weeks after N+2.
- Its Vite summary says 6.0.1 while the inventory and package manifest say
  6.4.2.
- It calls Motion "Framer Motion" 11.11.17 while the frontend now depends on
  the `motion` package at 13.1.0.
- `docs/development/devcontainer-installed-software.md` says Node 20 although
  the sibling Dockerfile selects Node 22, and says cert-manager 1.13.2 while
  the production version contract selects 1.20.2.

When dependency automation is implemented, update the canonical owner first,
then synchronize `docs/development/local-environment.md`,
`docs/development/devcontainer-installed-software.md`,
`docs/architecture/security-architecture.md`,
`docs/architecture/observability.md`, and `deploy/README.md` only where their
owned behavior or exact operational contract changes. Do not rewrite ADRs to
reflect current versions.

## Automation Comparison Baseline

No checked-in Dependabot or Renovate configuration was found in the reviewed
Budget Analyzer repositories. Repository settings such as Dependabot alerts
could not be inferred from the checkout.

After automation is enabled, compare its initial dashboard and pull requests
against this research using these categories:

1. Security findings reproduced exactly.
2. Security findings omitted by automation, especially Helm-managed
   applications and digest-pinned Kubernetes images.
3. Findings automation raises that are configuration-specific or unreachable.
4. Supported-line patch updates versus major migrations.
5. EOL findings that dependency version tools do not normally report.
6. Cross-repository coupling groups that must be merged and verified together.

Expected high-signal matches are Redis, Spring-managed transitive libraries,
External Secrets Operator, Kyverno, frontend direct and transitive packages,
`go-redis`, Temurin, Istio, Prometheus/Grafana, and the Kubernetes toolchain.

## Research Inputs

Local sources inspected:

- `docs/archive/dependency-notifications.md`
- `docs/OWNERSHIP.md`
- `docs/development/devcontainer-installed-software.md`
- `docs/development/local-environment.md`
- `deploy/scripts/lib/version-contract.sh`
- `scripts/lib/pinned-tool-versions.sh`
- `scripts/lib/image-pinning-targets.txt`
- `Tiltfile`, Kubernetes manifests, and observability Helm values
- Sibling Gradle version catalogs
- Sibling frontend `package.json` and lockfile
- Sibling `ext-authz/go.mod`
- Sibling workspace devcontainer Dockerfile

Checks performed:

- Upstream release and lifecycle review as of 2026-09-06
- GitHub Security Advisory and OSV queries for selected exact versions
- `npm audit` and `npm audit --omit=dev`
- `npm outdated`
- `govulncheck ./...` for `ext-authz`
- OCI/Docker manifest inspection to resolve exact versions behind pinned image
  digests

This research intentionally did not mutate dependencies, lockfiles,
manifests, repository settings, or the live cluster.
