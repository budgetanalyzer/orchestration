# Plan: RabbitMQ DLX Permission Repair

Date: 2026-05-12
Status: Implemented

Related documents:

- `Tiltfile`
- `deploy/manifests/phase-5/rabbitmq-definitions.template.json`
- `scripts/smoketest/verify-phase-1-credentials.sh`
- `docs/development/local-environment.md`
- `docs/runbooks/tilt-debugging.md`
- `deploy/README.md`
- `../currency-service/src/main/resources/application.yml`

## Diagnosis

The observed failure is a RabbitMQ authorization failure during Spring AMQP
resource declaration, not an HTTP authorization failure. The browser request
successfully updates the currency with HTTP 200, then `currency-service`
publishes the follow-up exchange-rate import message through Spring Cloud
Stream.

Spring Cloud Stream has a consumer binding:

- destination: `exchange-rate.import.requested`
- group: `exchange-rate-import-service`
- `auto-bind-dlq: true`
- `republish-to-dlq: true`

That creates these broker resources:

- exchange: `exchange-rate.import.requested`
- queue: `exchange-rate.import.requested.exchange-rate-import-service`
- dead-letter exchange: `DLX`
- dead-letter queue:
  `exchange-rate.import.requested.exchange-rate-import-service.dlq`
- binding from `DLX` to the DLQ

The current `currency-service` RabbitMQ permission regex allows `DLX` in
`configure` and `write`, but not in `read`:

```text
read = ^(exchange-rate\.import\.requested|exchange-rate\.import\.requested\.exchange-rate-import-service(\.dlq)?)$
```

RabbitMQ checks `queue.bind` as `write` on the target queue and `read` on the
source exchange. Because the DLQ bind uses `DLX` as the source exchange,
RabbitMQ rejects the bind with:

```text
ACCESS_REFUSED - read access to exchange 'DLX' in vhost '/' refused for user 'currency-service'
```

## Evidence

Static repo state:

- `Tiltfile` local boot-time definitions omit `DLX` from the service user's
  `read` regex.
- `deploy/manifests/phase-5/rabbitmq-definitions.template.json` has the same
  omission, so OCI secret material generated from the checked-in template would
  carry the same bug.
- `scripts/smoketest/verify-phase-1-credentials.sh` checks the main service
  queue but does not assert `DLX` read access or the DLQ queue permission set.

Live clean Tilt state:

- `rabbitmqctl list_permissions -p /` shows `DLX` in `configure` and `write`,
  but not `read`, for `currency-service`.
- `rabbitmqctl list_exchanges -p /` shows `DLX` exists.
- `rabbitmqctl list_queues -p /` shows the service queue and DLQ exist.
- `rabbitmqctl list_bindings -p /` does not show the expected `DLX` to DLQ
  binding, consistent with the bind failure.
- RabbitMQ logs show only the `DLX` read denial for `currency-service` in the
  inspected window.

No stale `currency.created` exchange or queue appeared in the live broker
resource list.

## Change Plan

1. Update the `currency-service` RabbitMQ `read` regex in `Tiltfile` to include
   `DLX`:

   ```text
   ^(exchange-rate\.import\.requested|exchange-rate\.import\.requested\.exchange-rate-import-service(\.dlq)?|DLX)$
   ```

2. Make the same change in
   `deploy/manifests/phase-5/rabbitmq-definitions.template.json` so local
   Tilt/Kind and OCI/k3s stay aligned.

3. Tighten `scripts/smoketest/verify-phase-1-credentials.sh` so the verifier
   catches the full Spring Cloud Stream resource contract:

   - main exchange matches `configure`, `write`, and `read`
   - main queue matches `configure`, `write`, and `read`
   - DLQ queue matches `configure`, `write`, and `read`
   - `DLX` matches `configure`, `write`, and `read`
   - `amq.default` still matches `write`
   - old `currency.created` exchange and queues do not match any service-user
     permission regex

4. Update the docs that describe the RabbitMQ allow-list:

   - `docs/development/local-environment.md`
   - `deploy/README.md`
   - `docs/runbooks/tilt-debugging.md` if adding the current-cluster recovery
     notes below is useful for operators

5. Treat the current live-cluster repair as recovery, not the durable fix.
   Because RabbitMQ imports definitions at boot against broker state, operators
   have two acceptable local recovery choices after the repo fix:

   - recreate the local RabbitMQ PVC and trigger the RabbitMQ Tilt resource, or
   - run a one-time `rabbitmqctl set_permissions` with the corrected regex and
     restart `currency-service` so cached authorization decisions and AMQP
     channels are refreshed.

   OCI should be updated by refreshing the
   `budget-analyzer-rabbitmq-definitions` Vault secret from the corrected
   template before applying a matching infrastructure reconcile.

## Verification

After implementation:

1. Validate the shell script changes:

   ```bash
   bash -n scripts/smoketest/verify-phase-1-credentials.sh
   shellcheck scripts/smoketest/verify-phase-1-credentials.sh
   ```

2. Run the focused credential and permission verifier:

   ```bash
   ./scripts/smoketest/verify-phase-1-credentials.sh
   ```

3. Confirm live broker permissions include `DLX` in `read`:

   ```bash
   kubectl exec -n infrastructure statefulset/rabbitmq -- \
     rabbitmqctl list_permissions -p /
   ```

4. Reproduce the user flow that updates an enabled currency and confirm:

   - no `ACCESS_REFUSED` appears in `currency-service` logs
   - no `access_refused` appears in RabbitMQ logs
   - `rabbitmqctl list_bindings -p /` shows a binding from `DLX` to
     `exchange-rate.import.requested.exchange-rate-import-service.dlq`

## Open Questions

- None for the immediate fix. The needed change is an allow-list correction for
  an existing Spring Cloud Stream DLQ contract, not a service logic change.
