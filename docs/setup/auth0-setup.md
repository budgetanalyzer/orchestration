# Auth0 Setup Guide

This guide walks you through configuring Auth0 for Budget Analyzer.

## 1. Create Auth0 Account

1. Go to https://auth0.com and sign up for a free account
2. Choose your tenant region (e.g., US)

## 2. Create Application

1. Navigate to **Applications → Applications**
2. Click **Create Application**
3. Name: `Budget Analyzer` (or any name you prefer)
4. Type: **Regular Web Applications**
5. Click **Create**

## 3. Configure Application Settings

In your application settings:

### Basic Information

Copy these values to your `.env` file:

| Auth0 Setting | .env Variable |
|---------------|---------------|
| Domain | `AUTH0_ISSUER_URI` (add `https://` prefix and `/` suffix) |
| Client ID | `AUTH0_CLIENT_ID` |
| Client Secret | `AUTH0_CLIENT_SECRET` |

**Example**: If your Domain is `dev-abc123.us.auth0.com`, set:
```
AUTH0_ISSUER_URI=https://dev-abc123.us.auth0.com/
```

That same `AUTH0_ISSUER_URI` value also drives the Istio Auth0 egress allowlist
through `scripts/dev/render-istio-egress-config.sh`. If you change tenants,
re-render or reapply the egress config so `session-gateway-idp-config` and the
Istio allowlist stay aligned.

### Application URIs

Scroll down to **Application URIs** and configure:

**Allowed Callback URLs**:
```
https://app.budgetanalyzer.localhost/login/oauth2/code/idp
```

**Allowed Logout URLs**:
```
https://app.budgetanalyzer.localhost/peace
```

**Allowed Web Origins**:
```
https://app.budgetanalyzer.localhost
```

Click **Save Changes** at the bottom.

## 4. Create API (Optional but Recommended)

For proper JWT audience configuration:

1. Navigate to **Applications → APIs**
2. Click **Create API**
3. Name: `Budget Analyzer API`
4. Identifier: `https://api.budgetanalyzer.org`
5. Click **Create**

The identifier becomes your `IDP_AUDIENCE` value. The default in `.env.example`
is already set to `https://api.budgetanalyzer.org`.

## 5. Final .env Configuration

Your `.env` file should look like:

```bash
# Auth0 Configuration
AUTH0_ISSUER_URI=https://your-tenant.us.auth0.com/
AUTH0_CLIENT_ID=your-client-id-here
AUTH0_CLIENT_SECRET=your-client-secret-here

# Optional - defaults work for most setups
# IDP_AUDIENCE=https://api.budgetanalyzer.org
# IDP_LOGOUT_RETURN_TO=https://app.budgetanalyzer.localhost/peace
```

The repo ships a checked-in fallback `ConfigMap/session-gateway-idp-config` for
non-Tilt applies. Tilt overwrites `AUTH0_ISSUER_URI`, `AUTH0_CLIENT_ID`,
`IDP_AUDIENCE`, and `IDP_LOGOUT_RETURN_TO` from `.env`, keeps only
`AUTH0_CLIENT_SECRET` in `Secret/auth0-credentials`, and renders the Auth0
egress `ServiceEntry`, egress `Gateway`, and `VirtualService` from the same
URI. Production deployers should preserve that same contract: whichever system
creates the Session Gateway IDP config must also feed the same
`AUTH0_ISSUER_URI` into the egress rendering/apply step.

## 6. Security Configuration

Default Auth0 tenant settings undermine Session Gateway's security features. A 24-hour access token never hits the refresh threshold, so revocation detection through `IdpTokenRefreshClient` never fires. A persistent 3-day Auth0 session lets users silently re-authenticate after the app's 15-minute session expires — someone at an unlocked browser gets back in without credentials.

The recommended Auth0 dashboard values (token lifetimes, refresh token rotation, tenant session policy) are maintained alongside Session Gateway's runtime defaults:

→ **[Recommended Auth0 Settings](https://github.com/budgetanalyzer/session-gateway/blob/main/docs/auth0-settings.md)** — the authoritative reference, tied to `SESSION_TTL_SECONDS`, `SESSION_REFRESH_THRESHOLD_SECONDS`, and heartbeat cadence.

## Troubleshooting

### "Invalid callback URL" error

- Verify **Allowed Callback URLs** exactly matches: `https://app.budgetanalyzer.localhost/login/oauth2/code/idp`
- Check for trailing slashes or typos

### "Unauthorized" after login

- Ensure the API audience is configured correctly
- Verify `AUTH0_ISSUER_URI` ends with `/`

## Security Notes

- Never commit `.env` to version control
- Use different Auth0 applications for dev/staging/prod
- Rotate client secrets periodically
