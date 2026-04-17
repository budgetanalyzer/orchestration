# Auth0 Production Settings for OCI Demo

**Date:** 2026-04-17
**Status:** Recommended settings for Phase 5 Chunk 1 Step 1 and later hostname work
**Related plan:** [oracle-cloud-deployment-plan.md](./oracle-cloud-deployment-plan.md)

This note captures the recommended Auth0 configuration for the OCI demo and the
matching non-secret `instance.env` values so the deployment work can resume
without re-deriving the same decisions.

It now reflects the current Auth0 Free-tier constraint that only one tenant is
included. The practical layout on Free is:

- one US Auth0 tenant
- one tenant-scoped custom domain
- one demo browser application
- one localhost development browser application
- one shared API registration

## Recommended Public Domains

- Demo application: `demo.budgetanalyzer.org`
- Auth0 custom domain: `auth.budgetanalyzer.org`
- API audience identifier: `https://api.budgetanalyzer.org`

Leave the observability hostnames blank for now unless those UIs are being
intentionally exposed in Phase 10/11.

## Recommended `instance.env` Values

Set these values in `~/.config/budget-analyzer/instance.env`:

```bash
DEMO_DOMAIN=demo.budgetanalyzer.org
GRAFANA_DOMAIN=
KIALI_DOMAIN=
JAEGER_DOMAIN=

AUTH0_CLIENT_ID=<production-regular-web-app-client-id>
AUTH0_ISSUER_URI=https://auth.budgetanalyzer.org/
IDP_AUDIENCE=https://api.budgetanalyzer.org
IDP_LOGOUT_RETURN_TO=https://demo.budgetanalyzer.org/peace
```

Notes:

- `AUTH0_CLIENT_SECRET` does not belong in `instance.env`; it stays in OCI Vault
  as `budget-analyzer/auth0-client-secret`.
- `AUTH0_ISSUER_URI` must be the same value later used by
  `scripts/ops/render-istio-egress-config.sh` in Phase 9 Step 2.
- `IDP_AUDIENCE` stays `https://api.budgetanalyzer.org`. The audience does not
  change when Auth0 moves to a custom domain.

## Auth0 Free-Tier Layout

Auth0 Free currently includes:

- `1` tenant
- `1` custom domain

That means the workable layout is one tenant with two applications:

- `Budget Analyzer Demo` - the production/demo browser app
- `Budget Analyzer Dev` - the localhost browser app

The custom domain is tenant-scoped, not application-scoped. On Free, you do
not get one custom domain per app.

For this repo, the recommended split is:

- Demo app uses the tenant custom domain:
  `https://auth.budgetanalyzer.org/`
- Local dev app uses the tenant canonical Auth0 domain:
  `https://<your-tenant>.us.auth0.com/`

This keeps the public demo branded while avoiding unnecessary coupling between
demo and localhost browser SSO behavior.

If you later move off Free and gain multiple tenants, a separate development
tenant is still the cleaner long-term setup.

## Recommended Auth0 Tenant Setup

For the single free-tier tenant:

- Region: US
- Custom domain: `auth.budgetanalyzer.org`
- Certificate mode: `Auth0-managed certificates`
- Browser application type: `Regular Web Application`
- Do not use an SPA application for Session Gateway's server-side browser flow

Auth0 Free requires credit-card verification before custom domains can be used.

## Recommended Demo Application Settings

Create one regular web application for the demo browser flow and set:

- `Application Name`: `Budget Analyzer Demo`
- `Application Login URI`: `https://demo.budgetanalyzer.org/login`
- `Allowed Callback URLs`:
  `https://demo.budgetanalyzer.org/login/oauth2/code/idp`
- `Allowed Logout URLs`:
  `https://demo.budgetanalyzer.org/peace`
- `Allowed Web Origins`:
  `https://demo.budgetanalyzer.org`
- `ID Token Expiration`: `3600` seconds

Use this app's client ID in production `instance.env`.

## Recommended Local Development Application Settings

Create a second regular web application for localhost development and set:

- `Application Name`: `Budget Analyzer Dev`
- `Application Login URI`: `https://app.budgetanalyzer.localhost/login`
- `Allowed Callback URLs`:
  `https://app.budgetanalyzer.localhost/login/oauth2/code/idp`
- `Allowed Logout URLs`:
  `https://app.budgetanalyzer.localhost/peace`
- `Allowed Web Origins`:
  `https://app.budgetanalyzer.localhost`
- `ID Token Expiration`: `3600` seconds

Recommended local `.env` values for the dev app:

```bash
AUTH0_CLIENT_ID=<localhost-dev-regular-web-app-client-id>
AUTH0_ISSUER_URI=https://<your-tenant>.us.auth0.com/
IDP_AUDIENCE=https://api.budgetanalyzer.org
IDP_LOGOUT_RETURN_TO=https://app.budgetanalyzer.localhost/peace
```

This doc keeps production on the custom domain and localhost dev on the
canonical tenant domain.

## Shared API Settings

Create one shared API registration in the same tenant and set:

- `Name`: `Budget Analyzer API`
- `Identifier`: `https://api.budgetanalyzer.org`
- `Signing Algorithm`: `RS256`
- `Maximum Access Token Lifetime`: `900` seconds
- `Allow Offline Access`: off

The API identifier is only an identifier. Auth0 does not call that URL.

Leave refresh-token and offline-access features off for now:

- No refresh-token rotation
- No refresh-token expiration configuration
- No offline access requirement for the browser flow

## Recommended Auth0 Session Settings

Under tenant session expiration settings, use:

- Session policy: `Non-persistent`
- Idle session lifetime: `15` minutes
- Maximum session lifetime: `480` minutes

If the dashboard shows separate persistent and non-persistent values, set the
persistent values to the same numbers to avoid drift.

## Session and SSO Implications

### What is shared in a single tenant

Auth0 documents that all users in a single tenant are shared between that
tenant's applications. Auth0 also documents that SSO works by the authorization
server setting an SSO cookie and reusing that session on later logins.

Practical effect:

- The demo app and the localhost app share the same underlying Auth0 user pool.
- If both apps use the same Auth0 issuer host, the user can be silently
  authenticated across both apps by the Auth0 SSO session.

### What is not shared in the recommended split

This document recommends:

- demo uses `https://auth.budgetanalyzer.org/`
- localhost dev uses `https://<your-tenant>.us.auth0.com/`

In that split, the browser-side Auth0 cookies are expected to stay separate by
host. Auth0 documents that authentication cookies are sent to the custom host
name when using a custom domain, and that enabling a custom domain invalidates
existing sessions created on the canonical tenant domain once you switch to the
custom domain.

Inference from those docs:

- demo login should reuse the Auth0 session for the demo app
- localhost login should reuse the Auth0 session for the localhost app
- demo and localhost should not behave like one shared browser SSO cookie jar
  when they use different issuer hosts

If you intentionally point both apps at the same issuer host, expect SSO
sharing between them.

## First-Login User Sync Implications

This repo's first-login sync path is keyed by the identity-provider subject,
not by email:

- `session-gateway` calls
  `GET /internal/v1/users/{idpSub}/permissions?email=...&displayName=...`
- `permission-service` creates the user on first login and updates the same
  user on later logins, keyed by `idpSub`

Auth0 documents that `user_id` is guaranteed unique within a tenant. In
OIDC-based flows, the user-facing `sub` claim maps to that stable user identity
within the tenant.

Practical effect:

- Using one Auth0 tenant for both demo and localhost does not break the
  permission-service first-login creation path.
- If the same human logs into demo and localhost through the same tenant and
  same connection, the same Auth0 identity should produce the same `idpSub`.
- Each environment still has its own local database, so the first login in demo
  and the first login in localhost create their own local user rows in their
  respective environments.
- If both apps ever point at the same backend environment, the sync path should
  converge on one local user row instead of creating duplicates, because it is
  keyed by `idpSub`.

Operational caution:

- Keep the same Auth0 connection strategy across demo and localhost if you want
  the same human to resolve to the same Auth0 subject.
- If you later move demo and localhost to different Auth0 tenants, the same
  human may not have the same Auth0 `user_id` across those tenants.

## Click Path Summary

### Custom Domain

1. Open the Auth0 tenant in Auth0.
2. If Auth0 blocks custom domains, add a payment method for verification.
3. Go to `Branding` -> `Custom Domains`.
4. Click `+ Add custom domain`.
5. Enter `auth.budgetanalyzer.org`.
6. Choose `Auth0-managed certificates`.
7. Save.
8. Copy the CNAME target Auth0 shows.
9. Create the matching DNS `CNAME` record for `auth.budgetanalyzer.org`.
10. Return to Auth0 and verify the domain.

### Demo Browser Application

1. Go to `Applications` -> `Applications`.
2. Click `Create Application`.
3. Name it `Budget Analyzer Demo`.
4. Choose `Regular Web Applications`.
5. Open `Settings`.
6. Set the login, callback, logout, and web-origin values from this document.
7. Set `ID Token Expiration` to `3600`.
8. Save changes.
9. Copy the generated `Client ID` into `instance.env`.
10. Copy the generated `Client Secret` into OCI Vault, not into the repo or
    `instance.env`.

### Local Dev Browser Application

1. Go to `Applications` -> `Applications`.
2. Click `Create Application`.
3. Name it `Budget Analyzer Dev`.
4. Choose `Regular Web Applications`.
5. Open `Settings`.
6. Set the localhost login, callback, logout, and web-origin values from this
   document.
7. Set `ID Token Expiration` to `3600`.
8. Save changes.
9. Put this app's `Client ID` in local `.env`, not in production `instance.env`.
10. Keep local dev on the canonical tenant issuer unless you explicitly want
    cross-app SSO with the public demo.

### API

1. Go to `Applications` -> `APIs`.
2. Click `Create API`.
3. Name it `Budget Analyzer API`.
4. Set the identifier to `https://api.budgetanalyzer.org`.
5. Choose `RS256`.
6. Save.
7. Set `Maximum Access Token Lifetime` to `900`.
8. Leave offline access off.
9. Save changes.

### Tenant Session Expiration

1. Go to `Tenant Settings`.
2. Switch to `Advanced`.
3. Find `Session Expiration`.
4. Set the session policy to `Non-persistent`.
5. Set idle lifetime to `15` minutes.
6. Set maximum lifetime to `480` minutes.
7. Save changes.

## Deployment Follow-Through

Once the tenant and DNS are ready:

1. Put the chosen non-secret values into
   `~/.config/budget-analyzer/instance.env`.
2. Store `AUTH0_CLIENT_SECRET` in OCI Vault as
   `budget-analyzer/auth0-client-secret`.
3. In Phase 5, render the production `session-gateway-idp-config` from those
   non-secret values.
4. In Phase 9 Step 2, render and apply Istio egress from the same
   `AUTH0_ISSUER_URI`.

If the Auth0 custom domain or demo hostname changes later, update
`AUTH0_ISSUER_URI`, `IDP_LOGOUT_RETURN_TO`, and the application URLs together,
then rerender the production IDP config and the Istio egress config in the same
change.
