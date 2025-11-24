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

### Application URIs

Scroll down to **Application URIs** and configure:

**Allowed Callback URLs**:
```
https://app.budgetanalyzer.localhost/login/oauth2/code/auth0
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

The identifier becomes your `AUTH0_AUDIENCE` value. The default in `.env.example` is already set to `https://api.budgetanalyzer.org`.

## 5. Final .env Configuration

Your `.env` file should look like:

```bash
# Auth0 Configuration
AUTH0_ISSUER_URI=https://your-tenant.us.auth0.com/
AUTH0_CLIENT_ID=your-client-id-here
AUTH0_CLIENT_SECRET=your-client-secret-here

# Optional - defaults work for most setups
# AUTH0_AUDIENCE=https://api.budgetanalyzer.org
```

## Troubleshooting

### "Invalid callback URL" error

- Verify **Allowed Callback URLs** exactly matches: `https://app.budgetanalyzer.localhost/login/oauth2/code/auth0`
- Check for trailing slashes or typos

### "Unauthorized" after login

- Ensure the API audience is configured correctly
- Verify `AUTH0_ISSUER_URI` ends with `/`

### Token validation failures

- Check the Token Validation Service logs: `kubectl logs -n budget-analyzer deployment/token-validation-service`
- Ensure JWKS endpoint is accessible from your cluster

## Security Notes

- Never commit `.env` to version control
- Use different Auth0 applications for dev/staging/prod
- Rotate client secrets periodically
