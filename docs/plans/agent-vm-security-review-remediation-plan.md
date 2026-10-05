# Native VM Security Review Remediation

**Status:** Ready for repository implementation; not executed. The original
native migration and human A–D checkpoints are complete by operator confirmation
in [the acceptance record](agent-host-isolation-acceptance.md#native-human-acceptance).
This is a new plan and must use its own AI Session Handler state. Never rerun
the migration's destructive bootstrap, retirement or installation checkpoints.

Close the final review findings against orchestration `3b67af2` and workspace
`fed714c`: missing tracked npm lock, ineffective TLS hostname rejection, weak
Kubernetes URL authority checks, confirmed host firewall precedence defects,
incomplete Mint Docker retirement, duplicate guest CA installation, and
obsolete transitional workflows/helpers.
Keep the existing simple runtime: one VM, one guest user/home, native agents,
one guest Docker daemon, host-initiated Git/SSH, no host mounts or credentials.

The plan authoring change supplies the read-only host evidence collector and
its [runbook](../runbooks/host-isolation-audit.md), and records operator-attested
migration completion. Those are prerequisites available to the phases below,
not evidence that any remediation phase passed. The first operator-supplied
host report confirms early multicast and libvirt DNS/DHCP accepts plus retained
Mint Docker artifacts. It also supplies positive confinement and loopback-bind
evidence. Firewall repair, post-reboot protocol proof and final retirement
evidence remain human-owned acceptance gates.

## Execution And Authority

- Follow the [boundary contract](../architecture/autonomous-ai-execution.md).
  Each phase executes only in its declared repository; siblings are read-only.
  Workspace code changes must be performed by a workspace worker. No service
  implementation changes, production access, Git writes, package updates or
  additional virtualization/container layers are part of this plan.
- Preserve the accepted migration execution-plan bytes and existing runner
  state. Record new work in each repository's owner docs; orchestration's
  [post-migration review](agent-host-isolation-acceptance.md#post-migration-security-review)
  tracks integrated results. Historical timestamped evidence stays historical.
- Do not run live guest installers, write system/NSS trust, generate/rotate
  certificates, administer the host, reboot, restart Docker, recreate Kind or
  retire runtime resources from an agent. Offline fixtures use repository
  `tmp/` and synthetic identities. Human installation of reviewed fixes is a
  distinct handoff after affected workers stop.
- Before live cluster mutations run the native runtime preflight and exact
  local target gate. Prefer offline checks and read-only live validation here.
  Any smoke suite that mutates the guest cluster still requires those gates.
- Do not generate browser/infrastructure certificates even for a test. Use
  checked-in public certificate fixtures without private keys, pure command
  fixtures and parsing tests, or established real certificates read-only.
- Human host repair and evidence collection may happen only after Phase 6 has
  produced a concrete reviewable handoff. Before Phase 7 can complete, the
  human must apply the reviewed repair, complete the remaining D.3 retirement,
  reboot, privately review the new report and provide the required paired
  protocol and live trust/tool results. Missing evidence leaves Phase 7
  stopped, never an inferred PASS. An agent must not administer the host or
  install guest-authored policy there.
- Treat every candidate host report as private until a human reviews its
  publication scope. The current Git-tracked report is evidence input, not a
  source file to quote or replicate; this plan does not authorize Git removal,
  history rewriting or external publication of that report.
- This authorizes planned repository fixes and retirement of obsolete tracked
  container support after its consumers have been accounted for. It does not
  authorize removing host/guest runtime data or discarding unrelated tooling.

## Phase 1: Make Native Installation Reproducible From Git

### Workspace

../workspace

### Goal

Every native installer input survives ordinary Git transfer, including the
reviewed npm integrity lock, and validation no longer passes on ignored inputs.

### Scope

The npm input files, ignore rules, manifest/environment checks and native tool
documentation. Preserve selected dependency versions and transitive integrity.

### Non-goals

No live installation, package refresh, Git staging/commit or replacement of the
current native home. Do not resolve a fresh lock merely to conceal its omission.

### Required context

Read `AGENTS.md`, `.gitignore`, `native/npm/package.json`, the existing local
`native/npm/package-lock.json`, `native/toolchain.json`,
`scripts/native/user_tools.py`, `tests/native/check_user_environment.py`,
`docs/native-user-tools.md` and `docs/dependency-automation.md`.

### Execution steps

1. Validate the existing ignored lock against manifest versions, tarball URLs
   and integrity values; compare its hash with available installation evidence.
   Stop if it is missing or mismatched and request the reviewed input.
2. Add a narrowly scoped ignore exception and retain the reviewed lock as a
   reviewable new repository file. Do not stage it; the human owns Git writes.
3. Add a focused check for required input presence and ignore-policy errors.
   Distinguish an intended new unstaged file from published-source proof.
4. Verify the complete install input closure from a source-only disposable
   export containing tracked plus explicitly proposed new source, excluding
   ignored state. After the human commits, require a true `git archive HEAD`
   check before reporting committed-source reproducibility. Do not create an
   alternate dependency resolution or download packages in this fixture.
5. Record the exact lock hash, validation and publication limitation in the
   workspace owner documentation for the next phase's read-only review.

### Implementation notes

The review found only `package.json` in `git ls-tree HEAD native/npm/` while
`.gitignore` ignored every `package-lock.json`. Current-checkout success is
insufficient. Keep checks focused on source closure and actual integrity.

### Validation

Run the focused native unittest suite, manifest check and environment check
documented in workspace. Prove missing/ignored lock rejection and source-only
input completeness without installing tools. Run `git diff --check` and inspect
new-file content and status explicitly.

### Completion criteria

The reviewed lock is included in the proposed source change, no required input
depends on ignored state, and source-only validation passes. Clearly retain
the human commit/export proof as a final integration prerequisite if pending.

## Phase 2: Correct TLS And Kubernetes Target Rejection

### Workspace

.

### Goal

Reject wrong-host ingress certificates and non-loopback Kubernetes authorities
before installation or cluster operations.

### Scope

`scripts/bootstrap/install-imported-ingress-tls.sh`,
`scripts/lib/local-kubernetes-target.sh`, focused negative fixtures and nearest
script/TLS/boundary documentation.

### Non-goals

No CA/key generation, live Secret/trust change, endpoint relocation, TLS bypass
or replacement cluster. Preserve supported local Kind behavior.

### Required context

Read `AGENTS.md`, `scripts/README.md`,
`docs/architecture/autonomous-ai-execution.md`, the local-environment TLS
section, both affected scripts and `tests/native-guest-preflight/`.

### Execution steps

1. Replace the `openssl x509 -checkhost` exit-status gate with chain verification
   that includes `-verify_hostname app.budgetanalyzer.localhost`. Preserve
   validity, key-match, CA and private-key permissions checks.
2. Prove a mismatch is rejected even when `x509 -checkhost` returns zero.
   Include a matching-host positive and assert rejection precedes mutation.
3. Validate the Kubernetes URL's actual authority using a small, strict parser
   or fully anchored grammar. Permit only the intended HTTPS loopback literals
   and localhost with a valid port; reject userinfo, suffix hosts, malformed
   ports, unwanted path/query/fragment and alternative schemes. Account for
   kubeconfig proxy overrides that could redirect requests outside the local
   boundary; do not execute arbitrary kubeconfig auth plugins merely to inspect
   the configuration. Preserve context, cluster, Kind and Ready-node gates.
4. Add negative cases for `https://127.0.0.1:6443@outside.invalid:443`, deceptive
   localhost prefixes, malformed URLs and proxy redirection, and positive
   IPv4/IPv6/localhost cases. Use stubs so no remote request occurs.
5. Update the owner docs and record the original reproductions and focused
   results in the post-migration review section.

### Implementation notes

Target checks prevent accidental remote operations; they are not a hostile
guest-root containment mechanism. Keep that distinction explicit. Avoid a new
general URL framework when a small strict contract suffices.

### Validation

Run Bash syntax and ShellCheck for all modified shell files, focused preflight
and TLS negative fixtures, existing imported-TLS `--validate-only` against the
approved files, and the read-only native runtime preflight. No certificate or
cluster mutation is needed to validate these changes.

### Completion criteria

Both review reproductions fail closed before mutation, valid supported local
inputs still pass, tests cover the actual failure modes, and docs agree.

## Phase 3: Establish One Owner For Guest CA Trust

### Workspace

../workspace

### Goal

Workspace owns human-operated guest system/NSS trust installation and its
read-only verifier, including safe convergence from the two legacy CA files.

### Scope

Native trust installation/verification, focused fixtures and TLS/user-tool
documentation. Keep one managed system CA destination, preferably the existing
workspace `budget-analyzer-local-mkcert.crt` path to minimize installed changes.

### Non-goals

No live system/NSS write, host CA operation, unrelated trust deletion, broad
certificate cleanup or recreation of a provider home.

### Required context

Read `AGENTS.md`, `scripts/native/local_ca.py`, `scripts/native/user_tools.py`,
`docs/local-budget-analyzer-tls.md`, `docs/native-user-tools.md`, focused native
tests and orchestration's imported-TLS installer and TLS owner doc read-only.

### Execution steps

1. Define the single destination and division of responsibilities: workspace
   imports guest OS/NSS trust; orchestration validates files/reconciles Secrets;
   the personal host alone signs browser certificates.
2. Prepare an idempotent human-only convergence path for the exact legacy
   `budget-analyzer-local-ingress-ca.crt` duplicate. Check regular-file status,
   symlinks, ownership and certificate identity before any removal. Preserve
   unrelated roots. If the duplicate differs, stop for explicit fingerprint
   review; do not silently retain stale trust or delete an unexplained root.
3. Test duplicate convergence, unknown-root refusal, idempotence, preserved
   public roots/NSS entries and verifier read-only behavior with disposable
   inputs and mocked system operations. Never test against real trust stores.
4. Document the concrete human installation command and the expected final
   single-file/trust checks. Human installation waits until Phase 4 removes
   orchestration's competing writer and all affected workers have exited.

### Implementation notes

Both legacy files currently contain the same certificate, but a repair must
not assume that future machines or rotations share this state. Cleanup is of
one positively identified duplicate, never the whole trust directory.

### Validation

Run workspace's native safety, manifest and environment checks; compile changed
Python with bytecode under `tmp/`; validate all modified shell files. Prove a
different legacy root cannot be removed by an ordinary unattended invocation.

### Completion criteria

The workspace trust owner has a focused, documented, tested convergence path
and preserves the read-only native ensure/check contract. No live trust changed.

## Phase 4: Remove Orchestration's Duplicate Trust Writer

### Workspace

.

### Goal

Fresh guest bootstrap and renewal use the workspace trust owner, while Tilt
only validates imported files and reconciles the ingress Secret.

### Scope

Guest bootstrap/TLS interfaces, setup and renewal documentation, affected
guardrails and references. Update orchestration ownership and authoring guidance
where the active workflow changes.

### Non-goals

No running `setup.sh`, live trust/Secret mutation, host renewal, cluster reset
or duplication of workspace trust code inside orchestration.

### Required context

Read `AGENTS.md`, `docs/OWNERSHIP.md`, `docs/agents-md-checkstyle.md`,
`setup.sh`, the imported-TLS installer, `Tiltfile`, TLS guardrails, getting-started
and local-environment guides, plus Phase 3's workspace trust owner docs.

### Execution steps

1. Remove the competing system-CA installation implementation. Choose an
   explicit migration for `--install-system-trust`: reject with the canonical
   human command or delegate to the canonical workspace owner only where its
   full identity/prerequisite contract can be satisfied. Do not retain a second
   implementation or silently ignore a requested import.
2. Update the human first-bootstrap/renewal sequence to call the single owner
   at the correct point, preserving all native prerequisites. Keep Tilt free
   of trust installation and certificate generation.
3. Update nearest docs, interface references and guardrails together. Preserve
   host-only renewal and the exact three approved transfer files.
4. Record the combined Phase 3/4 human handoff, including ending workers,
   reviewing/installing workspace changes, checking exactly one managed CA,
   and testing curl/Python/Node/Chromium verified HTTPS to the exact app origin.
   Human acceptance may occur before Phase 6; do not perform it as an agent.

### Implementation notes

The workflow must remain executable from a fresh guest and from the existing
healthy guest. Missing workspace prerequisites require a clear diagnostic,
not a duplicate installer fallback.

### Validation

Run Bash syntax/ShellCheck, focused bootstrap/TLS contract fixtures, relevant
static Tilt guardrails, docs/link checks and diff checks. Do not run destructive
bootstrap or write trust merely to validate orchestration integration.

### Completion criteria

One trust owner serves documented bootstrap/renewal paths, Tilt cannot generate
certificates/import trust, and the human installation handoff is concrete.

## Phase 5: Retire Transitional Workflows And Duplicate Helpers

### Workspace

../workspace

### Goal

Native development is the single documented daily agent workflow, with one
maintained implementation of each retained helper.

### Scope

Retired Mint devcontainer/runtime sources, duplicated helper resources,
README/AGENTS/owner docs, tests and dependency-evidence configuration affected
by removing those sources. Preserve all supported native capabilities.

### Non-goals

No deletion of host/guest Docker data, ignored provider state, user work or
historical acceptance. No removal of an unrelated helper simply because it
formerly shipped in a container. No new image or dependency automation platform.

### Required context

Read `AGENTS.md`, `README.md`, `docs/host-isolation.md`,
`docs/native-tool-inventory.md`, `docs/native-user-tools.md`,
`docs/dependency-automation.md`, `.devcontainer/`, `ai-agent-sandbox/`,
`native/toolchain.json`, native scripts/tests and affected workflows/Renovate
configuration. Consult orchestration's completed acceptance and AGENTS standard.

### Execution steps

1. Inventory every consumer of legacy Dockerfile/Compose/devcontainer files,
   helper resources, prompt/settings/skills and image evidence. Treat the human's
   completed D as runtime-retirement authority; no runtime deletion is needed.
2. Make native resources the canonical source, relocating shared settings or
   skills before removing their old directory. Remove duplicate implementations
   while preserving command behavior and optional proxy separation.
3. Retire obsolete tracked launch/build configurations and their exclusively
   obsolete automation. Preserve unrelated dependency evidence and production
   policy; coordinate owner-doc updates for any repo-local workflow removal.
   Do not leave an image scan/build job pointing at a deleted Dockerfile.
4. Replace Dockerfile-parity assertions with native-manifest and capability
   checks. Avoid replacing one duplicate inventory with another. Verify all
   manifest paths and Dockerfile-era helper capabilities are retained or have
   an explicitly documented retirement.
5. Make native Remote SSH/daily setup primary in README and AGENTS; remove
   instructions to reopen this VM in a container or retain retired Mint Docker.
   Preserve dated evidence as history with a clear current-status pointer.
6. Record native resource/install changes needing human refresh after workers
   stop. Do not run the installer to force the live home to match new source.

### Implementation notes

Prefer deleting obsolete paths and keeping one existing native implementation
over building an abstraction to support a retired runtime. Change tracking and
human Git review make source retirement recoverable; ignored runtime data is
outside this phase's scope.

### Validation

Run native safety/manifest/environment checks, focused helper argument and
behavior tests for changed mappings, shell/Python validation, broken-link and
retired-reference checks. Run actionlint for touched workflows and relevant
dependency configuration validation. No container build or launch is needed.

### Completion criteria

Native commands/capabilities have one maintained source, no active docs or
automation require the retired container, and any required human refresh is
explicitly recorded without claiming it has occurred.

## Phase 6: Prepare The Host Repair And Evidence Handoff

### Workspace

.

### Goal

Turn the confirmed firewall and retirement discrepancies into a narrow,
reviewable host repair contract, and make the next evidence collection safe and
decisive enough for final review.

### Scope

Audit collector/runbook improvements justified by the supplied report, a
concrete host-owned firewall and Docker-retirement handoff, and focused protocol
fixtures needed to test the repaired boundary.

### Non-goals

No host administration from an agent, firewall installation or reload, reboot,
live probes, broad policy rewrite, revived Docker fixture on the retired host,
service logic changes, report publication or claim that VM isolation eliminates
host-client/hypervisor vulnerabilities.

### Required context

Read `AGENTS.md`, `docs/agents-md-checkstyle.md`, `docs/OWNERSHIP.md`,
`docs/runbooks/host-isolation-audit.md`, the collector and its tests, the boundary
contract, the manual plan's D.3 retirement contract, completed migration
acceptance, the dated post-migration report review, relevant workspace results
and the human-provided privately reviewed host evidence. Do not copy report
identifiers or full rule dumps into repository documentation or test fixtures.

### Execution steps

1. Use the dated acceptance-record review as the finding baseline. Preserve its
   distinction between proven policy reachability and unproven delivery: early
   IPv4/IPv6 mDNS/SSDP accepts and broad libvirt port 53/67 accepts are confirmed
   defects; actual guest delivery to Avahi or another listener is not yet
   established. Preserve the positive AppArmor, device and loopback-bind
   evidence without treating it as a firewall pass.
2. Fix the collector's best-effort redaction with synthetic tests. Redact full
   iptables/nft comment values, including the argument after a comment module;
   consistently alias custom domain, network, bridge and tap identifiers while
   preserving their relationships; and preserve CIDR masks and rule semantics.
   Make Docker package collection distinguish an empty installed-package result
   from command failure and account for the discovered Docker engine/CLI,
   containerd and runc package families without publishing unrelated packages.
3. Write the exact human-owned firewall repair contract into the audit runbook.
   Require a root-owned persistent enforcement point that sees input from the
   dedicated VM bridge/tap before both libvirt's `LIBVIRT_INP` accepts and UFW's
   multicast/before-rule accepts in every applicable address family. Prove no
   active path exposed through any installed firewall backend bypasses that
   enforcement point. Default-deny VM-originated host input there while
   allowing only reviewed established replies, gateway-scoped TCP/UDP DNS,
   narrowly formed DHCP and required IPv6 control traffic. Explicitly deny
   mDNS, SSDP and every other unapproved host destination. Another ordinary UFW
   user rule, or a change only to UFW before-rules, is not an acceptable repair.
4. Make the firewall handoff lifecycle-safe. It must use discovered interfaces
   and addresses, coexist with UFW/libvirt without flushing either ruleset,
   remain effective across UFW reload, libvirt network restart and host reboot,
   and fail closed if its persistent policy cannot load. Require root ownership,
   no guest-writable source, syntax validation and read-back of actual hook
   priority/order before human application. Keep LAN/VPN and Internet policy
   outside this repair.
5. Add a D.3 reconciliation checklist for the human. Without starting Docker,
   identify package and containerd consumers, remove only retired Mint Docker
   packages/data and the reviewed isolation helper, service drop-in and UFW
   hook call, then reboot. Final evidence must show no Docker daemon/socket/CLI
   or engine packages, `docker0`, Docker nft/legacy chains, retired runtime data,
   helper or drop-in. Retained containerd/runc requires a named non-Docker
   consumer and must not recreate Docker state.
6. Implement a small explicit host-listener/guest-probe helper only where the
   reviewed topology needs one. It must never alter firewall, routing or
   services; must bind only the selected interface/address; use nonce-bearing
   harmless payloads; refuse occupied ports; stop cleanly; and distinguish a
   positive control, observed ingress/drop counter and receiver non-delivery
   from a missing route, group membership or listener. For occupied mDNS/SSDP
   ports, require a reviewed counter/scoped-capture method rather than sending
   discovery traffic to a real service or stopping that service.
7. Specify the post-repair matrix: applicable unicast TCP/UDP and multicast
   IPv4/IPv6 attempts from the guest, gateway DNS/DHCP and required IPv6
   positives, counter or scoped-ingress attribution, and repeated results after
   reboot. Also require guest verified HTTPS/Internet, host-initiated SSH/Git/
   app HTTPS and read-only guest Docker/Kind/Tilt health. Host Docker-path tests
   are inapplicable after retirement and must be replaced by absence evidence.
8. Validate collector and helper fixtures offline, compile changed Python under
   `tmp/`, run Bash syntax/ShellCheck for changed shell, and run doc/link and
   diff checks. Record the exact human commands, expected outputs, rollback
   boundary and stop conditions without running them. Do not mark the confirmed
   findings repaired in the acceptance record during this phase.

### Implementation notes

The supplied report is enough to design the repair, but it is not evidence that
the repair exists. Prefer one early VM-specific policy boundary over duplicated
exceptions in several generated chains. Its allowlist must be derived from the
actual libvirt network and working flows, especially DHCP and IPv6 control; do
not guess protocol allowances or weaken unrelated host policy. Keep the current
report private and avoid embedding real identifiers in fixtures.

### Validation

Run collector offline tests, any new protocol-helper negative/positive fixtures,
changed-shell Bash/ShellCheck, Python compilation under `tmp/`, plan/doc links
and diff checks. Inspect the generated handoff against the supplied rule order
and D.3 contract. No live host or guest network operation is needed in this
phase.

### Completion criteria

The repository contains tested redaction/package-evidence fixes, a precise
persistent firewall repair contract, a bounded D.3 cleanup checklist and a
controlled post-repair proof matrix. The human can review and execute the
handoff without inventing policy or reviving Docker. The acceptance record still
shows the firewall and retirement findings open.

## Phase 7: Close Host Evidence And Integrated Acceptance

### Workspace

.

### Goal

Review the human-applied host repair and retirement evidence, align remaining
orchestration documentation, and accept only the final verified native boundary.

### Scope

The new privately reviewed host report and paired protocol/reboot results,
remaining native workflow documentation, relevant guest read-only checks and
the distinct post-migration acceptance record.

### Non-goals

No host administration from an agent, report publication, repeated destructive
migration, revived host Docker, unrelated firewall hardening, service logic
changes, hidden credentials or claim that the VM removes host-client/hypervisor
risk.

### Required context

Read `AGENTS.md`, `docs/agents-md-checkstyle.md`, `docs/OWNERSHIP.md`,
`docs/runbooks/host-isolation-audit.md`, the boundary contract, Phase 6's
reviewed handoff and tests, the manual plan's D.3 contract, completed migration
acceptance, relevant workspace results and the human-provided post-repair
evidence. The human must have privately reviewed the candidate report before it
is made available; request only narrow redacted follow-up evidence when needed.

### Execution steps

1. Confirm Phase 1's reviewed lock is committed and survives source-only Git
   export through human evidence; inspect sibling source read-only. Confirm
   human native refresh/trust convergence and HTTPS results for Phases 3–5.
2. Trace the post-repair IPv4/IPv6 input path through every active nft and
   compatibility backend. Prove the VM-specific enforcement point precedes and
   cannot be bypassed by libvirt DNS/DHCP or UFW multicast accepts, permits only
   the reviewed allowlist, and remains active after UFW/libvirt lifecycle events
   and the final reboot. Missing or redacted-away decisive evidence requires a
   narrowly specified follow-up, never a guessed PASS.
3. Review paired applicable TCP/UDP/multicast IPv4/IPv6 results. Require
   nonce-bearing positive controls plus scoped ingress/drop attribution and
   receiver non-delivery; a timeout, zero counter without proven routing, or
   host-wide multicast counter is NOT TESTED. Confirm gateway DNS/DHCP, required
   IPv6 behavior, guest verified HTTPS/Internet and host-initiated SSH/Git/app
   HTTPS still work.
4. Reconcile D.3 after reboot. Require absence of the host Docker daemon/socket/
   CLI and engine packages, `docker0`, Docker chains in every installed backend,
   retired runtime data, the isolation helper/drop-in and its UFW hook call.
   Confirm any retained containerd/runc consumer is explicit and unrelated.
   Do not restart Docker or infer absence from inactive units alone.
5. Reconfirm the running VM's enforcing dynamic AppArmor label, selected
   dedicated network, no filesystem/host-device passthrough, and loopback-only
   app HTTPS/VNC listeners. Treat these as required positive boundary evidence,
   not substitutes for packet-policy proof.
6. Finish orchestration native-only daily guidance and cross-links, retaining
   human-only fresh bootstrap and historical migration records. Remove active
   transitional instructions; preserve the immutable migration execution plan.
7. Run the read-only native runtime preflight and focused guest checks justified
   by actual runtime changes, with exact local target gates. Record revisions,
   commands, timestamps, attribution, failures, untested cases and residual
   host-client/hypervisor risk. Update post-migration acceptance only for
   independently reviewed or explicitly attributed human results.

### Implementation notes

The original migration acceptance remains historical operator attestation. The
new report resolves its contradictory snapshot only if it proves the repaired
state after reboot. Do not copy complete firewall dumps or identifying values
into the acceptance record; record the relevant order, behavior and attribution.

### Validation

Run focused collector/helper tests when Phase 6 code changed, plan/doc links,
diff checks and the read-only native runtime preflight after human refresh.
Review actual host audit and paired-reboot results through the runbook. Run
broader guest smoke checks only for affected runtime behavior and only after the
exact target gates pass.

### Completion criteria

All confirmed review defects are closed, trust ownership and helpers are
consolidated, obsolete active guidance is gone, fresh Git source is complete,
human live installation has passed, and post-reboot host firewall/confinement/
protocol/retirement evidence supports the documented boundary. The new review
record lists actual coverage and residual risks; original migration acceptance
remains completed and unchanged in meaning.
