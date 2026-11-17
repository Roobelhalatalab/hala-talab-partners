import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'Content-Type': 'application/json; charset=utf-8' },
})

function normalizeIraqiPhone(raw: unknown) {
  let digits = String(raw ?? '').replace(/\D/g, '')
  if (digits.startsWith('00964')) digits = digits.slice(2)
  if (digits.startsWith('0')) digits = digits.slice(1)
  if (!digits.startsWith('964')) digits = `964${digits}`
  if (!/^9647\d{9}$/.test(digits)) throw new Error('INVALID_IRAQI_PHONE')
  return `+${digits}`
}

function normalizeRole(raw: unknown) {
  const role = String(raw ?? '').toLowerCase()
  if (!['customer', 'business', 'driver'].includes(role)) throw new Error('UNSUPPORTED_ROLE')
  return role
}

function syntheticEmail(phone: string) {
  return `${phone.replace(/\D/g, '')}@phone.halatalab.invalid`
}

function roleMismatchCode(role: string) {
  return `ROLE_MISMATCH_${role.toUpperCase()}`
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ ok: false, code: 'METHOD_NOT_ALLOWED' }, 405)

  try {
    const body = await req.json()
    const action = String(body?.action ?? 'login').toLowerCase()
    const phone = normalizeIraqiPhone(body?.phone)
    const role = normalizeRole(body?.role)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !serviceKey) return json({ ok: false, code: 'SERVER_AUTH_NOT_CONFIGURED' }, 503)
    const sb = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })

    const { data: registry, error: registryError } = await sb.from('phone_account_registry')
      .select('auth_user_id,account_role').eq('phone_e164', phone).maybeSingle()
    if (registryError) throw registryError
    if (registry && registry.account_role !== role) {
      return json({ ok: false, code: roleMismatchCode(String(registry.account_role)) }, 409)
    }

    if (action === 'request_pin_reset') {
      if (!registry) return json({ ok: false, code: 'ACCOUNT_NOT_FOUND' }, 404)
      const { data: requestId, error } = await sb.rpc('server_request_phone_pin_reset', {
        p_user_id: registry.auth_user_id,
        p_phone_e164: phone,
        p_role: role,
      })
      if (error) throw error
      return json({ ok: true, request_id: requestId, phone, role })
    }

    if (action === 'reset_pin_with_admin_code') {
      if (!registry) return json({ ok: false, code: 'ACCOUNT_NOT_FOUND' }, 404)
      const recoveryCode = String(body?.recovery_code ?? '').trim()
      const newPin = String(body?.new_pin ?? '').trim()
      if (!/^\d{6}$/.test(recoveryCode)) return json({ ok: false, code: 'INVALID_RECOVERY_CODE' }, 400)
      if (!/^\d{4}$/.test(newPin)) return json({ ok: false, code: 'INVALID_PIN' }, 400)
      const { data: resetStatus, error } = await sb.rpc('server_redeem_phone_pin_reset_code', {
        p_user_id: registry.auth_user_id,
        p_role: role,
        p_code: recoveryCode,
        p_new_pin: newPin,
      })
      if (error) throw error
      if (resetStatus !== 'OK') {
        const status = resetStatus === 'RESET_CODE_LOCKED' ? 429 : 400
        return json({ ok: false, code: resetStatus || 'RESET_FAILED' }, status)
      }
      return json({ ok: true, phone, role })
    }

    const pin = String(body?.pin ?? '').trim()
    if (!/^\d{4}$/.test(pin)) return json({ ok: false, code: 'INVALID_PIN' }, 400)

    const allowCreate = action === 'register'
    if (!registry && !allowCreate) return json({ ok: false, code: 'ACCOUNT_NOT_FOUND' }, 404)
    if (registry && action === 'register') return json({ ok: false, code: 'ACCOUNT_ALREADY_EXISTS' }, 409)

    let userId = registry?.auth_user_id as string | undefined
    let email = syntheticEmail(phone)
    let isNewAccount = false

    if (!userId) {
      const fullName = String(body?.full_name ?? '').trim()
      if (role === 'customer' && fullName.length < 2) return json({ ok: false, code: 'INVALID_FULL_NAME' }, 400)
      const businessType = body?.business_type ?? null
      const systemCategoryId = body?.system_category_id ?? null
      const metadata = { account_role: role, role, full_name: fullName, phone, contact_phone: phone, auth_method: 'phone_pin', business_type: businessType, system_category_id: systemCategoryId }
      const { data: created, error: createError } = await sb.auth.admin.createUser({ email, email_confirm: true, user_metadata: metadata })
      if (createError || !created.user) throw createError ?? new Error('AUTH_USER_CREATE_FAILED')
      userId = created.user.id
      isNewAccount = true

      const { error: regInsertError } = await sb.from('phone_account_registry').insert({ phone_e164: phone, auth_user_id: userId, account_role: role })
      if (regInsertError) throw regInsertError
      await sb.from('account_roles').upsert({ user_id: userId, email, role }, { onConflict: 'user_id' })
      if (role === 'customer') {
        await sb.from('customer_accounts').upsert({ user_id: userId, email }, { onConflict: 'user_id' })
      } else {
        await sb.from('partner_profiles').upsert({ id: userId, full_name: fullName, phone, email, role, business_type: role === 'business' ? businessType : null, system_category_id: role === 'business' ? systemCategoryId : null, account_status: 'pending' }, { onConflict: 'id' })
      }
      const { error: pinSetError } = await sb.rpc('server_set_phone_pin', { p_user_id: userId, p_phone_e164: phone, p_pin: pin })
      if (pinSetError) throw pinSetError
    } else {
      const { data: existingUser, error: existingUserError } = await sb.auth.admin.getUserById(userId)
      if (existingUserError || !existingUser.user) throw existingUserError ?? new Error('AUTH_USER_NOT_FOUND')
      email = existingUser.user.email ?? email

      const { data: pinStatus, error: pinCheckError } = await sb.rpc('server_check_phone_pin', { p_user_id: userId, p_pin: pin })
      if (pinCheckError) throw pinCheckError
      if (pinStatus === 'PIN_NOT_SET') {
        return json({ ok: false, code: 'PIN_NOT_SET_USE_RECOVERY' }, 409)
      }
      if (pinStatus !== 'OK') {
        return json({ ok: false, code: pinStatus || 'PIN_INCORRECT' }, pinStatus === 'PIN_LOCKED' ? 429 : 401)
      }
    }

    const { data: control } = await sb.from('admin_user_controls').select('access_status').eq('user_id', userId).maybeSingle()
    if (['suspended', 'blocked'].includes(String(control?.access_status ?? 'active'))) {
      return json({ ok: false, code: 'ACCOUNT_SUSPENDED' }, 403)
    }

    const { data: linkData, error: linkError } = await sb.auth.admin.generateLink({
      type: 'magiclink', email,
      options: { data: { account_role: role, role, contact_phone: phone, auth_method: 'phone_pin' } },
    })
    if (linkError) throw linkError
    const tokenHash = linkData?.properties?.hashed_token
    if (!tokenHash) throw new Error('AUTH_SESSION_TOKEN_MISSING')

    return json({ ok: true, role, phone, is_new_account: isNewAccount, token_hash: tokenHash })
  } catch (error) {
    console.error(error)
    const text = String(error)
    const code = text.includes('INVALID_IRAQI_PHONE') ? 'INVALID_IRAQI_PHONE'
      : text.includes('UNSUPPORTED_ROLE') ? 'UNSUPPORTED_ROLE'
      : 'PHONE_PIN_AUTH_FAILED'
    return json({ ok: false, code }, code === 'PHONE_PIN_AUTH_FAILED' ? 500 : 400)
  }
})
