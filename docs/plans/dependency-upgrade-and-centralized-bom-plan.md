# Plan: Dependency Upgrades And Centralized Dependency Management

Date: 2026-05-02
Status: Draft

Related documents:

- `docs/dependency-notifications.md`
- `docs/OWNERSHIP.md`
- `scripts/lib/pinned-tool-versions.sh`
- `Tiltfile`
- `kind-cluster-config.yaml`
- `../workspace/ai-agent-sandbox/Dockerfile`
- `../service-common/gradle/libs.versions.toml`
- `../currency-service/gradle/libs.versions.toml`
- `../budget-analyzer-web/package.json`

## Scope

This plan covers the dependency upgrade work identified from Tier 1 and Tier 2 in
`docs/dependency-notifications.md`, plus the requested Tilt upgrade path.

It also defines a DRY dependency-management direction that keeps Spring's BOMs as the primary
source of Spring-managed versions, while removing avoidable per-service version drift.

## Current Findings

The current dependency notification guide is directionally useful, but a few entries are stale or
too local:

- Spring Cloud is only used by `currency-service` today, not by `session-gateway`.
- `currency-service` owns its own `springCloud` version, which creates avoidable drift risk.
- Java 24 is now stale as a non-LTS baseline; Java 25 LTS and Java 26 current are available.
- Kind's local Kubernetes node image is older than the supported range for the current Istio
  baseline.
- Tilt is listed as 0.37.0 and has a patch upgrade available.

## Guiding Principles

- Prefer official BOMs over hand-pinning framework transitive dependencies.
- Keep Spring Boot BOM management active for every Spring service.
- Keep Spring Cloud dependencies opt-in; do not add Cloud libraries to services that do not use
  Cloud APIs.
- Centralize version selection once, but keep service dependency declarations explicit.
- Avoid custom dependency-resolution rules, dynamic `latest` selectors, and forced versions.
- Use Gradle-native platforms before introducing custom Gradle plugins.
- Treat local Kind/Tilt and OCI/k3s as production-grade deployment paths, not throwaway tooling.

## Centralized Dependency Management Direction

### Recommended Artifact Name

Use `org.budgetanalyzer:budgetanalyzer-dependencies`.

Do not use `budgetanalyzer-spring-dependencies` unless the platform will intentionally cover only
Spring-family dependencies. The better long-term shape is a Budget Analyzer dependency platform
that imports Spring BOMs and adds the small set of project-level constraints that Spring does not
own.

The name should stay broad because the project also needs central decisions for Testcontainers,
SpringDoc, WireMock, ShedLock, frontend/tooling references in docs, and future non-Spring
constraints.

### Preferred Implementation

Create a standard Gradle `java-platform` project that publishes a Maven BOM-like artifact:

```kotlin
plugins {
    `java-platform`
}

javaPlatform {
    allowDependencies()
}

dependencies {
    api(platform("org.springframework.boot:spring-boot-dependencies:3.5.14"))
    api(platform("org.springframework.cloud:spring-cloud-dependencies:2025.0.2"))
    api(platform("org.springframework.modulith:spring-modulith-bom:1.4.11"))

    constraints {
        api("org.springdoc:springdoc-openapi-starter-webmvc-ui:2.8.13")
        api("org.springdoc:springdoc-openapi-starter-webflux-ui:2.8.13")
        api("org.testcontainers:testcontainers:1.21.4")
    }
}
```

This is not a custom dependency engine. It is a normal Gradle platform that produces standard Maven
dependency-management metadata.

### Consumer Pattern

Each backend service should import the Budget Analyzer platform once:

```kotlin
dependencies {
    implementation(platform("org.budgetanalyzer:budgetanalyzer-dependencies:0.0.x"))
}
```

Services still declare only the dependencies they actually use:

```kotlin
implementation("org.springframework.boot:spring-boot-starter-web")
implementation("org.springframework.cloud:spring-cloud-stream")
```

This keeps dependency use explicit while version selection stays centralized.

### Spring Cloud Handling

Spring Cloud cannot be managed by the Spring Boot BOM. It has its own release train BOM and
compatibility matrix.

The DRY best-practice compromise is:

- centralize the Spring Cloud release train in `budgetanalyzer-dependencies`
- import the platform in all Spring services
- only declare Spring Cloud libraries in services that actually use them
- document that Spring Cloud constraints may exist globally, but Spring Cloud dependencies remain
  opt-in

This avoids a service-local `springCloud` version without pretending Spring Boot owns Spring Cloud
versions.

If the team wants stricter separation, use a second standard Gradle platform rather than a custom
plugin:

- `budgetanalyzer-dependencies`: base backend platform with Spring Boot and common constraints
- `budgetanalyzer-spring-cloud-dependencies`: optional overlay that imports the base platform and
  the Spring Cloud BOM

With that stricter model, only `currency-service` imports the Cloud overlay today. This is more
precise, but it adds one more published artifact. Either approach is acceptable; the important rule
is that the Spring Cloud version is centralized and service dependency declarations stay explicit.

### What Not To Do

- Do not copy a shared `libs.versions.toml` into every repo by hand.
- Do not use dependency-resolution rules to rewrite versions globally.
- Do not use `enforcedPlatform` unless there is a specific conflict that normal platform
  constraints cannot solve.
- Do not apply Spring Cloud dependencies to services that do not use Spring Cloud APIs.
- Do not add a custom Gradle convention plugin in the first pass just to remove a few lines of
  build script repetition.

### Optional Later Step

If build-script repetition remains painful after the platform exists, add a small precompiled
convention plugin later, such as:

- `org.budgetanalyzer.spring-boot-service`
- `org.budgetanalyzer.spring-cloud-service`

That should be a second step. Start with the standard platform because it solves version drift with
minimal custom build logic.

## Upgrade Workstreams

### 1. Documentation And Inventory Cleanup

Update `docs/dependency-notifications.md` before code changes:

- correct Spring Cloud ownership to `currency-service` only
- update Java support text for Java 25 LTS and Java 26 current
- update latest stable references for Tier 1 and Tier 2
- keep recurring dependency monitoring policy in `docs/dependency-notifications.md`
- link this plan only as a point-in-time execution artifact if useful
- keep exact dependency locations as source-of-truth pointers, not long duplicated inventories

Validation:

- `rg -n "session-gateway.*Spring Cloud|Java 24|2025.0.0" docs/dependency-notifications.md`
- review source-of-truth pointers against actual repo files

### 2. Create `budgetanalyzer-dependencies`

Create the standard Gradle platform in the most appropriate owning repo.

Recommended owner: `../service-common`, because it already publishes shared JVM artifacts and is
the closest shared backend dependency surface.

Initial platform contents:

- Spring Boot BOM `3.5.14`
- Spring Cloud BOM `2025.0.2`
- Spring Modulith BOM `1.4.11`
- explicit constraints for SpringDoc, Testcontainers, WireMock, Awaitility, ShedLock, and any
  other versions currently repeated across backend services

Validation:

- publish locally from `service-common`
- verify each backend can resolve the platform from Maven Local in the local Tilt path
- check generated POM metadata includes imported BOMs and constraints

### 3. Move Backend Services To The Platform

For each backend service:

- import `org.budgetanalyzer:budgetanalyzer-dependencies`
- remove local `springBoot`, `springCloud`, and `springModulith` version literals where the
  platform now owns them
- keep explicit service dependency declarations
- keep `currency-service` as the only current Spring Cloud consumer

Recommended order:

1. `service-common`
2. `currency-service`
3. `transaction-service`
4. `permission-service`
5. `session-gateway`

Validation:

- run `./gradlew clean build` in each backend repo
- confirm dependency insight for Spring Boot, Spring Cloud Stream, Spring Security, and Spring
  Modulith resolves through the intended platform/BOM chain

### 4. Spring Boot, Spring Cloud, Security, And Modulith Patch Upgrades

Upgrade targets:

- Spring Boot `3.5.7` to `3.5.14`
- Spring Cloud `2025.0.0` to `2025.0.2`
- Spring Security from Boot-managed `6.5.6` to Boot-managed `6.5.10`
- Spring Modulith `1.4.0` to `1.4.11`

Defer:

- Spring Boot `4.0.6`
- Spring Cloud `2025.1.1`
- Spring Security `7.0.5`
- Spring Modulith `2.0.6`

Those are a Spring Framework 7 / Boot 4 migration and should be handled in a separate migration
branch.

Validation:

- full backend builds and tests
- targeted auth/session tests in `session-gateway`
- message publishing/consumer tests in `currency-service`
- local Tilt startup and smoke checks

### 5. Java And Gradle Upgrade

Recommended target:

- move from Java 24 to Java 25 LTS
- move Gradle from `8.14.2` to at least `9.1.0`; prefer current stable `9.5.0` if plugins pass

Rationale:

- Java 24 is a superseded non-LTS baseline.
- Java 25 gives a stable LTS target.
- Gradle's compatibility matrix requires Gradle 9.1.0 or later for Java 25 toolchain support.
- Java 26 requires Gradle 9.4.0 or later, but Java 26 is non-LTS.

Update surfaces:

- `*/gradle/wrapper/gradle-wrapper.properties`
- backend `libs.versions.toml` or the new centralized platform/convention location
- backend Dockerfile Eclipse Temurin base images
- orchestration Tilt inline Java image references
- `../workspace/ai-agent-sandbox/Dockerfile` Zulu JDK baseline
- `service-common` Javadoc links

Validation:

- regenerate Gradle wrappers non-interactively in each backend repo
- run wrapper validation if present
- run `./gradlew clean build` in each backend repo
- rebuild local service images on both `linux/amd64` and `linux/arm64` where feasible

### 6. Istio Patch Upgrade

Upgrade target:

- Istio `1.29.1` to `1.29.2`

Update surfaces:

- `Tiltfile` Helm chart versions for base, CNI, istiod, ingress gateway, and egress gateway
- production overlays if they pin Istio chart versions separately
- dependency notification docs

Validation:

- `helm template` or render equivalent for affected charts
- `tilt up`
- `kubectl get pods -A`
- route/auth smoke tests
- observability smoke checks

### 7. Kind, Kubernetes, Gateway API, Calico, And kubectl Platform Upgrade

Upgrade targets:

- Kind `v0.24.0` to `v0.31.0`
- Kind node image from Kubernetes `v1.30.8` to `v1.35.0`
- kubectl from `v1.30.8` to a compatible `v1.35.x`
- Gateway API CRDs from `v1.4.0` to `v1.5.1`
- Calico from `v3.29.3` to `v3.32.0`

Rationale:

- Istio 1.29 supports Kubernetes 1.31 through 1.35.
- The current Kind node image is Kubernetes 1.30.8, which is outside that range.
- Calico 3.32 is tested against Kubernetes 1.34, 1.35, and 1.36.

Update surfaces:

- `../workspace/ai-agent-sandbox/Dockerfile`
- `kind-cluster-config.yaml`
- `scripts/lib/pinned-tool-versions.sh`
- `scripts/bootstrap/install-calico.sh`
- `Tiltfile`
- `setup.sh`
- `scripts/bootstrap/check-tilt-prerequisites.sh`
- docs that list the local baseline

Validation:

- rebuild devcontainer
- recreate Kind cluster from the checked-in config
- `./scripts/bootstrap/check-tilt-prerequisites.sh`
- `./setup.sh` on the host path where certificate constraints apply
- `tilt up`
- `./scripts/smoketest/verify-clean-tilt-deployment-admission.sh`
- targeted Gateway/Istio route checks
- network policy smoke checks

### 8. Tilt Patch Upgrade

Upgrade target:

- Tilt `0.37.0` to `0.37.3`

Update surfaces:

- `scripts/lib/pinned-tool-versions.sh`
- `../workspace/ai-agent-sandbox/Dockerfile`
- `docs/dependency-notifications.md`
- `docs/tilt-kind-setup-guide.md`

Verified upstream checksums for 0.37.3:

- `linux-amd64`: `e90bc6cf70882bc7579d8174a27cab2de0284612ec7339e4b32f669cd5de4e5c`
- `linux-arm64`: `826f48198f368ef5edb684e9ae4c87ff76eca84c904f72b2376b29b93bffc019`
- `darwin-amd64`: `c8e2b58fb7efdec9ae7e3fc4249b4f662dc6520eabe8efcac84b80856f20d31b`
- `darwin-arm64`: `4d1f4e604aa5ca65a2df0d19c9e9b351cf9703be886f52fa5f3afd317d968ffd`

Validation:

- `./scripts/bootstrap/install-verified-tool.sh tilt`
- `./scripts/bootstrap/check-tilt-prerequisites.sh`
- `tilt doctor`
- `tilt up`
- `tilt get uiresources`

### 9. Kyverno Upgrade

Upgrade target:

- Kyverno Helm chart `3.7.1` to `3.8.0`
- Kyverno app `v1.17.1` to `v1.18.0`

Update surfaces:

- `Tiltfile`
- `scripts/lib/pinned-tool-versions.sh` if Kyverno CLI should move in lockstep
- Kyverno policy validation docs and scripts if output changes

Validation:

- render chart
- apply in local Tilt cluster
- `kubectl wait` for Kyverno controllers
- `./scripts/smoketest/verify-clean-tilt-deployment-admission.sh`
- `./scripts/smoketest/verify-phase-7-security-guardrails.sh`

### 10. PostgreSQL And Redis Image Refresh

PostgreSQL recommended path:

- stay on PostgreSQL 16 for now
- refresh `postgres:16-alpine` to the latest 16.x digest
- plan PostgreSQL 18 as a separate major data migration

Redis recommended path:

- evaluate Redis 8.6.2 as a separate compatibility task
- validate ACL behavior, persistence, client compatibility, and licensing before moving from
  Redis 7 to Redis 8
- at minimum, refresh the current `redis:7-alpine` digest if a newer supported 7.x digest exists

Validation:

- recreate local infrastructure namespace from manifests
- run service integration tests
- validate Redis ACL users and session/auth paths
- validate PostgreSQL migrations and readiness probes

### 11. Frontend React Patch Updates

Upgrade targets:

- React and React DOM to `19.2.5`
- React Router and React Router DOM to `7.14.2`
- keep Vite major migration separate unless the frontend repo is ready for Vite 8

Validation:

- `npm ci`
- `npm run lint`
- `npm run build`
- `npm test`
- local UI smoke through the real ingress path

### 12. Gradle And Tooling Documentation

After the platform and upgrade work lands:

- update `docs/dependency-notifications.md`
- update `docs/tilt-kind-setup-guide.md`
- update `scripts/README.md` if installer or verifier behavior changes
- update sibling repo docs where dependency ownership moved
- add a short explanation of `budgetanalyzer-dependencies` and when to add constraints to it

## Suggested Execution Order

1. Fix dependency documentation drift.
2. Create and publish `budgetanalyzer-dependencies`.
3. Move backend services to the platform without changing runtime versions.
4. Apply Spring Boot 3.5.x, Spring Cloud 2025.0.x, and Spring Modulith 1.4.x patch upgrades.
5. Upgrade Gradle and Java to the Java 25 LTS baseline.
6. Upgrade Tilt independently.
7. Upgrade Kind/Kubernetes, kubectl, Gateway API, and Calico as one platform batch.
8. Upgrade Istio patch level.
9. Upgrade Kyverno.
10. Refresh PostgreSQL and Redis images, keeping major data-store migrations separate.
11. Patch frontend React dependencies.
12. Run full local stack verification and update dependency docs with final versions.

## Completion Criteria

- Dependency versions are centralized where practical.
- Spring Cloud no longer has a currency-service-owned version literal.
- Services still declare only the dependencies they use.
- Java is no longer on a superseded non-LTS baseline.
- Local Kind/Kubernetes is inside the supported Istio range.
- Tilt is on the latest 0.37.x patch.
- All changed shell scripts pass `bash -n` and `shellcheck`.
- Full local startup and targeted smoke tests pass.

## Source Links

- Spring Boot: https://spring.io/projects/spring-boot/
- Spring Cloud compatibility: https://spring.io/projects/spring-cloud/
- Spring Cloud release docs: https://docs.spring.io/spring-cloud-release/reference/
- Java support roadmap: https://www.oracle.com/java/technologies/java-se-support-roadmap.html
- Gradle compatibility: https://docs.gradle.org/current/userguide/compatibility.html
- Istio supported releases: https://istio.io/latest/docs/releases/supported-releases/
- Kind releases: https://github.com/kubernetes-sigs/kind/releases
- Tilt releases: https://github.com/tilt-dev/tilt/releases
- Gateway API releases: https://github.com/kubernetes-sigs/gateway-api/releases
- Calico requirements: https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements
- Kyverno chart releases: https://github.com/kyverno/kyverno/releases
- PostgreSQL releases: https://www.postgresql.org/docs/release/
- Redis releases: https://redis.io/docs/latest/operate/oss_and_stack/stack-with-enterprise/release-notes/
- React versions: https://react.dev/versions
