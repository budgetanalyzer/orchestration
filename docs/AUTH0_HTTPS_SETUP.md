# Auth0 Configuration for Local HTTPS Development

## Overview

After implementing local HTTPS setup, you need to update your Auth0 application configuration to allow the new HTTPS URLs.

## Required Changes

Access your Auth0 Dashboard: https://manage.auth0.com/

Navigate to: **Applications → [Your Application] → Settings**

### 1. Allowed Callback URLs

**Purpose**: URLs where Auth0 can redirect users after authentication

**Add the following URL**:
```
https://app.budgetanalyzer.localhost/login/oauth2/code/auth0
```

**Migration Strategy**: Keep both HTTP and HTTPS URLs during transition:
```
https://app.budgetanalyzer.localhost/login/oauth2/code/auth0
http://localhost:8081/login/oauth2/code/auth0
```

Once HTTPS is verified working, you can remove the HTTP URL.

### 2. Allowed Logout URLs

**Purpose**: URLs where Auth0 can redirect users after logout

**Add the following URL**:
```
https://app.budgetanalyzer.localhost/
```

**Migration Strategy**: Keep both during transition:
```
https://app.budgetanalyzer.localhost/
http://localhost:8081/
```

### 3. Allowed Web Origins

**Purpose**: URLs that can make requests to Auth0

**Add the following URL**:
```
https://app.budgetanalyzer.localhost
```

**Migration Strategy**: Keep both during transition:
```
https://app.budgetanalyzer.localhost
http://localhost:8081
```

### 4. Allowed Origins (CORS)

**Purpose**: Cross-Origin Resource Sharing for Auth0 API calls

**Add the following URL**:
```
https://app.budgetanalyzer.localhost
```

**Migration Strategy**: Keep both during transition:
```
https://app.budgetanalyzer.localhost
http://localhost:8081
```

## Complete Configuration Example

After adding all URLs, your Auth0 application settings should look like this:

**Allowed Callback URLs**:
```
https://app.budgetanalyzer.localhost/login/oauth2/code/auth0,
http://localhost:8081/login/oauth2/code/auth0
```

**Allowed Logout URLs**:
```
https://app.budgetanalyzer.localhost/,
http://localhost:8081/
```

**Allowed Web Origins**:
```
https://app.budgetanalyzer.localhost,
http://localhost:8081
```

**Allowed Origins (CORS)**:
```
https://app.budgetanalyzer.localhost,
http://localhost:8081
```

## Testing the Configuration

After updating Auth0:

1. Access `https://app.budgetanalyzer.localhost`
2. Click the login button
3. You should be redirected to Auth0
4. After authenticating, you should be redirected back to `https://app.budgetanalyzer.localhost`
5. Check browser DevTools → Application → Cookies
6. Verify the SESSION cookie has the `Secure` flag ✅

## Troubleshooting

### Redirect URI Mismatch Error

If you see an error like:
```
The redirect URI is wrong. You sent https://app.budgetanalyzer.localhost/login/oauth2/code/auth0
```

**Solution**: Make sure you added the HTTPS callback URL to "Allowed Callback URLs" in Auth0 settings.

### CORS Errors

If you see CORS errors in the browser console:

**Solution**: Make sure you added `https://app.budgetanalyzer.localhost` to both "Allowed Web Origins" and "Allowed Origins (CORS)" in Auth0 settings.

## Cleanup (Optional)

Once you've verified HTTPS is working correctly and you no longer need HTTP access:

1. Remove the HTTP URLs from all Auth0 settings:
   - Remove `http://localhost:8081/login/oauth2/code/auth0`
   - Remove `http://localhost:8081/`
   - Remove `http://localhost:8081`

2. This enforces HTTPS-only access for your local development environment

## Additional Resources

- [Auth0 Application Settings Documentation](https://auth0.com/docs/get-started/dashboard/application-settings)
- [Auth0 Callback URL Documentation](https://auth0.com/docs/get-started/applications/application-settings#application-uris)
- [Local HTTPS Setup Plan](../docs/plans/local-https-setup.md)
