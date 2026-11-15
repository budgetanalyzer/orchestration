#!/usr/bin/env python3
"""Focused regression runner for scripts/guardrails/verify-mesh-authorization.py.

Every local case copies the checked-in kubernetes/ tree into a temporary source
root, proves that the unmodified copy passes, applies one mutation, asserts that
the mutation changed the input, and then requires the expected exit status and
diagnostics from the same helper the static gate invokes. The fail fixtures
under fixtures/fail/authorization-policy-*.yaml must fail with the diagnostics
named in their "# expect:" header lines.

Production cases render the production-reference overlays offline with the
pinned kubectl from the static tool directory, prove that the unmodified render
passes with --environment production, and then mutate either temporary
rendered copies or a temporary copy of the production overlay sources. Overlay
source mutations must still pass the local source check, proving the rendered
production check is what inspects them.

Run with the repository-local PyYAML interpreter after the static gate has
installed its pinned tools (PHASE7_STATIC_TOOLS_DIR overrides the tool dir):
  .cache/phase7-static-tools/pyyaml-venv/bin/python -I tests/security-guardrails/test-mesh-authorization.py
"""

import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

REPO_DIR = Path(__file__).resolve().parents[2]
HELPER = REPO_DIR / "scripts" / "guardrails" / "verify-mesh-authorization.py"
FIXTURE_DIR = REPO_DIR / "tests" / "security-guardrails" / "fixtures" / "fail"
POLICY_FILE = Path("kubernetes/istio/authorization-policies.yaml")
STATIC_TOOLS_DIR = Path(os.environ.get("PHASE7_STATIC_TOOLS_DIR") or REPO_DIR / ".cache" / "phase7-static-tools")
KUBECTL = STATIC_TOOLS_DIR / "bin" / "kubectl"
# Rendered production inputs, keyed by the file name each case mutates.
PRODUCTION_OVERLAYS = {
    "authorization.yaml": Path("kubernetes/production/istio"),
    "ingress-policies.yaml": Path("kubernetes/production/istio-ingress-policies"),
    "apps.yaml": Path("kubernetes/production/apps"),
}
# The app overlay reads the canonical NGINX configuration outside kubernetes/.
PRODUCTION_SOURCE_DIRS = ("kubernetes", "nginx")

NGINX = "cluster.local/ns/default/sa/nginx-gateway"
INGRESS = "cluster.local/ns/istio-ingress/sa/istio-ingress-gateway-istio"
SESSION_GATEWAY = "cluster.local/ns/default/sa/session-gateway"
EXT_AUTHZ = "cluster.local/ns/default/sa/ext-authz"
PROMETHEUS = "cluster.local/ns/monitoring/sa/prometheus-stack-kube-prom-prometheus"

BROAD_GRANT = {
    "apiVersion": "security.istio.io/v1",
    "kind": "AuthorizationPolicy",
    "metadata": {"name": "broad-allow", "namespace": "default"},
    "spec": {"action": "ALLOW", "rules": [{}]},
}


def run_helper(*args):
    return subprocess.run(
        [sys.executable, "-I", str(HELPER), "--label-root", str(REPO_DIR), *map(str, args)],
        capture_output=True,
        text=True,
        check=False,
    )


def tree_digest(root):
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        if path.is_file():
            digest.update(str(path.relative_to(root)).encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()


# ---------------------------------------------------------------------------
# Mutation helpers
# ---------------------------------------------------------------------------


def load(root, relative=POLICY_FILE):
    return [document for document in yaml.safe_load_all((root / relative).read_text()) if document]


def dump(root, documents, relative=POLICY_FILE):
    target = root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(yaml.safe_dump_all(documents, sort_keys=False))


def edit(root, name, change, namespace="default"):
    documents = load(root)
    policy = next(
        document
        for document in documents
        if document["metadata"]["name"] == name and document["metadata"]["namespace"] == namespace
    )
    change(policy["spec"])
    dump(root, documents)


def append_policy(root, policy, relative=POLICY_FILE):
    documents = load(root, relative) if (root / relative).exists() else []
    documents.append(policy)
    dump(root, documents, relative)


def policy(name, spec, namespace="default"):
    return {
        "apiVersion": "security.istio.io/v1",
        "kind": "AuthorizationPolicy",
        "metadata": {"name": name, "namespace": namespace},
        "spec": spec,
    }


def rule(spec, index):
    return spec["rules"][index]


def add_backend(root, namespace="default"):
    deployment = {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {"name": "report-service", "namespace": namespace},
        "spec": {
            "selector": {"matchLabels": {"app": "report-service"}},
            "template": {
                "metadata": {"labels": {"app": "report-service", "version": "v1"}},
                "spec": {"serviceAccountName": "report-service", "containers": []},
            },
        },
    }
    dump(root, [deployment], Path("kubernetes/services/report-service/deployment.yaml"))


def report_service_policy(paths):
    return policy(
        "report-service-policy",
        {
            "selector": {"matchLabels": {"app": "report-service"}},
            "action": "ALLOW",
            "rules": [{"from": [{"source": {"principals": [NGINX]}}], "to": [{"operation": {"paths": paths}}]}],
        },
    )


def set_envoy_metrics(change):
    return lambda root: edit(root, "envoy-metrics-prometheus-policy", change)


def broad(**changes):
    grant = policy(BROAD_GRANT["metadata"]["name"], dict(BROAD_GRANT["spec"]))
    for key, value in changes.items():
        if value is None:
            grant["spec"].pop(key, None)
        else:
            grant["spec"][key] = value
    return grant


def compose(*steps):
    def apply(root):
        for step in steps:
            step(root)

    return apply


def write_file(relative, text):
    def apply(root):
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    return apply


# Each case: (description, mutation, expected exit, required diagnostics).
CASES = [
    (
        "issue repro: namespace-wide ALLOW rules [{}] in the existing file",
        lambda root: append_policy(root, broad()),
        1,
        ["default/broad-allow", "is a broad additive grant over namespace default"],
    ),
    (
        "namespace-wide ALLOW rules [{}] in a new file",
        lambda root: append_policy(root, broad(), Path("kubernetes/istio/zz-extra-allow.yaml")),
        1,
        ["kubernetes/istio/zz-extra-allow.yaml", "broad additive grant"],
    ),
    (
        "namespace-wide ALLOW in a new directory",
        lambda root: append_policy(root, broad(), Path("kubernetes/extra/policies.yml")),
        1,
        ["kubernetes/extra/policies.yml", "broad additive grant"],
    ),
    (
        "broad grant with action omitted",
        lambda root: append_policy(root, broad(action=None)),
        1,
        ["implicit ALLOW (action omitted)", "broad additive grant"],
    ),
    (
        "broad grant with an empty selector",
        lambda root: append_policy(root, broad(selector={"matchLabels": {}})),
        1,
        ["with an empty selector is a broad additive grant"],
    ),
    (
        "broad grant in the mesh root namespace",
        lambda root: append_policy(root, policy("root-allow", {"action": "ALLOW", "rules": [{}]}, "istio-system")),
        1,
        ["istio-system/root-allow", "mesh root namespace istio-system", "across every mesh namespace"],
    ),
    (
        "root-namespace selector reaches default workloads",
        lambda root: append_policy(
            root,
            policy(
                "root-selected",
                {"selector": {"matchLabels": {"app": "transaction-service"}}, "rules": [{}]},
                "istio-system",
            ),
        ),
        1,
        ["istio-system/root-selected rules[0]", "selected workload(s) transaction-service", "unrestricted source"],
    ),
    (
        "selectorless ALLOW in istio-ingress",
        lambda root: append_policy(root, policy("ingress-allow", {"rules": [{}]}, "istio-ingress")),
        1,
        ["istio-ingress/ingress-allow", "broad additive grant over namespace istio-ingress"],
    ),
    (
        "selected ALLOW in istio-ingress has no caller contract",
        lambda root: append_policy(
            root,
            policy(
                "ingress-selected",
                {
                    "selector": {"matchLabels": {"gateway.networking.k8s.io/gateway-name": "istio-ingress-gateway"}},
                    "rules": [{}],
                },
                "istio-ingress",
            ),
        ),
        1,
        ["selects no discovered application workload"],
    ),
    (
        "ALLOW in a namespace outside the declared mesh scope",
        lambda root: append_policy(
            root,
            policy("infra-allow", {"selector": {"matchLabels": {"app": "postgresql"}}, "rules": [{}]}, "infrastructure"),
        ),
        1,
        ["outside the declared mesh namespace scope"],
    ),
    (
        "ALLOW attached through targetRefs",
        lambda root: append_policy(
            root,
            policy(
                "target-allow",
                {"targetRefs": [{"kind": "Service", "group": "", "name": "transaction-service"}], "rules": [{}]},
            ),
        ),
        1,
        ["ALLOW attachment through targetRefs is unsupported"],
    ),
    (
        "duplicate policy identity in a new file",
        lambda root: append_policy(
            root,
            next(d for d in load(root) if d["metadata"]["name"] == "currency-service-policy"),
            Path("kubernetes/istio/zz-duplicate.yaml"),
        ),
        1,
        ["duplicate AuthorizationPolicy identity"],
    ),
    (
        "issue repro: Session Gateway ingress rule without to",
        lambda root: edit(root, "session-gateway-policy", lambda spec: rule(spec, 0).pop("to")),
        1,
        ["session-gateway-policy rules[0]", "ingress -> session-gateway auth surface: has no to restriction",
         "auth path restriction"],
    ),
    (
        "Session Gateway ingress operation without paths",
        lambda root: edit(
            root, "session-gateway-policy", lambda spec: rule(spec, 0).update(to=[{"operation": {"methods": ["GET"]}}])
        ),
        1,
        ["does not restrict paths (auth path restriction)"],
    ),
    (
        "Session Gateway ingress /* path",
        lambda root: edit(
            root, "session-gateway-policy", lambda spec: rule(spec, 0)["to"][0]["operation"]["paths"].append("/*")
        ),
        1,
        ["path '/*' is outside the documented auth surface (auth path restriction"],
    ),
    (
        "Session Gateway ingress extra unrestricted operation",
        lambda root: edit(root, "session-gateway-policy", lambda spec: rule(spec, 0)["to"].append({})),
        1,
        ["to[1] {} does not restrict paths (auth path restriction)"],
    ),
    (
        "empty from alternative beside an approved source",
        lambda root: edit(root, "transaction-service-policy", lambda spec: rule(spec, 0)["from"].append({})),
        1,
        ["transaction-service-policy rules[0].from[1] {}", "unrestricted source alternative"],
    ),
    (
        "from alternative with only other source fields",
        lambda root: edit(
            root,
            "transaction-service-policy",
            lambda spec: rule(spec, 0).update({"from": [{"source": {"namespaces": ["default"]}}]}),
        ),
        1,
        ["has no explicit source.principals (unrestricted source alternative)"],
    ),
    (
        "wildcard principal",
        lambda root: edit(
            root, "transaction-service-policy", lambda spec: rule(spec, 0)["from"][0]["source"].update(principals=["*"])
        ),
        1,
        ["wildcard principal '*'"],
    ),
    (
        "wildcard principal alongside the valid principal",
        lambda root: edit(
            root,
            "transaction-service-policy",
            lambda spec: rule(spec, 0)["from"][0]["source"]["principals"].append("cluster.local/ns/default/sa/*"),
        ),
        1,
        ["wildcard principal 'cluster.local/ns/default/sa/*'"],
    ),
    (
        "unexpected principal alongside the valid principal",
        lambda root: edit(
            root,
            "transaction-service-policy",
            lambda spec: rule(spec, 0)["from"][0]["source"]["principals"].append(EXT_AUTHZ),
        ),
        1,
        [f"principal '{EXT_AUTHZ}' is not an approved caller of transaction-service (caller contract)"],
    ),
    (
        "unexpected principal in a second from alternative",
        lambda root: edit(
            root,
            "nginx-gateway-policy",
            lambda spec: rule(spec, 0)["from"].append({"source": {"principals": [PROMETHEUS]}}),
        ),
        1,
        ["nginx-gateway-policy rules[0].from[1]", "not an approved caller of nginx-gateway (caller contract)"],
    ),
    (
        "broad policy selected by the Spring framework label",
        lambda root: append_policy(
            root,
            policy("framework-allow", {"selector": {"matchLabels": {"app.kubernetes.io/framework": "spring-boot"}},
                                       "rules": [{}]}),
        ),
        1,
        ["framework-allow rules[0]",
         "selected workload(s) currency-service, permission-service, session-gateway, transaction-service"],
    ),
    (
        "NGINX grant selected by the Spring framework label reaches Session Gateway",
        lambda root: append_policy(
            root,
            policy(
                "framework-nginx",
                {
                    "selector": {"matchLabels": {"app.kubernetes.io/framework": "spring-boot"}},
                    "rules": [{"from": [{"source": {"principals": [NGINX]}}],
                               "to": [{"operation": {"paths": ["/transaction-service/v1/transactions"]}}]}],
                },
            ),
        ),
        1,
        [f"principal '{NGINX}' is not an approved caller of session-gateway (caller contract)"],
    ),
    (
        "conjunctive selector on a label pair selects the matching workload",
        lambda root: append_policy(
            root,
            policy(
                "conjunctive-allow",
                {"selector": {"matchLabels": {"app": "currency-service", "version": "v1"}}, "rules": [{}]},
            ),
        ),
        1,
        ["conjunctive-allow rules[0]", "selected workload(s) currency-service"],
    ),
    (
        "conjunctive selector that matches no workload",
        lambda root: append_policy(
            root,
            policy(
                "conjunctive-miss",
                {"selector": {"matchLabels": {"app": "currency-service", "version": "v2"}}, "rules": [{}]},
            ),
        ),
        1,
        ["conjunctive-miss", "selects no discovered application workload"],
    ),
    (
        "unrestricted to beside a valid backend operation",
        lambda root: edit(
            root, "transaction-service-policy", lambda spec: rule(spec, 0)["to"].append({"operation": {"methods": ["GET"]}})
        ),
        1,
        ['to[1] {"operation":{"methods":["GET"]}} does not restrict paths (unrestricted operation alternative)'],
    ),
    (
        "mixed NGINX and Session Gateway principals must satisfy both contracts",
        lambda root: edit(
            root,
            "permission-service-policy",
            lambda spec: rule(spec, 0)["from"][0]["source"]["principals"].append(SESSION_GATEWAY),
        ),
        1,
        ["session-gateway -> permission-service internal", "(internal caller contract)"],
    ),
    (
        "internal permission-service paths removed",
        lambda root: edit(
            root,
            "permission-service-policy",
            lambda spec: [entry["operation"].pop("paths") for entry in rule(spec, 1)["to"]],
        ),
        1,
        ["must name both methods and paths (internal caller contract)"],
    ),
    (
        "internal permission-service method broadened",
        lambda root: edit(
            root,
            "permission-service-policy",
            lambda spec: rule(spec, 1)["to"][0]["operation"].update(methods=["POST", "GET"]),
        ),
        1,
        ["GET '/permission-service/internal/v1/users/sync' is not an approved Session Gateway -> permission-service pair"],
    ),
    (
        "internal permission-service unrestricted to alternative",
        lambda root: edit(root, "permission-service-policy", lambda spec: rule(spec, 1)["to"].append({})),
        1,
        ["to[2] {} must name both methods and paths (internal caller contract)"],
    ),
    (
        "revocation port broadened",
        lambda root: edit(
            root,
            "session-gateway-policy",
            lambda spec: rule(spec, 1)["to"][0]["operation"].update(ports=["8081", "8090"]),
        ),
        1,
        ["ports must be within ['8081'] (internal caller contract: bulk session revocation)"],
    ),
    (
        "revocation method broadened",
        lambda root: edit(
            root,
            "session-gateway-policy",
            lambda spec: rule(spec, 1)["to"][0]["operation"].update(methods=["DELETE", "GET"]),
        ),
        1,
        ["methods must be within ['DELETE'] (internal caller contract: bulk session revocation)"],
    ),
    (
        "revocation port removed",
        lambda root: edit(
            root, "session-gateway-policy", lambda spec: rule(spec, 1)["to"][0]["operation"].pop("ports")
        ),
        1,
        ["ports must be within ['8081']"],
    ),
    (
        "Spring metrics path broadened",
        lambda root: edit(
            root,
            "spring-boot-metrics-prometheus-policy",
            lambda spec: rule(spec, 0)["to"][0]["operation"].update(paths=["/actuator/*"]),
        ),
        1,
        ["spring-boot-metrics-prometheus-policy rules[0]", "(metrics contract)"],
    ),
    (
        "Spring metrics port restriction removed",
        lambda root: edit(
            root, "spring-boot-metrics-prometheus-policy", lambda spec: rule(spec, 0)["to"][1]["operation"].pop("ports")
        ),
        1,
        ["to[1]", "is not GET on one port and one actuator/prometheus path (metrics contract)"],
    ),
    (
        "Envoy metrics exception principal changed",
        set_envoy_metrics(lambda spec: rule(spec, 0)["from"][0]["source"].update(principals=[NGINX])),
        1,
        ["envoy-metrics-prometheus-policy: Envoy metrics exception mismatch"],
    ),
    (
        "Envoy metrics exception port changed",
        set_envoy_metrics(lambda spec: rule(spec, 0)["to"][0]["operation"].update(ports=["15090", "8081"])),
        1,
        ["Envoy metrics exception mismatch"],
    ),
    (
        "Envoy metrics exception gains a granting rule",
        set_envoy_metrics(lambda spec: spec["rules"].append({})),
        1,
        ["Envoy metrics exception mismatch", "broad additive grant"],
    ),
    (
        "Envoy metrics exception gains a to alternative",
        set_envoy_metrics(lambda spec: rule(spec, 0)["to"].append({"operation": {"paths": ["/*"]}})),
        1,
        ["Envoy metrics exception mismatch"],
    ),
    (
        "Envoy metrics exception action omitted",
        set_envoy_metrics(lambda spec: spec.pop("action")),
        1,
        ["Envoy metrics exception mismatch", "implicit ALLOW (action omitted)"],
    ),
    (
        "default-deny-all gains a grant",
        lambda root: edit(root, "default-deny-all", lambda spec: spec.update(rules=[{}])),
        1,
        ["default-deny-all must have an empty spec", "broad additive grant over namespace default"],
    ),
    (
        "synthetic backend without an NGINX path rule",
        add_backend,
        1,
        ["no ALLOW rule admits nginx-gateway to backend report-service"],
    ),
    (
        "synthetic backend with a valid NGINX path rule",
        compose(add_backend, lambda root: append_policy(
            root, report_service_policy(["/report-service/v1/reports", "/report-service/v1/reports/*"]))),
        0,
        [],
    ),
    (
        "synthetic backend with a version-wide NGINX path",
        compose(add_backend, lambda root: append_policy(root, report_service_policy(["/report-service/v1/*"]))),
        1,
        ["path '/report-service/v1/*' is a service- or version-wide wildcard"],
    ),
    (
        "application workload in an undeclared namespace",
        lambda root: add_backend(root, namespace="reports"),
        1,
        ["application workload namespace 'reports' is outside the declared application namespace"],
    ),
    (
        "special role without a discovered workload",
        lambda root: shutil.rmtree(root / "kubernetes/services/ext-authz"),
        1,
        ["caller contract names workload 'ext-authz', but no such workload was discovered"],
    ),
    (
        "local frontend workload stays required",
        lambda root: shutil.rmtree(root / "kubernetes/services/budget-analyzer-web"),
        1,
        ["caller contract names workload 'budget-analyzer-web', but no such workload was discovered"],
    ),
    (
        "baseline caller lane removed",
        lambda root: dump(root, [d for d in load(root) if d["metadata"]["name"] != "nginx-gateway-policy"]),
        1,
        [f"baseline caller lane ingress -> nginx-gateway (caller-only) ({INGRESS}) is not represented"],
    ),
    (
        "narrower caller-only grant still passes",
        lambda root: edit(
            root, "ext-authz-policy", lambda spec: rule(spec, 0).update(to=[{"operation": {"ports": ["9002"]}}])
        ),
        0,
        [],
    ),
    (
        "additional DENY policy is left to its own checks",
        lambda root: append_policy(root, policy("extra-deny", {"action": "DENY", "rules": [{}]})),
        0,
        [],
    ),
    (
        "Kustomize patch fragment is not a standalone policy",
        compose(
            write_file(
                "kubernetes/istio/local-overlay/kustomization.yaml",
                "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n"
                "  - ../authorization-policies.yaml\npatches:\n  - path: patches/delete-deny.yaml\n",
            ),
            write_file(
                "kubernetes/istio/local-overlay/patches/delete-deny.yaml",
                "$patch: delete\napiVersion: security.istio.io/v1\nkind: AuthorizationPolicy\n"
                "metadata:\n  name: default-deny-all\n  namespace: default\n",
            ),
        ),
        0,
        [],
    ),
    (
        "malformed rules list",
        lambda root: edit(root, "currency-service-policy", lambda spec: spec.update(rules="nginx")),
        1,
        ["currency-service-policy: malformed input: rules must be a list"],
    ),
    (
        "unparseable policy file",
        write_file("kubernetes/istio/zz-broken.yaml", "kind: AuthorizationPolicy\nspec: [unterminated\n"),
        1,
        ["kubernetes/istio/zz-broken.yaml: cannot parse"],
    ),
]


# ---------------------------------------------------------------------------
# Production-reference render cases
# ---------------------------------------------------------------------------


def render_production(source_root, out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, overlay in PRODUCTION_OVERLAYS.items():
        result = subprocess.run(
            [str(KUBECTL), "kustomize", str(source_root / overlay), "--load-restrictor=LoadRestrictionsNone"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise RuntimeError(f"failed to render {overlay}: {result.stderr.strip()}")
        (out_dir / name).write_text(result.stdout)


def run_production(render_dir, source_root=REPO_DIR):
    return run_helper(
        "--environment", "production",
        "--policies", render_dir / "authorization.yaml", render_dir / "ingress-policies.yaml",
        "--workloads", render_dir / "apps.yaml",
        "--expected-workloads", source_root / "kubernetes" / "services",
        "--istiod-values", source_root / "kubernetes" / "istio" / "istiod-values.yaml",
    )


def edit_rendered(name, change):
    def apply(render_dir):
        path = render_dir / name
        documents = [document for document in yaml.safe_load_all(path.read_text()) if document]
        documents = change(documents)
        path.write_text(yaml.safe_dump_all(documents, sort_keys=False))

    return apply


def append_rendered(name, document):
    return edit_rendered(name, lambda documents: documents + [document])


def edit_rendered_policy(policy_name, change):
    def apply(documents):
        target = next(d for d in documents if d["metadata"]["name"] == policy_name)
        change(target["spec"])
        return documents

    return edit_rendered("authorization.yaml", apply)


def drop_rendered(name, kind, resource_name):
    return edit_rendered(
        name,
        lambda documents: [
            d for d in documents if not (d.get("kind") == kind and d["metadata"]["name"] == resource_name)
        ],
    )


def local_frontend_deployment():
    path = REPO_DIR / "kubernetes/services/budget-analyzer-web/deployment.yaml"
    return next(d for d in yaml.safe_load_all(path.read_text()) if d and d.get("kind") == "Deployment")


def add_production_resource(file_name, document):
    def apply(root):
        overlay = root / PRODUCTION_OVERLAYS["authorization.yaml"]
        (overlay / file_name).write_text(yaml.safe_dump(document, sort_keys=False))
        kustomization = yaml.safe_load((overlay / "kustomization.yaml").read_text())
        kustomization["resources"].append(file_name)
        (overlay / "kustomization.yaml").write_text(yaml.safe_dump(kustomization, sort_keys=False))

    return apply


def add_production_patch(target_name, operations):
    def apply(root):
        overlay = root / PRODUCTION_OVERLAYS["authorization.yaml"]
        kustomization = yaml.safe_load((overlay / "kustomization.yaml").read_text())
        kustomization["patches"].append(
            {
                "target": {"group": "security.istio.io", "kind": "AuthorizationPolicy", "name": target_name},
                "patch": yaml.safe_dump(operations, sort_keys=False),
            }
        )
        (overlay / "kustomization.yaml").write_text(yaml.safe_dump(kustomization, sort_keys=False))

    return apply


def drop_frontend_deletion_patch(root):
    overlay = root / PRODUCTION_OVERLAYS["authorization.yaml"]
    kustomization = yaml.safe_load((overlay / "kustomization.yaml").read_text())
    kustomization.pop("patches")
    (overlay / "kustomization.yaml").write_text(yaml.safe_dump(kustomization, sort_keys=False))


# Each case mutates temporary copies of the rendered production files:
# (description, mutation, required diagnostics). Every case must fail.
PRODUCTION_RENDER_CASES = [
    (
        "production issue repro: namespace-wide ALLOW rules [{}]",
        append_rendered("authorization.yaml", broad()),
        ["default/broad-allow", "is a broad additive grant over namespace default"],
    ),
    (
        "production issue repro: Session Gateway ingress rule without to",
        edit_rendered_policy("session-gateway-policy", lambda spec: rule(spec, 0).pop("to")),
        ["session-gateway-policy rules[0]", "ingress -> session-gateway auth surface: has no to restriction"],
    ),
    (
        "production added broad policy in the rendered ingress policy set",
        append_rendered("ingress-policies.yaml", policy("ingress-allow", {"rules": [{}]}, "istio-ingress")),
        ["istio-ingress/ingress-allow", "broad additive grant over namespace istio-ingress"],
    ),
    (
        "production added broad policy in the mesh root namespace",
        append_rendered("authorization.yaml", policy("root-allow", {"action": "ALLOW", "rules": [{}]}, "istio-system")),
        ["istio-system/root-allow", "mesh root namespace istio-system"],
    ),
    (
        "production broadened Envoy metrics exception",
        edit_rendered_policy(
            "envoy-metrics-prometheus-policy",
            lambda spec: rule(spec, 0)["to"][0]["operation"].update(ports=["15090", "8081"]),
        ),
        ["envoy-metrics-prometheus-policy: Envoy metrics exception mismatch"],
    ),
    (
        "production standalone frontend workload reappears",
        append_rendered("apps.yaml", local_frontend_deployment()),
        ["workload 'budget-analyzer-web' must be absent from the production reference"],
    ),
    (
        "production render loses a backend workload",
        drop_rendered("apps.yaml", "Deployment", "transaction-service"),
        ["production reference is missing application workload 'transaction-service'"],
    ),
    (
        "production render loses a special-role workload",
        drop_rendered("apps.yaml", "Deployment", "ext-authz"),
        ["caller contract names workload 'ext-authz'", "missing application workload 'ext-authz'"],
    ),
    (
        "production render loses a backend policy",
        drop_rendered("authorization.yaml", "AuthorizationPolicy", "transaction-service-policy"),
        ["no ALLOW rule admits nginx-gateway to backend transaction-service"],
    ),
    (
        "production render loses default-deny-all",
        drop_rendered("authorization.yaml", "AuthorizationPolicy", "default-deny-all"),
        ["expected exactly one default/default-deny-all, found 0"],
    ),
    (
        "production render loses the Envoy metrics grant",
        drop_rendered("authorization.yaml", "AuthorizationPolicy", "envoy-metrics-prometheus-policy"),
        ["missing the Envoy metrics grant default/envoy-metrics-prometheus-policy"],
    ),
    (
        "production render loses the Spring metrics lane",
        drop_rendered("authorization.yaml", "AuthorizationPolicy", "spring-boot-metrics-prometheus-policy"),
        ["baseline caller lane prometheus -> transaction-service metrics"],
    ),
]

# Each case mutates a temporary copy of the production overlay sources. The
# local source check must still pass and the production render must fail.
PRODUCTION_SOURCE_CASES = [
    (
        "production-only overlay resource adds a broad ALLOW",
        add_production_resource("zz-extra-allow.yaml", broad()),
        ["default/broad-allow", "is a broad additive grant over namespace default"],
    ),
    (
        "production-only overlay patch removes the Session Gateway auth paths",
        add_production_patch("session-gateway-policy", [{"op": "remove", "path": "/spec/rules/0/to"}]),
        ["session-gateway-policy rules[0]", "ingress -> session-gateway auth surface: has no to restriction"],
    ),
    (
        "production-only overlay patch adds an unrestricted Spring metrics operation",
        add_production_patch(
            "spring-boot-metrics-prometheus-policy",
            [{"op": "add", "path": "/spec/rules/0/to/-", "value": {"operation": {"methods": ["GET"]}}}],
        ),
        ["spring-boot-metrics-prometheus-policy rules[0]", "(metrics contract)"],
    ),
    (
        "production frontend deletion patch dropped",
        drop_frontend_deletion_patch,
        ["default/budget-analyzer-web-policy", "selects no discovered application workload"],
    ),
]


def run_production_cases(work_dir, failures):
    if not os.access(KUBECTL, os.X_OK):
        failures.append(
            f"pinned kubectl is not executable at {KUBECTL}; run "
            "scripts/guardrails/verify-static-security-manifests.sh (or --self-test) to install the verified tools"
        )
        return

    baseline_dir = work_dir / "production-baseline"
    try:
        render_production(REPO_DIR, baseline_dir)
    except RuntimeError as error:
        failures.append(f"production reference render failed: {error}")
        return
    baseline = run_production(baseline_dir)
    if baseline.returncode != 0:
        failures.append(f"unmodified production render was rejected\n{baseline.stdout}{baseline.stderr}")
        return
    print("ok - unmodified production render and workloads pass")

    usage = run_helper("--environment", "production", "--policies", baseline_dir / "authorization.yaml",
                       "--workloads", baseline_dir / "apps.yaml")
    check_result("production mode requires --expected-workloads", usage, 2,
                 ["--environment production requires --expected-workloads"], failures)

    for index, (description, mutate, diagnostics) in enumerate(PRODUCTION_RENDER_CASES):
        render_dir = work_dir / f"production-render-{index:02d}"
        shutil.copytree(baseline_dir, render_dir)
        before = tree_digest(render_dir)
        mutate(render_dir)
        if tree_digest(render_dir) == before:
            failures.append(f"{description}: mutation did not change the rendered input")
            continue
        check_result(description, run_production(render_dir), 1, diagnostics, failures)
        shutil.rmtree(render_dir)

    for index, (description, mutate, diagnostics) in enumerate(PRODUCTION_SOURCE_CASES):
        root = work_dir / f"production-source-{index:02d}"
        for directory in PRODUCTION_SOURCE_DIRS:
            shutil.copytree(REPO_DIR / directory, root / directory, symlinks=True)
        mutate(root)
        render_dir = root / "rendered"
        try:
            render_production(root, render_dir)
        except RuntimeError as error:
            failures.append(f"{description}: {error}")
            continue
        if tree_digest(render_dir) == tree_digest(baseline_dir):
            failures.append(f"{description}: overlay mutation did not change the production render")
            continue
        local = run_helper("--source-root", root)
        if local.returncode != 0:
            failures.append(f"{description}: local source check unexpectedly failed, so it does not prove the "
                            f"production render is inspected\n{local.stdout}{local.stderr}")
            continue
        check_result(description, run_production(render_dir, root), 1, diagnostics, failures)
        shutil.rmtree(root)


def check_result(description, result, expected_status, diagnostics, failures):
    output = result.stdout + result.stderr
    if result.returncode != expected_status:
        failures.append(f"{description}: expected exit {expected_status}, got {result.returncode}\n{output}")
        return
    missing = [text for text in diagnostics if text not in result.stderr]
    if missing:
        failures.append(f"{description}: missing diagnostics {missing}\n{output}")
        return
    print(f"ok - {description}")


def run_cases(work_dir, failures):
    for index, (description, mutate, expected_status, diagnostics) in enumerate(CASES):
        root = work_dir / f"case-{index:02d}"
        shutil.copytree(REPO_DIR / "kubernetes", root / "kubernetes", symlinks=True)
        baseline = run_helper("--source-root", root)
        if baseline.returncode != 0:
            failures.append(f"{description}: baseline copy was rejected, so the mutation proves nothing\n"
                            f"{baseline.stdout}{baseline.stderr}")
            continue
        before = tree_digest(root)
        mutate(root)
        if tree_digest(root) == before:
            failures.append(f"{description}: mutation did not change the input")
            continue
        check_result(description, run_helper("--source-root", root), expected_status, diagnostics, failures)
        shutil.rmtree(root)


def run_fixtures(failures):
    fixtures = sorted(FIXTURE_DIR.glob("authorization-policy-*.yaml"))
    if not fixtures:
        failures.append("no authorization-policy-*.yaml fail fixtures found")
    for fixture in fixtures:
        expects = [
            line.split("# expect:", 1)[1].strip()
            for line in fixture.read_text().splitlines()
            if line.startswith("# expect:")
        ]
        description = f"fixture {fixture.name}"
        if not expects:
            failures.append(f"{description}: has no '# expect:' diagnostic lines")
            continue
        result = run_helper("--policies", fixture, "--workloads", REPO_DIR / "kubernetes" / "services")
        check_result(description, result, 1, expects, failures)


def main():
    failures = []
    baseline = run_helper("--source-root", REPO_DIR)
    if baseline.returncode != 0:
        failures.append(f"unmodified repository policy set was rejected\n{baseline.stdout}{baseline.stderr}")
    else:
        print("ok - unmodified repository policy set and workloads pass")
    with tempfile.TemporaryDirectory(prefix="mesh-authorization-") as work_dir:
        run_cases(Path(work_dir), failures)
        run_production_cases(Path(work_dir), failures)
    run_fixtures(failures)

    if failures:
        for failure in failures:
            print(f"FAIL - {failure}", file=sys.stderr)
        print(f"mesh authorization regression runner failed ({len(failures)} failures)", file=sys.stderr)
        return 1
    production = len(PRODUCTION_RENDER_CASES) + len(PRODUCTION_SOURCE_CASES)
    print(
        f"mesh authorization regression runner passed ({len(CASES)} local cases, {production} production cases, "
        "fixtures included)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
