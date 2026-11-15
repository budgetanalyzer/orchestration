# Transaction date cap uses the JVM default time zone

- **Severity:** Low (latent; both services run in UTC today)
- **Owner:** transaction-service
- **Status:** Open
- **Source:** 2026-11-15 review of the Redis session/cache split, while choosing
  the exchange-rate end-date cap

## Problem

transaction-service rejects transaction dates more than one day in the future,
but it takes "today" from `LocalDate.now()`, which uses the JVM default time
zone:

- `TransactionService.maxAllowedTransactionDate()`, used by single-transaction
  validation and batch import validation;
- `ConfigurableCsvStatementExtractor.validateDateNotTooFarInFuture()`, used by
  CSV statement import.

The service already defines a UTC `Clock` bean in `TransactionServiceConfig`,
and `PreviewImportTokenService` uses it. These date checks do not.

currency-service takes "today" from an injected UTC `Clock`. The Redis split
remediation caps the exchange-rate `endDate` at UTC tomorrow so that a
transaction dated at transaction-service's limit still gets a rate. The two
limits agree only because both containers happen to run in UTC. Neither
deployment sets `TZ` or `-Duser.timezone`. On 2026-11-15, `date` in the
transaction-service pod reported `UTC +0000`. Nothing pins this.

If transaction-service ran in a zone ahead of UTC, it could accept a date two
days after the UTC date. currency-service would cap the range at UTC tomorrow,
and the web client would find no exchange rate for that transaction. In a zone
behind UTC, the transaction limit would be stricter than documented.

The tests also read the wall clock. For example, `LocalDate.now().plusDays(2)`
appears in `TransactionServiceIntegrationTest`. No test checks the exact
boundary at a fixed time: tomorrow accepted, the day after rejected.

## Proposed fix

- Inject the existing `Clock` into `TransactionService` and use
  `LocalDate.now(clock)`.
- Pass the same `Clock` to `ConfigurableCsvStatementExtractor`, which
  `StatementExtractorRegistry` and `CsvStatementFormatWizardService` construct
  directly, and use it there too.
- Add fixed-clock boundary tests for single-transaction validation, batch import
  and CSV extraction: tomorrow (UTC) is accepted and the day after is rejected.
- Add "(UTC)" to the transaction date rule in transaction-service
  `docs/api/README.md`.
- Keep the one-day allowance and the UTC basis. The currency-service end-date
  cap depends on both.

## Acceptance

- `rg -n "LocalDate\.now\(\)" src/main/java` in transaction-service returns
  nothing.
- The boundary tests pass regardless of the JVM default zone, including under
  `TZ=Pacific/Kiritimati` (UTC+14) and `TZ=Pacific/Pago_Pago` (UTC-11).
