# Production Reference Rendering

**Status:** Maintained provider-neutral, offline reference; not a deployment
system

Budget Analyzer currently has no production environment. This directory keeps
the provider-independent inputs needed to render and review the production
Kubernetes reference without OCI configuration, cloud credentials, a
kubeconfig, or cluster access.

The former OCI bootstrap, secret provisioning, apply, upgrade, release, and
remote-access implementation is retired. The lean removed-file inventory,
complete-tree Git provenance, exclusions, and restoration caveats are
documented in [archive/oci/README.md](../archive/oci/README.md). Do not execute
or source the archive or tagged history from active tooling.

## Maintained Surface

```text
deploy/
├── helm-values/       # Provider-independent pinned chart values
└── scripts/
    ├── lib/           # Offline render-only helpers
    └── render/        # Provider-neutral production reference renders
```

The active render commands are:

```bash
./deploy/scripts/render/production-routes.sh
./deploy/scripts/render/production-infrastructure.sh
./deploy/scripts/render/observability.sh
```

They write ignored review artifacts below `tmp/` by default and accept
`--output-dir DIR`. They never load an instance file, select a kubeconfig, or
contact a Kubernetes API. The commands may download pinned Helm charts or use
verified local CLI tools, so upstream network access can still be required.

`production-routes.sh` renders the shared Gateway API routes, ingress policies,
workload authorization policies, ingress gateway pod hardening and diagnostics,
internal-only Grafana values, and Istio egress reference. Production omits only
the standalone frontend authorization policy and does not select an ingress
Service publication type. Its
`demo.budgetanalyzer.org` and `https://auth.budgetanalyzer.org/` values are
non-secret historical reference inputs, not evidence of a live endpoint or
identity provider.

`production-infrastructure.sh` renders the shared PostgreSQL, RabbitMQ, and
Redis baseline through `kubernetes/production/infrastructure/`.

`observability.sh` copies the maintained Jaeger resources and renders the
pinned Kiali chart client-side. Because Kiali normally derives namespace RBAC
through live Helm lookups, the offline renderer deterministically expands the
approved namespace-scoped `Role` and `RoleBinding` resources.

## Validation

Use the maintained production-reference verifier as the main offline entry
point:

```bash
./scripts/guardrails/verify-production-image-overlay.sh
```

In addition to image and exposure checks, it compares rendered routes,
authorization, gateway pod configuration, and infrastructure against their
shared sources. The accepted differences are limited to the documented
hostname, standalone-frontend omission, local Kind NodePort, and Redis storage
size.

Also run the broader static and image-evidence checks when their inputs change:

```bash
./scripts/guardrails/verify-static-security-manifests.sh
./scripts/security/render-image-scan-inputs.sh --help
```

The exact image-evidence invocation and CI ownership are documented in
[docs/dependency-automation.md](../docs/dependency-automation.md) and
[scripts/README.md](../scripts/README.md).

## Reference Boundaries

The retained Kubernetes inputs preserve digest-pinned application images,
ARM64-compatible third-party image policy, routing, security, persistence, and
internal-only observability behavior. They do not choose or implement:

- a hosting provider or Kubernetes distribution;
- public load balancing, DNS, or endpoint publication;
- storage classes, capacity, backup, or disaster recovery;
- production secret management or identity-provider provisioning;
- certificate issuance, private-key handling, or TLS renewal; or
- a deployment, upgrade, rollback, or release-apply workflow.

Those are prerequisites for a future, separately authorized deployment
project. Do not infer them from the retired OCI history or add compatibility
wrappers around its commands.

## Maintainer Rules

- Keep offline render helpers free of instance files, cloud CLIs, kubeconfig
  defaults, and Kubernetes API access.
- Keep chart and tool versions in
  `scripts/lib/production-version-contract.sh`; Renovate discovers pins there.
- Keep production application image provenance in
  `kubernetes/production/apps/` and clearly marked as a historical,
  reference-only baseline.
- Keep archive paths out of active scripts, dependency discovery, image-scan
  inputs, shell-validation sweeps, and acceptance gates.
- Validate every changed active shell script with `bash -n` and ShellCheck.
