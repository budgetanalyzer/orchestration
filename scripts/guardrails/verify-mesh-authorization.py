#!/usr/bin/env python3
"""Structural guard for the mesh AuthorizationPolicy caller contract.

Istio ALLOW policies are additive: an empty default-deny-all does not stop a
later broad ALLOW. This checker reads a complete policy set and the application
workloads it protects, and requires every granting branch of every ALLOW
policy (each extra policy, each rule, each `from` alternative, each principal
and each `to` alternative) to fit an explicit caller contract. It is a
structural contract checker, not an Istio request simulator, and its backend
path heuristic does not prove that a path is a public NGINX route.

The contract lives in docs/architecture/security-architecture.md#mesh-publicinternal-boundary.

Inputs:
  --source-root ROOT  local source discovery: every AuthorizationPolicy under
                      ROOT/kubernetes except ROOT/kubernetes/production (the
                      offline production reference) and Kustomize patch
                      fragments; workloads from ROOT/kubernetes/services; the
                      mesh root namespace from ROOT/kubernetes/istio/istiod-values.yaml
  --policies PATH...  explicit policy files or directories, for example the
                      rendered production-reference policy sets
  --workloads PATH... explicit workload files or directories, for example the
                      rendered production-reference app overlay
  --root-namespace NS mesh root namespace for explicit inputs
  --istiod-values F   read the mesh root namespace for explicit inputs from F
  --environment ENV   local (default) or production. Production models the
                      documented topology difference: the released frontend
                      is served by nginx-gateway, so budget-analyzer-web must
                      be absent and has no caller contract.
  --expected-workloads PATH...
                      required with --environment production: the shared
                      workload sources (kubernetes/services). Every workload
                      there except the documented production absence must be
                      present in --workloads.

Exit status: 0 when the set satisfies the contract, 1 on any violation or
malformed input, 2 on usage errors.
"""

import argparse
import json
import re
import sys
from pathlib import Path

import yaml

TRUST_DOMAIN = "cluster.local"
DEFAULT_ROOT_NAMESPACE = "istio-system"
APPLICATION_NAMESPACE = "default"
# Declared mesh namespace scope from the checked-in topology: the application
# namespace, the ingress and egress gateway namespaces and monitoring, where
# Prometheus is meshed. The mesh root namespace is added at run time. An ALLOW
# policy in any other namespace fails until this scope and its contract are
# extended.
MESH_NAMESPACES = (APPLICATION_NAMESPACE, "istio-ingress", "istio-egress", "monitoring")

INGRESS_PRINCIPAL = f"{TRUST_DOMAIN}/ns/istio-ingress/sa/istio-ingress-gateway-istio"
PROMETHEUS_PRINCIPAL = f"{TRUST_DOMAIN}/ns/monitoring/sa/prometheus-stack-kube-prom-prometheus"

DENY_ALL_ID = (APPLICATION_NAMESPACE, "default-deny-all")
# The only selectorless grant: Prometheus on the Envoy stats port of every
# default workload. Its content must match exactly; the name alone exempts
# nothing.
ENVOY_METRICS_ID = (APPLICATION_NAMESPACE, "envoy-metrics-prometheus-policy")
ENVOY_METRICS_SPEC = {
    "action": "ALLOW",
    "rules": [
        {
            "from": [{"source": {"principals": [PROMETHEUS_PRINCIPAL]}}],
            "to": [{"operation": {"ports": ["15090"]}}],
        }
    ],
}

# Workloads with this pod label expose Spring Boot actuator metrics to the
# Prometheus identity (kubernetes/monitoring/servicemonitor-spring-boot.yaml).
SPRING_BOOT_LABEL = ("app.kubernetes.io/framework", "spring-boot")
METRICS_PATH = re.compile(r"^(/[a-z0-9][a-z0-9-]*)?/actuator/prometheus$")

# The documented Session Gateway auth surface
# (docs/architecture/session-edge-authorization-pattern.md). The ingress
# identity may reach Session Gateway only on these exact policy paths.
AUTH_SURFACE_PATHS = frozenset({"/oauth2/*", "/login/oauth2/*", "/logout", "/logout/*", "/auth/*"})
# Session Gateway -> permission-service: login user sync and heartbeat lookup.
INTERNAL_PERMISSION_PAIRS = frozenset(
    {
        ("POST", "/permission-service/internal/v1/users/sync"),
        ("GET", "/permission-service/internal/v1/users/{*}/authorization"),
    }
)
# permission-service -> Session Gateway: bulk session revocation only.
REVOCATION_METHODS = frozenset({"DELETE"})
REVOCATION_PATHS = frozenset({"/internal/v1/sessions/users/{*}"})
REVOCATION_PORTS = frozenset({"8081"})

# Workloads under kubernetes/services are NGINX backends unless they have a
# special role here. Each special role must match a discovered workload.
SPECIAL_ROLES = {
    # Edge proxy behind the ingress gateway; NGINX owns route matching.
    "nginx-gateway": "ingress-edge",
    # Istio ext_authz provider called by the ingress gateway.
    "ext-authz": "ingress-edge",
    # Direct auth lane: ingress on the auth surface plus bulk revocation.
    "session-gateway": "session-gateway",
    # Local Vite frontend served through NGINX.
    "budget-analyzer-web": "frontend",
}
# Backend with an internal caller lane in addition to NGINX.
PERMISSION_SERVICE = "permission-service"
# Documented production-reference topology difference
# (kubernetes/production/README.md): the released frontend bundle is copied
# into nginx-gateway, so the standalone frontend workload and its policy are
# absent. No other workload may be absent.
PRODUCTION_ABSENT_WORKLOADS = {
    "budget-analyzer-web": "production serves the released frontend bundle from nginx-gateway",
}
ENVIRONMENTS = ("local", "production")

# Fewer than three fixed segments before a wildcard covers a whole service or
# API version, for example /transaction-service/* or /transaction-service/v1/*.
MIN_FIXED_SEGMENTS = 3

POD_TEMPLATE_KINDS = ("Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job")
KNOWN_ACTIONS = ("ALLOW", "DENY", "CUSTOM", "AUDIT")
YAML_SUFFIXES = (".yaml", ".yml")


class Malformed(Exception):
    pass


def show(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), default=str)


class Context:
    def __init__(self, label_root):
        self.label_root = label_root
        self.failures = []

    def fail(self, message):
        if message not in self.failures:
            self.failures.append(message)

    def label(self, path):
        try:
            return str(Path(path).resolve().relative_to(self.label_root))
        except ValueError:
            return str(path)


# ---------------------------------------------------------------------------
# Input loading
# ---------------------------------------------------------------------------


def yaml_files(path):
    path = Path(path)
    if path.is_dir():
        return sorted(p for p in path.rglob("*") if p.is_file() and p.suffix in YAML_SUFFIXES)
    return [path]


def load_documents(ctx, path):
    try:
        loaded = list(yaml.safe_load_all(Path(path).read_text(encoding="utf-8")))
    except (OSError, UnicodeDecodeError, yaml.YAMLError) as error:
        ctx.fail(f"{ctx.label(path)}: cannot parse: {error}")
        return []
    documents = []
    for document in loaded:
        if isinstance(document, dict) and document.get("kind") == "List":
            documents.extend(item for item in document.get("items") or [] if isinstance(item, dict))
        elif isinstance(document, dict):
            documents.append(document)
    return documents


def kustomize_patch_fragments(ctx, files):
    fragments = set()
    for path in files:
        if path.name not in ("kustomization.yaml", "kustomization.yml", "Kustomization"):
            continue
        for document in load_documents(ctx, path):
            references = []
            for entry in document.get("patches") or []:
                if isinstance(entry, dict) and isinstance(entry.get("path"), str):
                    references.append(entry["path"])
            for entry in document.get("patchesJson6902") or []:
                if isinstance(entry, dict) and isinstance(entry.get("path"), str):
                    references.append(entry["path"])
            for entry in document.get("patchesStrategicMerge") or []:
                if isinstance(entry, str) and "\n" not in entry:
                    references.append(entry)
            for reference in references:
                fragments.add((path.parent / reference).resolve())
    return fragments


def discover_source(ctx, source_root):
    kubernetes_dir = source_root / "kubernetes"
    services_dir = kubernetes_dir / "services"
    production_dir = (kubernetes_dir / "production").resolve()
    if not kubernetes_dir.is_dir() or not services_dir.is_dir():
        raise Malformed(f"{ctx.label(source_root)}: expected kubernetes/ and kubernetes/services/")

    candidates = [
        path
        for path in yaml_files(kubernetes_dir)
        if production_dir not in path.resolve().parents
    ]
    fragments = kustomize_patch_fragments(ctx, candidates)
    policy_files = []
    for path in candidates:
        if path.resolve() in fragments:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            ctx.fail(f"{ctx.label(path)}: cannot read: {error}")
            continue
        if "AuthorizationPolicy" in text:
            policy_files.append(path)

    root_namespace = DEFAULT_ROOT_NAMESPACE
    istiod_values = kubernetes_dir / "istio" / "istiod-values.yaml"
    if istiod_values.is_file():
        root_namespace = read_root_namespace(ctx, istiod_values)
    return policy_files, yaml_files(services_dir), root_namespace


def read_root_namespace(ctx, istiod_values):
    root_namespace = DEFAULT_ROOT_NAMESPACE
    for document in load_documents(ctx, istiod_values):
        configured = (document.get("meshConfig") or {}).get("rootNamespace")
        if configured:
            root_namespace = configured
    return root_namespace


# ---------------------------------------------------------------------------
# Workload inventory and caller contracts
# ---------------------------------------------------------------------------


class Workload:
    def __init__(self, name, namespace, labels, service_account, source):
        self.name = name
        self.namespace = namespace
        self.labels = labels
        self.service_account = service_account
        self.source = source

    @property
    def principal(self):
        return f"{TRUST_DOMAIN}/ns/{self.namespace}/sa/{self.service_account}"


def pod_template(document):
    kind = document.get("kind")
    spec = document.get("spec") or {}
    if kind in POD_TEMPLATE_KINDS:
        return spec.get("template")
    if kind == "CronJob":
        return ((spec.get("jobTemplate") or {}).get("spec") or {}).get("template")
    if kind == "Pod":
        return document
    return None


def load_workloads(ctx, paths, environment="local"):
    workloads = {}
    for path in paths:
        for document in load_documents(ctx, path):
            template = pod_template(document)
            if template is None:
                continue
            metadata = document.get("metadata") or {}
            name = metadata.get("name")
            where = f"{ctx.label(path)}: {document.get('kind')} {name}"
            if not isinstance(template, dict):
                ctx.fail(f"{where}: pod template is not a mapping")
                continue
            labels = (template.get("metadata") or {}).get("labels") or {}
            pod_spec = template.get("spec") or {}
            namespace = metadata.get("namespace") or APPLICATION_NAMESPACE
            if not isinstance(name, str) or not name:
                ctx.fail(f"{where}: workload has no metadata.name")
                continue
            if not isinstance(labels, dict) or not labels:
                ctx.fail(f"{where}: workload pod template has no labels for selector matching")
                continue
            if namespace != APPLICATION_NAMESPACE:
                ctx.fail(
                    f"{where}: application workload namespace {namespace!r} is outside the declared "
                    f"application namespace {APPLICATION_NAMESPACE!r}; extend the mesh contract first"
                )
                continue
            if name in workloads:
                ctx.fail(f"{where}: duplicate application workload name (also in {workloads[name].source})")
                continue
            service_account = pod_spec.get("serviceAccountName") or "default"
            workloads[name] = Workload(
                name, namespace, {str(k): str(v) for k, v in labels.items()}, service_account, ctx.label(path)
            )

    if not workloads:
        ctx.fail("no application workloads discovered; the caller contract is not checkable")
        return workloads

    by_principal = {}
    for workload in workloads.values():
        if workload.principal in by_principal:
            ctx.fail(
                f"{workload.source}: workloads {by_principal[workload.principal]} and {workload.name} share "
                f"service account principal {workload.principal}, so callers cannot be told apart"
            )
        by_principal.setdefault(workload.principal, workload.name)

    absent = PRODUCTION_ABSENT_WORKLOADS if environment == "production" else {}
    for name, reason in sorted(absent.items()):
        if name in workloads:
            ctx.fail(
                f"{workloads[name].source}: workload {name!r} must be absent from the production reference "
                f"({reason}); this documented topology difference has no production caller contract"
            )
    for name in sorted((set(SPECIAL_ROLES) | {PERMISSION_SERVICE}) - set(absent)):
        if name not in workloads:
            ctx.fail(f"caller contract names workload {name!r}, but no such workload was discovered")
    return workloads


def check_expected_workloads(ctx, paths, workloads):
    """Fail when a shared workload is missing from a rendered environment."""
    expected = {}
    for path in paths:
        for document in load_documents(ctx, path):
            name = (document.get("metadata") or {}).get("name")
            if pod_template(document) is not None and isinstance(name, str) and name:
                expected.setdefault(name, ctx.label(path))
    if not expected:
        ctx.fail("no expected workloads discovered; production workload parity is not checkable")
    for name, source in sorted(expected.items()):
        if name in PRODUCTION_ABSENT_WORKLOADS or name in workloads:
            continue
        ctx.fail(
            f"production reference is missing application workload {name!r} from {source}; only "
            f"{', '.join(sorted(PRODUCTION_ABSENT_WORKLOADS))} may be absent"
        )


class Lane:
    """One caller -> workload contract.

    check(to_entries) returns the problems for one rule's `to` list.
    """

    def __init__(self, description, check):
        self.description = description
        self.check = check


def operation_list(operation, key):
    value = operation.get(key)
    if value is None:
        return []
    if not isinstance(value, list) or not all(isinstance(item, (str, int)) for item in value):
        raise Malformed(f"operation.{key} must be a list of strings, found {show(value)}")
    return [str(item) for item in value]


def operations(to_entries):
    """Yield (index, entry, operation) for a rule's `to` list."""
    if not isinstance(to_entries, list):
        raise Malformed(f"to must be a list, found {show(to_entries)}")
    for index, entry in enumerate(to_entries):
        if not isinstance(entry, dict):
            raise Malformed(f"to[{index}] must be a mapping, found {show(entry)}")
        operation = entry.get("operation") or {}
        if not isinstance(operation, dict):
            raise Malformed(f"to[{index}].operation must be a mapping, found {show(operation)}")
        yield index, entry, operation


def caller_only(to_entries):
    # Intentional caller-only contract: any `to` only narrows it.
    if to_entries:
        list(operations(to_entries))
    return []


def backend_wildcard_problem(path):
    if not path.startswith("/"):
        return "is not an absolute path"
    if "{**}" in path:
        return "uses a multi-segment {**} template"
    if "*" in path.replace("{*}", "") and not path.endswith("*"):
        return "uses a non-suffix wildcard"
    if path.endswith("*") and not path.endswith("{*}"):
        fixed = [segment for segment in path[:-1].split("/") if segment]
        if len(fixed) < MIN_FIXED_SEGMENTS:
            return "is a service- or version-wide wildcard"
    return None


def nginx_backend(to_entries):
    if not to_entries:
        return ["has no to restriction, so NGINX reaches every backend path"]
    problems = []
    for index, entry, operation in operations(to_entries):
        paths = operation_list(operation, "paths")
        if not paths:
            problems.append(f"to[{index}] {show(entry)} does not restrict paths (unrestricted operation alternative)")
        for path in paths:
            problem = backend_wildcard_problem(path)
            if problem:
                problems.append(f"to[{index}] path {path!r} {problem}")
    return problems


def ingress_auth_surface(to_entries):
    allowed = ", ".join(sorted(AUTH_SURFACE_PATHS))
    if not to_entries:
        return [f"has no to restriction (auth path restriction: paths must stay within {allowed})"]
    problems = []
    for index, entry, operation in operations(to_entries):
        paths = operation_list(operation, "paths")
        if not paths:
            problems.append(f"to[{index}] {show(entry)} does not restrict paths (auth path restriction)")
        for path in paths:
            if path not in AUTH_SURFACE_PATHS:
                problems.append(
                    f"to[{index}] path {path!r} is outside the documented auth surface (auth path restriction: {allowed})"
                )
    return problems


def internal_permission(to_entries):
    if not to_entries:
        return ["has no to restriction (internal caller contract: exact sync POST and authorization GET only)"]
    problems = []
    for index, entry, operation in operations(to_entries):
        methods = operation_list(operation, "methods")
        paths = operation_list(operation, "paths")
        if not methods or not paths:
            problems.append(
                f"to[{index}] {show(entry)} must name both methods and paths (internal caller contract)"
            )
            continue
        for method in methods:
            for path in paths:
                if (method, path) not in INTERNAL_PERMISSION_PAIRS:
                    problems.append(
                        f"to[{index}] {method} {path!r} is not an approved Session Gateway -> permission-service "
                        "pair (internal caller contract)"
                    )
    return problems


def revocation(to_entries):
    if not to_entries:
        return ["has no to restriction (internal caller contract: DELETE revocation on port 8081 only)"]
    problems = []
    for index, entry, operation in operations(to_entries):
        fields = {
            "methods": (operation_list(operation, "methods"), REVOCATION_METHODS),
            "paths": (operation_list(operation, "paths"), REVOCATION_PATHS),
            "ports": (operation_list(operation, "ports"), REVOCATION_PORTS),
        }
        for key, (values, allowed) in fields.items():
            if not values or not set(values) <= allowed:
                problems.append(
                    f"to[{index}] {show(entry)} {key} must be within {sorted(allowed)} "
                    "(internal caller contract: bulk session revocation)"
                )
    return problems


def prometheus_metrics(to_entries):
    if not to_entries:
        return ["has no to restriction (metrics contract: GET on one port and one actuator/prometheus path)"]
    problems = []
    for index, entry, operation in operations(to_entries):
        methods = operation_list(operation, "methods")
        ports = operation_list(operation, "ports")
        paths = operation_list(operation, "paths")
        if (
            methods != ["GET"]
            or len(ports) != 1
            or not ports[0].isdigit()
            or len(paths) != 1
            or not METRICS_PATH.match(paths[0])
        ):
            problems.append(
                f"to[{index}] {show(entry)} is not GET on one port and one actuator/prometheus path (metrics contract)"
            )
    return problems


def build_lanes(workloads):
    """Return {workload name: {caller principal: Lane}} for every workload."""
    nginx = workloads.get("nginx-gateway")
    session_gateway = workloads.get("session-gateway")
    permission_service = workloads.get(PERMISSION_SERVICE)
    lanes = {}
    for name, workload in workloads.items():
        role = SPECIAL_ROLES.get(name, "backend")
        own = {}
        if role == "ingress-edge":
            own[INGRESS_PRINCIPAL] = Lane(f"ingress -> {name} (caller-only)", caller_only)
        elif role == "frontend" and nginx:
            own[nginx.principal] = Lane(f"nginx-gateway -> {name} (caller-only)", caller_only)
        elif role == "session-gateway":
            own[INGRESS_PRINCIPAL] = Lane(f"ingress -> {name} auth surface", ingress_auth_surface)
            if permission_service:
                own[permission_service.principal] = Lane(f"{PERMISSION_SERVICE} -> {name} revocation", revocation)
        elif role == "backend" and nginx:
            own[nginx.principal] = Lane(f"nginx-gateway -> backend {name}", nginx_backend)
            if name == PERMISSION_SERVICE and session_gateway:
                own[session_gateway.principal] = Lane(f"session-gateway -> {name} internal", internal_permission)
        if workload.labels.get(SPRING_BOOT_LABEL[0]) == SPRING_BOOT_LABEL[1]:
            own[PROMETHEUS_PRINCIPAL] = Lane(f"prometheus -> {name} metrics", prometheus_metrics)
        lanes[name] = own
    return lanes


# ---------------------------------------------------------------------------
# Policy evaluation
# ---------------------------------------------------------------------------


class Policy:
    def __init__(self, document, source):
        metadata = document.get("metadata") or {}
        if not isinstance(metadata, dict):
            raise Malformed(f"metadata must be a mapping, found {show(metadata)}")
        self.name = metadata.get("name")
        self.namespace = metadata.get("namespace")
        self.spec = document.get("spec")
        if self.spec is None:
            self.spec = {}
        if not isinstance(self.spec, dict):
            raise Malformed(f"spec must be a mapping, found {show(self.spec)}")
        self.action_omitted = "action" not in self.spec
        self.action = self.spec.get("action", "ALLOW")
        self.source = source

    @property
    def identity(self):
        return (self.namespace, self.name)

    @property
    def where(self):
        return f"{self.source}: {self.namespace or '<no namespace>'}/{self.name or '<unnamed>'}"


def match_labels(policy):
    selector = policy.spec.get("selector")
    if selector is None:
        return {}
    if not isinstance(selector, dict):
        raise Malformed(f"selector must be a mapping, found {show(selector)}")
    unsupported = sorted(set(selector) - {"matchLabels"})
    if unsupported:
        raise Malformed(f"selector uses unsupported fields {unsupported}; Istio selectors only support matchLabels")
    labels = selector.get("matchLabels") or {}
    if not isinstance(labels, dict):
        raise Malformed(f"selector.matchLabels must be a mapping, found {show(labels)}")
    return {str(key): str(value) for key, value in labels.items()}


def selected_workloads(policy, labels, workloads, root_namespace):
    return [
        workload
        for name, workload in sorted(workloads.items())
        if (policy.namespace == root_namespace or policy.namespace == workload.namespace)
        and all(workload.labels.get(key) == value for key, value in labels.items())
    ]


def check_envoy_metrics_exception(ctx, policy):
    if policy.spec != ENVOY_METRICS_SPEC:
        ctx.fail(
            f"{policy.where}: Envoy metrics exception mismatch: the selectorless grant must be exactly "
            f"{show(ENVOY_METRICS_SPEC)} (Prometheus principal on sole port 15090, no selector and no other "
            f"granting branch), found {show(policy.spec)}"
        )
        return False
    return True


def evaluate_rules(ctx, policy, selected, lanes, represented):
    rules = policy.spec.get("rules")
    if rules is None:
        return
    if not isinstance(rules, list):
        raise Malformed(f"rules must be a list, found {show(rules)}")
    names = ", ".join(workload.name for workload in selected)
    for rule_index, rule in enumerate(rules):
        where = f"{policy.where} rules[{rule_index}]"
        if not isinstance(rule, dict):
            raise Malformed(f"rules[{rule_index}] must be a mapping, found {show(rule)}")
        sources = rule.get("from")
        if not sources:
            ctx.fail(
                f"{where}: rule has no from, so it admits every caller of selected workload(s) {names} "
                "(unrestricted source)"
            )
            continue
        if not isinstance(sources, list):
            raise Malformed(f"rules[{rule_index}].from must be a list, found {show(sources)}")

        approved = []
        for source_index, entry in enumerate(sources):
            source = entry.get("source") if isinstance(entry, dict) else None
            principals = source.get("principals") if isinstance(source, dict) else None
            if not principals:
                ctx.fail(
                    f"{where}.from[{source_index}] {show(entry)} has no explicit source.principals "
                    "(unrestricted source alternative)"
                )
                continue
            if not isinstance(principals, list):
                raise Malformed(f"from[{source_index}].source.principals must be a list, found {show(principals)}")
            for principal in principals:
                if not isinstance(principal, str) or "*" in principal:
                    ctx.fail(f"{where}.from[{source_index}]: wildcard principal {principal!r} is not allowed")
                    continue
                unapproved = [workload.name for workload in selected if principal not in lanes[workload.name]]
                if unapproved:
                    ctx.fail(
                        f"{where}.from[{source_index}]: principal {principal!r} is not an approved caller of "
                        f"{', '.join(unapproved)} (caller contract)"
                    )
                    continue
                if principal not in approved:
                    approved.append(principal)

        # Every approved principal must satisfy its own contract on every `to`
        # alternative of this rule; there is no first-match shortcut.
        to_entries = rule.get("to")
        for principal in approved:
            for workload in selected:
                lane = lanes[workload.name][principal]
                represented.add((workload.name, principal))
                for problem in lane.check(to_entries):
                    ctx.fail(f"{where}: {lane.description}: {problem}")


def evaluate(ctx, policy_docs, workloads, root_namespace):
    lanes = build_lanes(workloads)
    represented = set()
    scope = set(MESH_NAMESPACES) | {root_namespace}
    seen = {}
    deny_all = []
    envoy_metrics = []

    for document, source in policy_docs:
        try:
            policy = Policy(document, source)
        except Malformed as error:
            ctx.fail(f"{source}: malformed AuthorizationPolicy: {error}")
            continue
        if not isinstance(policy.name, str) or not policy.name:
            ctx.fail(f"{policy.where}: AuthorizationPolicy has no metadata.name")
            continue
        if policy.identity in seen:
            ctx.fail(f"{policy.where}: duplicate AuthorizationPolicy identity (also in {seen[policy.identity]})")
            continue
        seen[policy.identity] = source

        if policy.action not in KNOWN_ACTIONS:
            ctx.fail(f"{policy.where}: unknown action {policy.action!r}")
            continue
        if policy.action != "ALLOW":
            continue  # DENY, CUSTOM and AUDIT have their own checks.

        if policy.identity == DENY_ALL_ID:
            deny_all.append(policy)
            if policy.spec == {}:
                continue
            ctx.fail(
                f"{policy.where}: default-deny-all must have an empty spec, found {show(policy.spec)}; "
                "its name exempts no grant"
            )

        try:
            evaluate_allow(ctx, policy, workloads, lanes, represented, scope, root_namespace, envoy_metrics)
        except Malformed as error:
            ctx.fail(f"{policy.where}: malformed input: {error}")

    if len(deny_all) != 1:
        ctx.fail(f"expected exactly one {DENY_ALL_ID[0]}/{DENY_ALL_ID[1]}, found {len(deny_all)}")
    if not envoy_metrics:
        ctx.fail(f"missing the Envoy metrics grant {ENVOY_METRICS_ID[0]}/{ENVOY_METRICS_ID[1]}")

    for name in sorted(workloads):
        for principal, lane in lanes[name].items():
            if (name, principal) in represented:
                continue
            if lane.check is nginx_backend:
                ctx.fail(
                    f"no ALLOW rule admits nginx-gateway to backend {name}, so the backend contract is not "
                    "checkable; add a path-restricted NGINX rule or give the workload a reasoned special role"
                )
            else:
                ctx.fail(f"baseline caller lane {lane.description} ({principal}) is not represented")


def evaluate_allow(ctx, policy, workloads, lanes, represented, scope, root_namespace, envoy_metrics):
    where = policy.where
    if not policy.namespace:
        ctx.fail(f"{where}: ALLOW policy must declare metadata.namespace")
        return
    if policy.namespace not in scope:
        ctx.fail(
            f"{where}: ALLOW policy namespace {policy.namespace!r} is outside the declared mesh namespace scope "
            f"{sorted(scope)}; extend the mesh contract first"
        )
        return
    for key in ("targetRef", "targetRefs"):
        if key in policy.spec:
            ctx.fail(
                f"{where}: ALLOW attachment through {key} is unsupported by this guard; use a workload "
                "selector that the caller contract can check"
            )
            return

    labels = match_labels(policy)
    if not labels:
        if policy.identity == ENVOY_METRICS_ID and "selector" not in policy.spec:
            if check_envoy_metrics_exception(ctx, policy):
                envoy_metrics.append(policy)
                return
        if policy.identity == DENY_ALL_ID and policy.spec == {}:
            return
        form = "implicit ALLOW (action omitted)" if policy.action_omitted else "ALLOW"
        selector_form = "an empty selector" if "selector" in policy.spec else "no selector"
        if policy.namespace == root_namespace:
            ctx.fail(
                f"{where}: {form} with {selector_form} in the mesh root namespace {root_namespace} is a broad "
                "additive grant across every mesh namespace"
            )
        else:
            ctx.fail(
                f"{where}: {form} with {selector_form} is a broad additive grant over namespace {policy.namespace}"
            )
        return

    selected = selected_workloads(policy, labels, workloads, root_namespace)
    if not selected:
        ctx.fail(
            f"{where}: ALLOW selector {show(labels)} selects no discovered application workload, so no caller "
            "contract applies (unsupported)"
        )
        return
    evaluate_rules(ctx, policy, selected, lanes, represented)


def collect_policies(ctx, paths):
    collected = []
    for path in paths:
        for document in load_documents(ctx, path):
            if document.get("kind") == "AuthorizationPolicy":
                collected.append((document, ctx.label(path)))
    return collected


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Structural mesh AuthorizationPolicy caller-contract guard.")
    parser.add_argument("--source-root", type=Path, help="discover the local policy set and workloads")
    parser.add_argument("--policies", nargs="+", type=Path, help="explicit policy files or directories")
    parser.add_argument("--workloads", nargs="+", type=Path, help="explicit workload files or directories")
    parser.add_argument("--root-namespace", help=f"mesh root namespace (default {DEFAULT_ROOT_NAMESPACE})")
    parser.add_argument("--istiod-values", type=Path, help="read the mesh root namespace from this istiod values file")
    parser.add_argument("--environment", choices=ENVIRONMENTS, default="local", help="topology to check")
    parser.add_argument(
        "--expected-workloads", nargs="+", type=Path, help="shared workload sources that a rendered environment must keep"
    )
    parser.add_argument("--label-root", type=Path, default=Path.cwd(), help="base for diagnostic file names")
    args = parser.parse_args(argv)
    if args.source_root and (args.policies or args.workloads):
        parser.error("--source-root cannot be combined with --policies or --workloads")
    if not args.source_root and not (args.policies and args.workloads):
        parser.error("use --source-root, or both --policies and --workloads")
    if args.source_root and (args.root_namespace or args.istiod_values):
        parser.error("--source-root reads the root namespace from istiod-values.yaml")
    if args.root_namespace and args.istiod_values:
        parser.error("use --root-namespace or --istiod-values, not both")
    if args.environment == "production":
        if args.source_root:
            parser.error("--environment production checks rendered inputs; use --policies and --workloads")
        if not args.expected_workloads:
            parser.error("--environment production requires --expected-workloads")
    elif args.expected_workloads:
        parser.error("--expected-workloads applies only to --environment production")
    return args


def main(argv):
    args = parse_args(argv)
    ctx = Context(args.label_root.resolve())
    policy_count = workload_count = 0
    try:
        if args.source_root:
            policy_files, workload_files, root_namespace = discover_source(ctx, args.source_root.resolve())
        else:
            policy_files = [path for item in args.policies for path in yaml_files(item)]
            workload_files = [path for item in args.workloads for path in yaml_files(item)]
            root_namespace = args.root_namespace or DEFAULT_ROOT_NAMESPACE
            if args.istiod_values:
                if not args.istiod_values.is_file():
                    raise Malformed(f"{ctx.label(args.istiod_values)}: istiod values file does not exist")
                root_namespace = read_root_namespace(ctx, args.istiod_values)
        expected_files = [path for item in args.expected_workloads or [] for path in yaml_files(item)]
        for path in policy_files + workload_files + expected_files:
            if not Path(path).is_file():
                ctx.fail(f"{ctx.label(path)}: input file does not exist")
        policies = collect_policies(ctx, policy_files)
        workloads = load_workloads(ctx, workload_files, args.environment)
        if expected_files:
            check_expected_workloads(ctx, expected_files, workloads)
        policy_count, workload_count = len(policies), len(workloads)
        evaluate(ctx, policies, workloads, root_namespace)
    except Malformed as error:
        ctx.fail(f"malformed input: {error}")
    except Exception as error:  # Fail closed on any unexpected input shape.
        ctx.fail(f"malformed input: {type(error).__name__}: {error}")

    if ctx.failures:
        for failure in ctx.failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    print(
        f"mesh authorization contract ({args.environment}): {policy_count} policies, {workload_count} workloads checked"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
