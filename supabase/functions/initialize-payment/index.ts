import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, json } from '../_shared/cors.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const paystackSecret = Deno.env.get('PAYSTACK_SECRET_KEY');

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  if (!paystackSecret) return json({ error: 'Payment service is not configured' }, 503);

  const authHeader = request.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return json({ error: 'Authentication required' }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return json({ error: 'Invalid session' }, 401);

  let input: { product_id?: string; metadata?: Record<string, unknown> };
  try { input = await request.json(); } catch { return json({ error: 'Invalid JSON body' }, 400); }
  if (!input.product_id) return json({ error: 'product_id is required' }, 400);

  const reference = `BN_${crypto.randomUUID().replaceAll('-', '').slice(0, 20).toUpperCase()}`;
  const admin = createClient(supabaseUrl, serviceRoleKey);
  const { data: product } = await admin.from('catalog_products').select('id,code,kind,price_usd_cents,price_ngn_kobo,gem_amount,plan_id').eq('id', input.product_id).eq('is_active', true).maybeSingle();
  if (!product) return json({ error: 'Product not found or inactive' }, 404);
  const { data: order, error: orderError } = await admin.from('orders').insert({
    user_id: user.id,
    product_id: product.id,
    reference,
    amount_usd_cents: product.price_usd_cents,
    amount_ngn_kobo: product.price_ngn_kobo,
  }).select('id').single();
  if (orderError || !order) return json({ error: 'Could not create order' }, 500);
  const { error: insertError } = await admin.from('payment_transactions').insert({
    user_id: user.id,
    reference,
    product_id: product.id,
    order_id: order.id,
    amount_kobo: product.price_ngn_kobo,
    purpose: product.code,
    metadata: input.metadata ?? {},
    status: 'pending',
  });
  if (insertError) return json({ error: 'Could not create payment record' }, 500);

  const paystackResponse = await fetch('https://api.paystack.co/transaction/initialize', {
    method: 'POST',
    headers: { Authorization: `Bearer ${paystackSecret}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: user.email,
      amount: product.price_ngn_kobo.toString(),
      reference,
      ...(Deno.env.get('PAYSTACK_CALLBACK_URL') ? { callback_url: Deno.env.get('PAYSTACK_CALLBACK_URL') } : {}),
      metadata: { user_id: user.id, product_id: product.id, purpose: product.code },
    }),
  });
  const result = await paystackResponse.json();
  if (!paystackResponse.ok || !result.status) {
    await admin.from('payment_transactions').update({ status: 'failed', gateway_response: result }).eq('reference', reference);
    return json({ error: 'Paystack rejected the transaction' }, 502);
  }

  await admin.from('payment_transactions').update({ gateway_access_code: result.data.access_code }).eq('reference', reference);
  return json({ reference, authorization_url: result.data.authorization_url, access_code: result.data.access_code });
});
