# Secure Paystack payments in BookNest

## What belongs where

The Flutter APK may contain the Supabase URL and anon key. It must never contain:

- `PAYSTACK_SECRET_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- webhook signing secrets
- database passwords

These are stored as Supabase Edge Function secrets.

## One-time setup

From the repository root, after installing and linking the Supabase CLI:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
supabase secrets set PAYSTACK_SECRET_KEY="sk_test_or_live_..."
supabase secrets set SUPABASE_SERVICE_ROLE_KEY="YOUR_SERVICE_ROLE_KEY"
supabase functions deploy initialize-payment
supabase functions deploy verify-payment
supabase functions deploy paystack-webhook --no-verify-jwt
```

The project URL, anon key, and service-role key can be retrieved from the Supabase dashboard. The service-role key is only supplied to the CLI command; never commit it.

Configure this Paystack webhook URL in the Paystack dashboard:

```text
https://YOUR_PROJECT_REF.supabase.co/functions/v1/paystack-webhook
```

## Flutter request flow

1. The signed-in Flutter client invokes `initialize-payment` with the normal Supabase session:

```dart
final response = await Supabase.instance.client.functions.invoke(
  'initialize-payment',
  body: {
    'product_id': productId, // load from catalog_products; never send a trusted amount
    'metadata': {'book_id': bookId},
  },
);
```

2. Open the returned `authorization_url` in the checkout/browser flow.
3. Call `verify-payment` after checkout using the returned `reference`.
4. Treat the server response as authoritative. Never mark an order paid solely because the app says payment succeeded.
5. The Paystack webhook independently verifies successful charges and updates `payment_transactions`.

Amounts are integer kobo, not floating-point naira values.

## Local development

```bash
supabase start
supabase functions serve initialize-payment --env-file ./creds/functions.env
```

Keep local secrets in `creds/functions.env` and add this to `.gitignore`:

```text
creds/
*.env
.env*
```

The `creds` folder is for local development only. It must never be bundled into Flutter assets or shipped in the APK.
