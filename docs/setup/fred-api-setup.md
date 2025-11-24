# FRED API Setup Guide

The Federal Reserve Economic Data (FRED) API provides exchange rate data for the Currency Service.

## 1. Get API Key

1. Go to https://fred.stlouisfed.org/docs/api/api_key.html
2. Click **Request API Key**
3. Create an account or sign in
4. Fill out the request form:
   - App Description: `Budget Analyzer - Personal finance app`
   - Accept terms of service
5. Click **Request API Key**
6. Copy the API key from the confirmation page (also sent via email)

## 2. Configure .env

Add your API key to `.env`:

```bash
FRED_API_KEY=your-api-key-here
```

## Usage

The Currency Service uses this API to fetch:
- USD/EUR exchange rates
- Other currency pair conversions
- Historical exchange rate data

## Rate Limits

FRED API free tier limits:
- 120 requests per minute
- No daily limit

The Currency Service caches responses to minimize API calls.

## Troubleshooting

### "API key is invalid" error

- Verify the key is copied correctly (no extra spaces)
- Check that the key is active in your FRED account

### Exchange rate data not updating

- Check Currency Service logs: `kubectl logs -n budget-analyzer deployment/currency-service`
- Verify network connectivity to `api.stlouisfed.org`

## Alternative: Skip FRED API

If you don't need exchange rate features, you can leave `FRED_API_KEY` empty. The Currency Service will start but exchange rate endpoints will return errors.
