# Dependency Notification Guide

Stay informed about dependency updates to avoid painful catch-up upgrades. This guide organizes every major dependency by priority tier, provides GitHub watch links, and documents which dependencies must upgrade together.

## Supply-Chain Contract

The active pinning scope is enforced by
[`scripts/lib/phase-7-image-pinning-targets.txt`](../scripts/lib/phase-7-image-pinning-targets.txt)
and [`scripts/lib/phase-7-allowed-latest.txt`](../scripts/lib/phase-7-allowed-latest.txt).

- Only the seven explicit local Tilt image repos may remain on `:latest` in
  checked-in manifests, and only with `imagePullPolicy: Never`. Live Tilt
  deployments rewrite those same repos to immutable `:tilt-<hash>` tags and
  currently force `imagePullPolicy: IfNotPresent` during the managed apply
  path.
- Every third-party image or Docker base image is now an immutable-digest
  target, including retained test assets and sibling build surfaces.
- `tests/setup-flow` and `tests/security-preflight` are retained, stale,
  non-gating retained assets until they are realigned, but their third-party
  refs still follow the same digest-pinning rule.
- The Session 1 installer inventory remains a frozen historical record; the
  version tables below reflect the checked-in workspace toolchain.

## How to Watch a GitHub Repository for Releases

1. Go to the repository on GitHub
2. Click the **Watch** button (top right)
3. Select **Custom**
4. Check **Releases**
5. Click **Apply**

You'll receive email notifications whenever a new release is published. Configure your notification preferences at https://github.com/settings/notifications.

---

## Tier 1 - Critical

Watch these immediately. Security patches, aggressive release cadences, or painful catch-up costs if you fall behind.

### Spring Boot

| | |
|---|---|
| **Current version** | 3.5.7 |
| **Watch** | https://github.com/spring-projects/spring-boot |
| **Also follow** | https://spring.io/blog (release announcements) |
| **Defined in** | `*/gradle/libs.versions.toml` (all backend services) |
| **Upgrade cadence** | Minor releases every ~3 months, patch releases every ~4 weeks |

**Why critical**: Drives ~80% of backend dependency versions via BOM (Jackson, Flyway, Spring Security, Spring Data, etc.). Falling 2+ minor versions behind turns a routine upgrade into a multi-day effort. Security patches land here first.

**Coupling**: Must upgrade in lockstep with Spring Cloud release train. Spring Security version is managed by the Spring Boot BOM.

### Spring Cloud

| | |
|---|---|
| **Current version** | 2025.0.0 (session-gateway, currency-service) |
| **Watch** | https://github.com/spring-cloud/spring-cloud-release |
| **Also watch** | https://github.com/spring-cloud/spring-cloud-gateway (session-gateway depends on this directly) |
| **Defined in** | `session-gateway/gradle/libs.versions.toml`, `currency-service/gradle/libs.versions.toml` |

**Why critical**: Release trains are tightly coupled to Spring Boot versions. The [Spring Cloud release train compatibility table](https://spring.io/projects/spring-cloud) dictates which Spring Cloud version works with which Spring Boot version. A Spring Boot upgrade without matching the Spring Cloud release train will break compilation.

**Note**: session-gateway and currency-service are currently aligned on `2025.0.0`. Keep both services on the same release train when upgrading Spring Boot.

### Spring Security

| | |
|---|---|
| **Current version** | Managed by Spring Boot BOM |
| **Watch** | https://github.com/spring-projects/spring-security |
| **Defined in** | Version inherited from Spring Boot BOM |

**Why critical**: Security CVEs. Spring Security patches are sometimes released independently of Spring Boot patch releases. Watching this repo directly ensures you don't miss a CVE disclosure that requires an urgent BOM override.

### Istio

| | |
|---|---|
| **Current version** | 1.29.2 (Helm charts) |
| **Watch** | https://github.com/istio/istio |
| **Also follow** | https://istio.io/latest/news/security/ (security bulletins) |
| **Defined in** | `orchestration/Tiltfile` (helm upgrade commands) |
| **Upgrade cadence** | Quarterly minor releases, patch releases as needed |

**Why critical**: Istio only supports the current and previous minor version (N and N-1) with security patches. Once you fall 2 minor versions behind, you're running unpatched service mesh infrastructure. The blast radius is the entire cluster - every service's mTLS, authorization policies, and traffic routing depends on it.

**Coupling**: Must check Gateway API CRD compatibility with each Istio upgrade. Istio documents supported Gateway API versions in its release notes.

### Java / JDK

| | |
|---|---|
| **Current version** | 25 (LTS) |
| **Eclipse Temurin images** | https://github.com/adoptium/containers |
| **Azul Zulu downloads** | https://www.azul.com/downloads/ |
| **JDK release schedule** | https://www.java.com/releases/ and https://www.oracle.com/java/technologies/java-se-support-roadmap.html |
| **Defined in** | `service-common/build.gradle.kts` (toolchain), `workspace/ai-agent-sandbox/Dockerfile` (Zulu), `orchestration/Tiltfile` (Temurin base image), `transaction-service/Dockerfile`, `currency-service/Dockerfile`, `permission-service/Dockerfile`, `session-gateway/Dockerfile` |
| **Upgrade cadence** | New version every 6 months (March and September) |

**Why critical**: Java 25 is the current backend LTS baseline. Java 26 is the
current non-LTS feature release and belongs on the six-month feature-release
track, not the stable service baseline. Each JDK upgrade requires checking
Gradle compatibility and revalidating base Docker images.

**Coupling**: JDK version must match the Eclipse Temurin base image tags in the
orchestration `Tiltfile` and the four backend service Dockerfiles, the Azul
Zulu version in the devcontainer Dockerfile, and Gradle's supported JDK range.
Gradle 9.1.0+ is required for Java 25 toolchains and for running Gradle on Java
25; the checked-in backend wrappers currently use Gradle 9.5.0.

---

## Tier 2 - Important

Watch releases. Breakage risk from active development, security-adjacent, or infrastructure that's painful to upgrade reactively.

### Kind

| | |
|---|---|
| **Current version** | v0.31.0 (binary), node image `kindest/node:v1.35.0` (Kubernetes 1.35.0) |
| **Watch** | https://github.com/kubernetes-sigs/kind |
| **Defined in** | `orchestration/scripts/lib/pinned-tool-versions.sh` (binary and verified checksums), `orchestration/kind-cluster-config.yaml` (node image), `workspace/ai-agent-sandbox/Dockerfile` (devcontainer binary) |

**Why important**: Kind is newer tooling with an evolving cluster config API. Each Kind release adds support for new Kubernetes versions via node images. Staying current means smaller config changes per upgrade and access to newer Kubernetes features. The node image pins the Kubernetes API version for the entire local development environment.

**Coupling**: Kind node image determines Kubernetes version, which affects Calico compatibility, kubectl client version, and Gateway API CRD support.

### Tilt

| | |
|---|---|
| **Current version** | 0.37.3 |
| **Watch** | https://github.com/tilt-dev/tilt |
| **Defined in** | `orchestration/scripts/lib/pinned-tool-versions.sh` (repo setup and verified installer), `workspace/ai-agent-sandbox/Dockerfile` (`ARG TILT_VERSION=0.37.3`, checksum-verified release tarball) |

**Why important**: Tilt is under active development with Tiltfile API changes between versions. The entire development workflow (`tilt up`) depends on it. Breaking changes in extensions (`ext://restart_process`, `ext://configmap`, etc.) can silently break live reload, so the pinned baseline reduces surprise drift but release watching still matters before deliberate upgrades.

### Kubernetes Gateway API CRDs

| | |
|---|---|
| **Current version** | v1.5.1 |
| **Watch** | https://github.com/kubernetes-sigs/gateway-api |
| **Defined in** | `orchestration/scripts/lib/pinned-tool-versions.sh` (version and manifest URL), `orchestration/Tiltfile`, `orchestration/setup.sh`, `orchestration/scripts/bootstrap/check-tilt-prerequisites.sh` |

**Why important**: Gateway API is graduating features from beta to GA. API changes affect HTTPRoute manifests, Gateway resources, and how Istio consumes them. Istio's support for specific Gateway API versions is documented in each Istio release.

**Coupling**: Must match Istio's supported Gateway API version range.

### Calico

| | |
|---|---|
| **Current version** | v3.32.0 |
| **Watch** | https://github.com/projectcalico/calico |
| **Defined in** | `orchestration/scripts/lib/pinned-tool-versions.sh`; installed by `orchestration/scripts/bootstrap/install-calico.sh` |

**Why important**: CNI plugin that enforces NetworkPolicies. Must be compatible with the Kubernetes version running in Kind. Security-relevant because it's the enforcement layer for all network segmentation.

**Coupling**: Check the [Calico compatibility matrix](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements) when upgrading Kubernetes (Kind node image).

### Kyverno

| | |
|---|---|
| **Current version** | 3.8.0 (Helm chart), app v1.18.0 |
| **Watch** | https://github.com/kyverno/kyverno |
| **Defined in** | `orchestration/Tiltfile` (helm upgrade command) |

**Why important**: Policy engine that enforces pod security standards. Policy syntax and CRD schemas change between major versions. Currently used for pod security admission enforcement.

### PostgreSQL

| | |
|---|---|
| **Current version** | 16-alpine |
| **Watch** | https://github.com/docker-library/postgres (image tags) |
| **Also follow** | https://www.postgresql.org/support/security/ (CVE announcements) |
| **Defined in** | `orchestration/kubernetes/infrastructure/postgresql/statefulset.yaml` |

**Why important**: Database backing three services. Minor version updates (16.x) include security patches and are safe. Major version upgrades (16 to 17) require `pg_dump`/`pg_restore`. PostgreSQL 16 is supported until November 2028.

### Redis

| | |
|---|---|
| **Current version** | 7-alpine |
| **Watch** | https://github.com/redis/redis |
| **Also watch** | https://github.com/docker-library/redis (image tags) |
| **Defined in** | `orchestration/kubernetes/infrastructure/redis/statefulset.yaml` |

**Why important**: Session store for authentication (session-gateway and ext-authz both read from it). Security patches matter because it holds active session data. Redis 7 is the current major.

### React

| | |
|---|---|
| **Current version** | ^19.0.0 |
| **Watch** | https://github.com/facebook/react |
| **Defined in** | `budget-analyzer-web/package.json` |

**Why important**: Core frontend framework. Major version changes (18 to 19) changed hooks, concurrent features, and server component patterns. The entire frontend codebase depends on React's API surface.

**Coupling**: React, React DOM, and React Router major versions should be upgraded together.

### Gradle

| | |
|---|---|
| **Current version** | 8.14.2 |
| **Watch** | https://github.com/gradle/gradle |
| **Defined in** | `*/gradle/wrapper/gradle-wrapper.properties` (all backend repos) |

**Why important**: Build system for all backend services. Within major version 8, upgrades are usually smooth. A future Gradle 9 will require build script changes across all repos. Also affects compatibility with the Spring dependency management plugin.

### Spring Modulith

| | |
|---|---|
| **Current version** | 1.4.0 (currency-service only) |
| **Watch** | https://github.com/spring-projects/spring-modulith |
| **Defined in** | `currency-service/gradle/libs.versions.toml` |

**Why important**: Used by currency-service for modular architecture. Relatively new Spring project with active API evolution. Must be compatible with the Spring Boot version.

---

## Tier 3 - Moderate

Check quarterly. Lower breakage risk, strong backward compatibility, or limited blast radius.

### Node.js

| | |
|---|---|
| **Current version** | 20-alpine (LTS) |
| **Releases** | https://github.com/nodejs/node |
| **LTS schedule** | https://nodejs.org/en/about/previous-releases |
| **Defined in** | `budget-analyzer-web/Dockerfile`, `budget-analyzer-web/Dockerfile.dev` |

Node 20 LTS reaches end-of-life April 2026. Plan migration to Node 22 LTS before then.

### Go

| | |
|---|---|
| **Current version** | 1.24 |
| **Releases** | https://github.com/golang/go |
| **Download page** | https://go.dev/dl/ |
| **Defined in** | `orchestration/ext-authz/Dockerfile`, `orchestration/ext-authz/go.mod`, `workspace/ai-agent-sandbox/Dockerfile` |

Only used for ext-authz (small codebase, ~200 lines). Go has excellent backward compatibility. Check when upgrading the devcontainer.

### Vite

| | |
|---|---|
| **Current version** | ^6.0.1 |
| **Releases** | https://github.com/vitejs/vite |
| **Defined in** | `budget-analyzer-web/package.json` |

Frontend build tool. Follows semver, rarely breaks within a major version.

### TypeScript

| | |
|---|---|
| **Current version** | ^5.6.3 |
| **Releases** | https://github.com/microsoft/TypeScript |
| **Defined in** | `budget-analyzer-web/package.json` |

Incremental improvements with good backward compatibility within major version.

### RabbitMQ

| | |
|---|---|
| **Current version** | 3.13-management |
| **Releases** | https://github.com/rabbitmq/rabbitmq-server |
| **Lifecycle** | https://www.rabbitmq.com/release-information |
| **Defined in** | `orchestration/kubernetes/infrastructure/rabbitmq/statefulset.yaml` |

Message broker for currency-service. Major versions are infrequent. Check lifecycle page for EOL dates.

### NGINX

| | |
|---|---|
| **Current version** | `nginxinc/nginx-unprivileged:1.29.4-alpine` |
| **Releases** | https://github.com/nginx/nginx |
| **Download page** | https://nginx.org/en/download.html |
| **Defined in** | `orchestration/kubernetes/services/nginx-gateway/deployment.yaml` |

### Testcontainers

| | |
|---|---|
| **Current version** | 1.21.4 |
| **Releases** | https://github.com/testcontainers/testcontainers-java |
| **Defined in** | `session-gateway/gradle/libs.versions.toml`, `currency-service/gradle/libs.versions.toml`, `transaction-service/gradle/libs.versions.toml` |

Test infrastructure. Usually backward compatible within major version.

### Helm

| | |
|---|---|
| **Current version** | 3.20.x (tested v3.20.1) |
| **Releases** | https://github.com/helm/helm |
| **Defined in** | `workspace/ai-agent-sandbox/Dockerfile`, `orchestration/scripts/bootstrap/check-tilt-prerequisites.sh` |

Helm 4 is explicitly blocked in this repo. Watch only to monitor the Helm 4 GA timeline and plan accordingly.

### go-redis

| | |
|---|---|
| **Current version** | v9.7.0 |
| **Releases** | https://github.com/redis/go-redis |
| **Defined in** | `orchestration/ext-authz/go.mod` |

Only used by ext-authz. Low urgency unless security patches are published.

### Eclipse Temurin Docker Images

| | |
|---|---|
| **Current version** | 25-jre-alpine |
| **Releases** | https://github.com/adoptium/containers |
| **Defined in** | `orchestration/Tiltfile` (inline Dockerfile for Spring Boot services) |

Base image for all Spring Boot services. Updates when JDK patch versions are released.

### Distroless

| | |
|---|---|
| **Current version** | static:nonroot |
| **Releases** | https://github.com/GoogleContainerTools/distroless |
| **Defined in** | `orchestration/ext-authz/Dockerfile` |

Minimal runtime image for ext-authz. Updated infrequently.

---

## Tier 4 - Low Priority

These either ride along with Spring Boot BOM upgrades or are stable libraries that rarely have breaking changes. No need to watch - just update when doing a Spring Boot or framework upgrade.

| Dependency | Current | GitHub | Where Defined |
|---|---|---|---|
| SpringDoc OpenAPI | 2.8.13 | https://github.com/springdoc/springdoc-openapi | `*/gradle/libs.versions.toml` |
| Flyway | BOM-managed | https://github.com/flyway/flyway | Spring Boot BOM |
| Jackson | BOM-managed | https://github.com/FasterXML/jackson | Spring Boot BOM |
| ShedLock | 6.0.2 | https://github.com/lukas-krecan/ShedLock | `currency-service/gradle/libs.versions.toml` |
| PDFBox | 3.0.3 | https://github.com/apache/pdfbox | `transaction-service/gradle/libs.versions.toml` |
| OpenCSV | 3.7 | https://github.com/opencsv/opencsv | `service-common/gradle/libs.versions.toml` |
| WireMock | 3.10.0 | https://github.com/wiremock/wiremock | `session-gateway/gradle/libs.versions.toml`, `currency-service/gradle/libs.versions.toml` |
| Awaitility | 4.2.2 | https://github.com/awaitility/awaitility | `session-gateway/gradle/libs.versions.toml`, `currency-service/gradle/libs.versions.toml` |
| JUnit Platform | 1.12.2 | https://github.com/junit-team/junit5 | `*/gradle/libs.versions.toml` |
| JaCoCo | 0.8.13 | https://github.com/jacoco/jacoco | `transaction-service/gradle/libs.versions.toml` |
| Spotless | 8.0.0 | https://github.com/diffplug/spotless | `service-common/build.gradle.kts`, `*/gradle/libs.versions.toml` |
| Google Java Format | 1.32.0 | https://github.com/google/google-java-format | `service-common/build.gradle.kts` |
| Checkstyle | 12.0.1 | https://github.com/checkstyle/checkstyle | `service-common/build.gradle.kts` |
| Spring Dep Mgmt Plugin | 1.1.7 | https://github.com/spring-gradle-plugins/dependency-management-plugin | `*/gradle/libs.versions.toml` |
| Radix UI | various | https://github.com/radix-ui/primitives | `budget-analyzer-web/package.json` |
| Tanstack React Query | ^5.59.16 | https://github.com/TanStack/query | `budget-analyzer-web/package.json` |
| Tanstack React Table | ^8.20.5 | https://github.com/TanStack/table | `budget-analyzer-web/package.json` |
| Redux Toolkit | ^2.3.0 | https://github.com/reduxjs/redux-toolkit | `budget-analyzer-web/package.json` |
| React Router | ^7.0.2 | https://github.com/remix-run/react-router | `budget-analyzer-web/package.json` |
| Framer Motion | ^11.11.17 | https://github.com/motiondivision/motion | `budget-analyzer-web/package.json` |
| Axios | ^1.7.7 | https://github.com/axios/axios | `budget-analyzer-web/package.json` |
| TailwindCSS | ^3.4.14 | https://github.com/tailwindlabs/tailwindcss | `budget-analyzer-web/package.json` |
| ESLint | ^9.13.0 | https://github.com/eslint/eslint | `budget-analyzer-web/package.json` |
| Prettier | ^3.6.2 | https://github.com/prettier/prettier | `budget-analyzer-web/package.json` |
| MSW | ^2.11.6 | https://github.com/mswjs/msw | `budget-analyzer-web/package.json` |
| Vitest | ^3.2.4 | https://github.com/vitest-dev/vitest | `budget-analyzer-web/package.json` |

---

## Upgrade Coupling Groups

These dependencies must be upgraded together. Upgrading one without the others will break things.

### Spring Ecosystem

```
Spring Boot version
  -> Spring Cloud release train (compatibility table: https://spring.io/projects/spring-cloud)
  -> Spring Security version (managed by Boot BOM, but watch for independent CVE patches)
  -> Spring Modulith version (compatibility table in its README)
  -> Spring Dependency Management plugin (must support the Boot version)
```

When upgrading Spring Boot, always check the Spring Cloud release train compatibility first. session-gateway and currency-service should stay aligned on the same Spring Cloud release train.

### Kubernetes Stack

```
Kind release (new binary)
  -> Kind node image (pins Kubernetes version)
  -> kubectl client version (should match server +/- 1 minor)
  -> Calico version (check compatibility matrix)
  -> Gateway API CRDs version (check Kubernetes support)
```

When Kind releases a new version with a newer Kubernetes node image, check Calico and Gateway API CRD compatibility before upgrading.

### Istio Stack

```
Istio version
  -> Gateway API CRDs (Istio release notes list supported versions)
  -> ext-authz protocol (verify extension provider config still works)
  -> Egress gateway Helm values (service.type=ClusterIP + gateway hardening)
```

The egress gateway now installs directly from the `istio/gateway` Helm chart.
When upgrading Istio, re-check that
`kubernetes/istio/egress-gateway-values.yaml` still matches the rendered chart
behavior you depend on.

### Java Stack

```
JDK version (e.g., 25 LTS -> next selected baseline)
  -> Eclipse Temurin base image tag in Tiltfile
  -> Azul Zulu version in devcontainer Dockerfile
  -> Gradle compatibility (check supported JDK versions)
  -> Javadoc link URLs in service-common/build.gradle.kts
```

### Frontend Core

```
React major version
  -> React DOM (must match)
  -> React Router (check compatibility with React version)
  -> Testing Library React (must support React version)
```

---

## Version Inventory Reference

Quick-reference table of every pinned version and where it's defined.

The image-pinning guardrail digest-pins the orchestration-owned third-party images in the
active manifests, verifier scripts, Kind configs, and retained DinD assets. The
table below tracks the human-readable tags; the checked-in refs now use
`name:tag@sha256:...`.

### Infrastructure Tooling

| Component | Version | Where Defined |
|---|---|---|
| Kind (binary) | v0.31.0 | `orchestration/scripts/lib/pinned-tool-versions.sh`, `workspace/ai-agent-sandbox/Dockerfile` |
| Kind node image | kindest/node:v1.35.0 | `orchestration/kind-cluster-config.yaml` |
| Tilt | 0.37.3 | `orchestration/scripts/lib/pinned-tool-versions.sh`, `workspace/ai-agent-sandbox/Dockerfile` |
| Helm | 3.20.x (tested v3.20.1) | `orchestration/scripts/lib/pinned-tool-versions.sh`, `workspace/ai-agent-sandbox/Dockerfile` |
| kubectl | v1.35.4 | `orchestration/scripts/lib/pinned-tool-versions.sh`, `workspace/ai-agent-sandbox/Dockerfile` |
| Istio | 1.29.2 | `orchestration/Tiltfile` |
| Calico | v3.32.0 | `orchestration/scripts/lib/pinned-tool-versions.sh` |
| Kyverno | 3.8.0 | `orchestration/Tiltfile` |
| Gateway API CRDs | v1.5.1 | `orchestration/scripts/lib/pinned-tool-versions.sh` |
| mkcert | v1.4.4 | `orchestration/scripts/lib/pinned-tool-versions.sh` |
| kubeconform | v0.7.0 | `orchestration/scripts/lib/pinned-tool-versions.sh` |
| kube-linter | v0.8.3 | `orchestration/scripts/lib/pinned-tool-versions.sh` |
| Kyverno CLI | v1.18.0 | `orchestration/scripts/lib/pinned-tool-versions.sh` |

### Container Images

| Image | Tag | Where Used |
|---|---|---|
| eclipse-temurin | 25-jre-alpine | `orchestration/Tiltfile` (inline Dockerfiles) |
| node | 20-alpine | `budget-analyzer-web/Dockerfile`, `budget-analyzer-web/Dockerfile.dev` |
| golang | 1.24-alpine | `orchestration/ext-authz/Dockerfile` |
| distroless/static | nonroot | `orchestration/ext-authz/Dockerfile` |
| postgres | 16-alpine | `orchestration/kubernetes/infrastructure/postgresql/statefulset.yaml` |
| redis | 7-alpine | `orchestration/kubernetes/infrastructure/redis/statefulset.yaml` |
| rabbitmq | 3.13-management | `orchestration/kubernetes/infrastructure/rabbitmq/statefulset.yaml` |
| nginxinc/nginx-unprivileged | 1.29.4-alpine | `orchestration/kubernetes/services/nginx-gateway/deployment.yaml` |

### Backend (Java/Spring)

| Dependency | Version | Where Defined |
|---|---|---|
| Java | 25 | `service-common/build.gradle.kts` |
| Spring Boot | 3.5.7 | `*/gradle/libs.versions.toml` |
| Spring Cloud | 2025.0.0 | `session-gateway/gradle/libs.versions.toml`, `currency-service/gradle/libs.versions.toml` |
| Spring Modulith | 1.4.0 | `currency-service/gradle/libs.versions.toml` |
| Gradle | 9.5.0 | `*/gradle/wrapper/gradle-wrapper.properties` |
| Spring Dep Mgmt Plugin | 1.1.7 | `*/gradle/libs.versions.toml` |
| SpringDoc OpenAPI | 2.8.13 | `*/gradle/libs.versions.toml` |
| Testcontainers | 1.21.4 | `session-gateway/`, `currency-service/`, `transaction-service/gradle/libs.versions.toml` |
| WireMock | 3.10.0 | `session-gateway/`, `currency-service/gradle/libs.versions.toml` |
| Awaitility | 4.2.2 | `session-gateway/`, `currency-service/gradle/libs.versions.toml` |
| ShedLock | 6.0.2 | `currency-service/gradle/libs.versions.toml` |
| PDFBox | 3.0.3 | `transaction-service/gradle/libs.versions.toml` |
| OpenCSV | 3.7 | `service-common/gradle/libs.versions.toml` |
| JUnit Platform | 1.12.2 | `*/gradle/libs.versions.toml` |
| JaCoCo | 0.8.13 | `transaction-service/gradle/libs.versions.toml` |
| Spotless | 8.0.0 | `service-common/build.gradle.kts`, `*/gradle/libs.versions.toml` |
| Google Java Format | 1.32.0 | `service-common/build.gradle.kts` |
| Checkstyle | 12.0.1 | `service-common/build.gradle.kts` |

### Go (ext-authz)

| Dependency | Version | Where Defined |
|---|---|---|
| Go | 1.24 | `orchestration/ext-authz/go.mod`, `orchestration/ext-authz/Dockerfile` |
| go-redis | v9.7.0 | `orchestration/ext-authz/go.mod` |

### Frontend

| Dependency | Version | Where Defined |
|---|---|---|
| React | ^19.0.0 | `budget-analyzer-web/package.json` |
| React DOM | ^19.0.0 | `budget-analyzer-web/package.json` |
| React Router | ^7.0.2 | `budget-analyzer-web/package.json` |
| TypeScript | ^5.6.3 | `budget-analyzer-web/package.json` |
| Vite | ^6.0.1 | `budget-analyzer-web/package.json` |
| Vitest | ^3.2.4 | `budget-analyzer-web/package.json` |
| TailwindCSS | ^3.4.14 | `budget-analyzer-web/package.json` |
| Axios | ^1.7.7 | `budget-analyzer-web/package.json` |
| Tanstack React Query | ^5.59.16 | `budget-analyzer-web/package.json` |
| Tanstack React Table | ^8.20.5 | `budget-analyzer-web/package.json` |
| Redux Toolkit | ^2.3.0 | `budget-analyzer-web/package.json` |
| Framer Motion | ^11.11.17 | `budget-analyzer-web/package.json` |
| ESLint | ^9.13.0 | `budget-analyzer-web/package.json` |
| Prettier | ^3.6.2 | `budget-analyzer-web/package.json` |
| MSW | ^2.11.6 | `budget-analyzer-web/package.json` |

### Devcontainer

| Component | Version | Where Defined |
|---|---|---|
| Ubuntu | 24.04 | `workspace/ai-agent-sandbox/Dockerfile` |
| Azul Zulu JDK | 25 | `workspace/ai-agent-sandbox/Dockerfile` |
| Go | 1.24.1 | `workspace/ai-agent-sandbox/Dockerfile` |
| Node.js | 20.x (`NODE_MAJOR=20`) | `workspace/ai-agent-sandbox/Dockerfile` |
| Kind | v0.31.0 | `workspace/ai-agent-sandbox/Dockerfile` |
| kubectl | v1.35.4 from the Kubernetes v1.35 apt repo | `workspace/ai-agent-sandbox/Dockerfile` |
| Helm | v3.20.1 | `workspace/ai-agent-sandbox/Dockerfile` |
| Tilt | 0.37.3 | `workspace/ai-agent-sandbox/Dockerfile` |

---

## Non-GitHub Notification Sources

Some critical information is published outside of GitHub releases.

| Source | URL | What to Watch |
|---|---|---|
| Spring Blog | https://spring.io/blog | Release announcements for Spring Boot, Cloud, Security, Modulith |
| Istio Security Bulletins | https://istio.io/latest/news/security/ | CVEs and emergency patches |
| PostgreSQL Security | https://www.postgresql.org/support/security/ | CVE announcements |
| Node.js LTS Schedule | https://nodejs.org/en/about/previous-releases | EOL dates for LTS versions |
| Kubernetes Releases | https://kubernetes.io/releases/ | Kind node images track these |
| RabbitMQ Lifecycle | https://www.rabbitmq.com/release-information | EOL dates for major versions |
| Calico Compatibility | https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements | Kubernetes version compatibility matrix |
| Spring Cloud Compatibility | https://spring.io/projects/spring-cloud | Spring Boot to Spring Cloud version mapping |

---

## Known Issues

No known issues are currently tracked from this dependency audit.
