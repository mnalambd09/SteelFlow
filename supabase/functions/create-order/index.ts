import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const authorization = req.headers.get('Authorization');
  if (!authorization) return Response.json({ error: 'Sign in is required.' }, { status: 401 });
  const authClient = createClient(url, anon, { global: { headers: { Authorization: authorization } } });
  const { data: { user }, error: authError } = await authClient.auth.getUser();
  if (authError || !user) return Response.json({ error: 'Your session is invalid or expired.' }, { status: 401 });
  try {
    const body = await req.json();
    if (!Array.isArray(body.items) || body.items.length === 0 || body.items.length > 100) {
      return Response.json({ error: 'Add between 1 and 100 products to the order.' }, { status: 400 });
    }
    const address = { line1: String(body.shipping_address || '').trim() };
    if (!address.line1 || address.line1.length > 500) return Response.json({ error: 'Enter a valid shipping address.' }, { status: 400 });
    const client = createClient(url, service);
    const quantities = new Map<string, number>();
    for (const item of body.items) {
      if (typeof item.product_id !== 'string' || !/^[0-9a-f-]{36}$/i.test(item.product_id) || !Number.isSafeInteger(Number(item.quantity)) || Number(item.quantity) < 1) {
        return Response.json({ error: 'A product or quantity is invalid.' }, { status: 400 });
      }
      quantities.set(item.product_id, (quantities.get(item.product_id) || 0) + Number(item.quantity));
    }
    const { data: orderId, error } = await client.rpc('create_order_secure', {
      p_user_id: user.id,
      p_items: Array.from(quantities, ([product_id, quantity]) => ({ product_id, quantity })),
      p_shipping_address: address,
    });
    if (error) return Response.json({ error: error.message }, { status: 400 });
    return Response.json({ order_id: orderId, status: 'Pending payment' }, { status: 201 });
  } catch {
    return Response.json({ error: 'Could not process the order request.' }, { status: 400 });
  }
});
