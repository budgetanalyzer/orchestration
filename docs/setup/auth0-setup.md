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

These Auth0 tenant settings control token lifetimes and session behavior that the Session Gateway architecture depends on. Default Auth0 values make security features ineffective — a 24-hour access token never hits the 10-minute refresh threshold, and a persistent 3-day Auth0 session lets users silently re-authenticate after the app session expires.

### API Settings

**Applications → APIs → budget-analyzer-api** (the API matching your `IDP_AUDIENCE`):

| Setting | Default | Recommended | Why |
|---------|---------|-------------|-----|
| Maximum Access Token Lifetime | 86400 (24 hrs) | 900 (15 min) | Enables revocation detection — Session Gateway's proactive refresh fires at the 10-min remaining threshold during heartbeat. A 24-hour token never reaches that threshold during any realistic session, making `IdpTokenRefreshClient` dead code. |
| Implicit/Hybrid Flow Lifetime | 7200 | Irrelevant | The application uses `authorization_code` with PKCE. This setting has no effect. |

### Application Settings

**Applications → Budget Analyzer → Settings**:

| Setting | Default | Recommended | Why |
|---------|---------|-------------|-----|
| ID Token Expiration | 36000 (10 hrs) | 3600 (1 hr) | Only used once at login for identity claims. 10 hours is needlessly generous. |
| Idle Refresh Token Lifetime | 1296000 (15 days) | 3600 (1 hr) | Stale refresh tokens should not linger for weeks. |
| Max Refresh Token Lifetime | 2592000 (30 days) | 28800 (8 hrs) | Hard ceiling matching a workday. |
| Rotation | Enabled | Keep | Required — Session Gateway expects new refresh tokens on each use. |
| Overlap | 0 | Keep | No overlap window between old and new refresh tokens. |

### Session Settings

**Settings → Advanced → Session Expiration**:

| Setting | Default | Recommended | Why |
|---------|---------|-------------|-----|
| Default Session Policy | Persistent | Non-persistent | Closing the browser should kill the Auth0 session. See rationale below. |
| Idle Session Lifetime | 4320 min (3 days) | 15 min | Match the app session. When the app session expires from inactivity, the Auth0 session should also be dead so the user sees a login form, not silent re-authentication. |
| Maximum Session Lifetime | 10080 min (7 days) | 480 min (8 hrs) | Hard ceiling — forces re-authentication once per workday. |

**Why session policy matters for a financial application:**

With "Persistent" and a 3-day idle timeout, the app's 15-minute session expiration gives a false sense of security:

1. User's app session expires (15 min idle, Redis key gone)
2. User clicks Login
3. Auth0 still has a live session (3-day idle, persistent cookie survived browser close)
4. Auth0 silently re-authenticates — no password prompt
5. User gets a new app session without proving they know the password

Someone who walks away from an unlocked browser gets back in without credentials as long as the Auth0 session is alive. Setting the policy to non-persistent with a 15-minute idle timeout closes this gap. The `/v2/logout` call in Session Gateway's `LogoutController` already kills the Auth0 session on explicit logout — these settings are the safety net for when logout doesn't happen cleanly (browser crash, tab close, session timeout).

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
