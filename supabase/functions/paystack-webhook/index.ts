import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { json, corsHeaders } from '../_shared/cors.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const paystackSecret = Deno.env.get('PAYSTACK_SECRET_KEY')!;

async function hmacSha512(secret: string, payload: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-512' }, false, ['sign']);
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(payload));
  return [...new Uint8Array(signature)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  const rawBody = await request.text();
  const received = request.headers.get('x-paystack-signature');
  if (!received || received !== await hmacSha512(paystackSecret, rawBody)) return json({ error: 'Invalid signature' }, 401);
  let event: { event?: string; data?: { reference?: string; amount?: number; status?: string; currency?: string } };
  try { event = JSON.parse(rawBody); } catch { return json({ error: 'Invalid JSON' }, 400); }
  if (event.event !== 'charge.success' || !event.data?.reference) return json({ received: true });

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const { data: payment } = await admin.from('payment_transactions').select('id,amount_kobo,order_id').eq('reference', event.data.reference).maybeSingle();
  if (!payment) return json({ received: true });
  const valid = event.data.status === 'success' && event.data.currency === 'NGN' && Number(event.data.amount) === payment.amount_kobo;
  const nextStatus = valid ? 'success' : 'failed';
  await admin.from('payment_transactions').update({ status: nextStatus, gateway_response: event.data, verified_at: valid ? new Date().toISOString() : null }).eq('id', payment.id);
  if (payment.order_id) {
    await admin.from('orders').update({ status: nextStatus, paid_at: valid ? new Date().toISOString() : null }).eq('id', payment.order_id);
    if (valid) await admin.rpc('fulfill_order', { target_order: payment.order_id });
  }
  return json({ received: true });
});
