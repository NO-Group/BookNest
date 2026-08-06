import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, json } from '../_shared/cors.ts';

const url = Deno.env.get('SUPABASE_URL')!;
const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const paystackSecret = Deno.env.get('PAYSTACK_SECRET_KEY');

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  if (!paystackSecret) return json({ error: 'Payment service is not configured' }, 503);
  const authHeader = request.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return json({ error: 'Authentication required' }, 401);

  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ error: 'Invalid session' }, 401);

  let body: { reference?: string };
  try { body = await request.json(); } catch { return json({ error: 'Invalid JSON body' }, 400); }
  if (!body.reference || !/^BN_[A-Z0-9]+$/.test(body.reference)) return json({ error: 'Invalid payment reference' }, 400);

  const admin = createClient(url, serviceRoleKey);
  const { data: payment } = await admin.from('payment_transactions').select('id,user_id,amount_kobo,status,order_id').eq('reference', body.reference).eq('user_id', user.id).maybeSingle();
  if (!payment) return json({ error: 'Payment not found' }, 404);
  if (payment.status === 'success') return json({ status: 'success', reference: body.reference });

  const response = await fetch(`https://api.paystack.co/transaction/verify/${encodeURIComponent(body.reference)}`, { headers: { Authorization: `Bearer ${paystackSecret}` } });
  const result = await response.json();
  if (!response.ok || !result.status) return json({ error: 'Could not verify transaction' }, 502);

  const paidAmount = Number(result.data?.amount);
  const valid = result.data?.status === 'success' && result.data?.currency === 'NGN' && paidAmount === payment.amount_kobo && result.data?.reference === body.reference;
  const nextStatus = valid ? 'success' : result.data?.status === 'failed' ? 'failed' : 'pending';
  await admin.from('payment_transactions').update({ status: nextStatus, gateway_response: result.data, verified_at: valid ? new Date().toISOString() : null }).eq('id', payment.id);
  if (payment.order_id) {
    await admin.from('orders').update({ status: nextStatus, paid_at: valid ? new Date().toISOString() : null }).eq('id', payment.order_id);
    if (valid) await admin.rpc('fulfill_order', { target_order: payment.order_id });
  }
  return json({ status: nextStatus, reference: body.reference });
});
