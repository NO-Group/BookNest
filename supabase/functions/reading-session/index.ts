import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, json } from '../_shared/cors.ts';

const url = Deno.env.get('SUPABASE_URL')!;
const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  const authHeader = request.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return json({ error: 'Authentication required' }, 401);
  const client = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: { user } } = await client.auth.getUser();
  if (!user) return json({ error: 'Invalid session' }, 401);
  let body: { action?: string; book_id?: string; session_id?: string };
  try { body = await request.json(); } catch { return json({ error: 'Invalid JSON body' }, 400); }
  try {
    if (body.action === 'start' && body.book_id) {
      const { data, error } = await client.rpc('start_reading_session', { target_book: body.book_id });
      if (error) throw error;
      return json({ session_id: data });
    }
    if (body.action === 'heartbeat' && body.session_id) {
      const { error } = await client.rpc('heartbeat_reading_session', { target_session: body.session_id });
      if (error) throw error;
      return json({ ok: true });
    }
    if (body.action === 'finish' && body.session_id) {
      const { data, error } = await client.rpc('finish_reading_session', { target_session: body.session_id });
      if (error) throw error;
      return json({ minutes: data ?? 0 });
    }
    return json({ error: 'action and required identifier are invalid' }, 400);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Reading session failed' }, 400);
  }
});
