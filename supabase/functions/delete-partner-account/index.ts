import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'Content-Type': 'application/json; charset=utf-8' },
})

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ ok: false, code: 'METHOD_NOT_ALLOWED' }, 405)

  try {
    const authorization = req.headers.get('Authorization') ?? ''
    if (!authorization.startsWith('Bearer ')) return json({ ok: false, code: 'AUTH_REQUIRED' }, 401)

    const body = await req.json().catch(() => ({}))
    if (body?.confirm !== true) return json({ ok: false, code: 'CONFIRMATION_REQUIRED' }, 400)
    const expectedRole = body?.expected_role === 'driver' ? 'driver' : body?.expected_role === 'business' ? 'business' : ''
    if (!expectedRole) return json({ ok: false, code: 'EXPECTED_ROLE_REQUIRED' }, 400)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !anonKey || !serviceKey) return json({ ok: false, code: 'SERVER_AUTH_NOT_CONFIGURED' }, 503)

    const caller = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: userData, error: userError } = await caller.auth.getUser()
    if (userError || !userData.user) return json({ ok: false, code: 'AUTH_REQUIRED' }, 401)
    const userId = userData.user.id

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    // Resolve the authoritative role server-side. Never trust a role or user id
    // supplied by the client.
    const { data: registry, error: registryError } = await admin
      .from('phone_account_registry')
      .select('account_role')
      .eq('auth_user_id', userId)
      .maybeSingle()
    if (registryError) throw registryError

    let role = String(registry?.account_role ?? '').toLowerCase()
    if (!role) {
      const { data: roleRow, error: roleError } = await admin
        .from('account_roles')
        .select('role')
        .eq('user_id', userId)
        .maybeSingle()
      if (roleError) throw roleError
      role = String(roleRow?.role ?? '').toLowerCase()
    }
    if (role !== expectedRole || (role !== 'business' && role !== 'driver')) {
      return json({ ok: false, code: 'PARTNER_ROLE_MISMATCH' }, 403)
    }

    if (role === 'business') {
      // Stage 208 Fix7 migration changes stores.owner_id to ON DELETE SET NULL.
      // This lets account deletion preserve completed order/accounting history
      // without keeping the former owner's authentication identity.
      const { data: store, error: storeError } = await admin
        .from('stores')
        .select('id')
        .eq('owner_id', userId)
        .maybeSingle()
      if (storeError) throw storeError

      if (store?.id) {
        const { error: anonymizeError } = await admin
          .from('stores')
          .update({
            owner_id: null,
            name: 'Deleted store',
            description: null,
            phone: 'deleted',
            address_text: 'Deleted account',
            logo_url: null,
            cover_url: null,
            is_active: false,
            is_open: false,
          })
          .eq('id', store.id)
        if (anonymizeError) {
          console.error('store anonymization failed', anonymizeError)
          return json({ ok: false, code: 'STORE_DELETE_SCHEMA_NOT_READY' }, 409)
        }
      }
    }

    // Remove account-control records that may not be covered by a cascade in
    // every deployment. Ignore missing-table errors so the function remains
    // compatible with older safe stages of the project.
    for (const [table, column] of [
      ['phone_pin_reset_requests', 'auth_user_id'],
      ['admin_user_controls', 'user_id'],
    ] as const) {
      const { error } = await admin.from(table).delete().eq(column, userId)
      if (error && !String(error.message ?? '').toLowerCase().includes('does not exist')) throw error
    }

    // For driver accounts, order.driver_id is ON DELETE SET NULL and driver
    // profile/auth tables are ON DELETE CASCADE. For stores, the migration
    // above preserves the store/order history while detaching the owner.
    const { error: deleteError } = await admin.auth.admin.deleteUser(userId)
    if (deleteError) throw deleteError

    return json({ ok: true, role })
  } catch (error) {
    console.error('delete-partner-account failed', error)
    return json({ ok: false, code: 'PARTNER_ACCOUNT_DELETE_FAILED' }, 500)
  }
})
