import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { GoogleAuth } from 'npm:google-auth-library@9.15.1'

type JsonMap = Record<string, unknown>

const PIPELINE_VERSION = '210-ios-push-hardening'

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  })

function asMap(value: unknown): JsonMap {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as JsonMap
    : {}
}

function stringifyData(value: unknown): Record<string, string> {
  const source = asMap(value)
  const output: Record<string, string> = {}
  for (const [key, item] of Object.entries(source)) {
    if (item === null || item === undefined) continue
    output[key] = typeof item === 'string' ? item : JSON.stringify(item)
  }
  return output
}

async function getFcmAccessToken(serviceAccountJson: string) {
  const credentials = JSON.parse(serviceAccountJson)
  const auth = new GoogleAuth({
    credentials,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  })
  const client = await auth.getClient()
  const token = await client.getAccessToken()
  const accessToken = typeof token === 'string' ? token : token?.token
  if (!accessToken) throw new Error('Could not obtain Firebase OAuth access token')
  return { accessToken, projectId: String(credentials.project_id ?? '') }
}

function driverText(eventType: string, orderNumber: unknown) {
  const shown = String(orderNumber ?? '').trim()
  const suffix = shown ? ` #${shown}` : ''
  switch (eventType) {
    case 'available': return { title: 'طلب توصيل جديد', body: `يوجد طلب جاهز للتوصيل من متجرك${suffix}` }
    case 'assigned': return { title: 'تم إسناد طلب جديد', body: `لديك طلب توصيل جديد${suffix}` }
    case 'picked_up': return { title: 'تم استلام الطلب', body: `تم تسجيل استلام الطلب${suffix}` }
    case 'delivered': return { title: 'تم تسليم الطلب', body: `تم تسجيل تسليم الطلب${suffix}` }
    case 'support_reply': return { title: 'رد جديد من دعم هلا طلب', body: 'وصل رد جديد على رسالة الدعم.' }
    case 'cancelled':
    case 'canceled': return { title: 'تم إلغاء الطلب', body: `تم إلغاء الطلب${suffix}` }
    default: return { title: 'إشعار السائق', body: suffix ? `تحديث على الطلب${suffix}` : 'لديك تحديث جديد' }
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    const payload = asMap(await req.json())
    // Stage 165 accepts both the canonical pg_net payload used by Hala Talab
    // and Supabase-style webhook aliases. This deliberately routes by TABLE
    // first, so Store/Driver notifications can never fall through a legacy
    // customer-only validator.
    const record = asMap(payload.record ?? payload.new_record ?? payload.new)
    const type = String(payload.type ?? payload.event ?? payload.event_type ?? 'INSERT').toUpperCase()
    const schema = String(payload.schema ?? payload.schema_name ?? 'public')
    const table = String(payload.table ?? payload.table_name ?? payload.source_table ?? '')
    const notificationId = String(record.id ?? payload.notification_id ?? '').trim()

    if (type !== 'INSERT' || schema !== 'public' || !notificationId) {
      return json({ pipeline_version: PIPELINE_VERSION, error: 'Invalid Hala Talab notification webhook payload', received: { type, schema, table, has_notification_id: Boolean(notificationId) } }, 400)
    }
    if (!['customer_notifications', 'store_notifications', 'driver_notifications'].includes(table)) {
      return json({ pipeline_version: PIPELINE_VERSION, error: 'Unsupported notification table', table }, 400)
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
    if (!supabaseUrl || !serviceRoleKey) return json({ error: 'Supabase server secrets are unavailable' }, 503)
    if (!serviceAccountJson) return json({ error: 'FIREBASE_SERVICE_ACCOUNT is not configured' }, 503)

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    let userId = ''
    let role = ''
    let title = ''
    let body = ''
    let data: Record<string, string> = {}

    if (table === 'customer_notifications') {
      const { data: n, error } = await supabase
        .from('customer_notifications')
        .select('id, customer_id, order_id, type, title, body, data')
        .eq('id', notificationId).maybeSingle()
      if (error) throw error
      if (!n) return json({ error: 'Customer notification row not found' }, 404)
      userId = String(n.customer_id ?? '')
      role = 'customer'
      title = String(n.title ?? '')
      body = String(n.body ?? '')
      data = stringifyData({ ...asMap(n.data), notification_id: n.id, order_id: n.order_id, notification_type: n.type })
    } else if (table === 'store_notifications') {
      const { data: n, error } = await supabase
        .from('store_notifications')
        .select('id, store_id, type, title, body, data')
        .eq('id', notificationId).maybeSingle()
      if (error) throw error
      if (!n) return json({ error: 'Store notification row not found' }, 404)
      const { data: store, error: storeError } = await supabase
        .from('stores').select('owner_id').eq('id', n.store_id).maybeSingle()
      if (storeError) throw storeError
      userId = String(store?.owner_id ?? '')
      role = 'business'
      title = String(n.title ?? '')
      body = String(n.body ?? '')
      data = stringifyData({ ...asMap(n.data), notification_id: n.id, store_id: n.store_id, notification_type: n.type })
    } else {
      const { data: n, error } = await supabase
        .from('driver_notifications')
        .select('id, driver_id, order_id, order_number, event_type')
        .eq('id', notificationId).maybeSingle()
      if (error) throw error
      if (!n) return json({ error: 'Driver notification row not found' }, 404)
      userId = String(n.driver_id ?? '')
      role = 'driver'
      const text = driverText(String(n.event_type ?? ''), n.order_number)
      title = text.title
      body = text.body
      data = stringifyData({ notification_id: n.id, order_id: n.order_id, order_number: n.order_number, notification_type: n.event_type })
    }

    if (!userId || !role || !title || !body) {
      return json({ error: 'Notification is missing recipient, role, title, or body' }, 400)
    }

    const { data: tokenRows, error: tokenError } = await supabase
      .from('device_push_tokens')
      .select('id, token, platform, updated_at')
      .eq('user_id', userId)
      .eq('role', role)
      .order('updated_at', { ascending: false })
    if (tokenError) throw tokenError
    if (!tokenRows?.length) {
      console.warn('Hala Talab push: no registered tokens', { table, notificationId, userId, role })
      return json({ pipeline_version: PIPELINE_VERSION, notification_id: notificationId, table, role, sent: 0, attempted: 0, reason: 'No registered push tokens for recipient' }, 404)
    }

    // A Hala Talab Store/Driver account can be open on more than one phone.
    // Keep every distinct FCM token and fan the notification out to all of
    // them. A token is installation-specific; never collapse by user/role.
    const seenTokens = new Set<string>()
    const distinctTokenRows = tokenRows.filter((row) => {
      const token = String(row.token ?? '').trim()
      if (!token || seenTokens.has(token)) return false
      seenTokens.add(token)
      return true
    })

    console.info('Hala Talab push dispatch Stage 208 Fix 4', {
      table, notificationId, userId, role, tokenCount: distinctTokenRows.length,
    })

    const { accessToken, projectId } = await getFcmAccessToken(serviceAccountJson)
    if (!projectId) throw new Error('Firebase service account project_id is missing')

    const results: Array<Record<string, unknown>> = []
    for (const row of distinctTokenRows) {
      const platform = String(row.platform ?? '').toLowerCase()
      const apnsTopic = role === 'customer'
        ? 'com.halatalab.customer'
        : 'com.halatalab.partners'
      const platformConfig = platform === 'ios'
        ? {
            apns: {
              headers: {
                'apns-priority': '10',
                'apns-push-type': 'alert',
                // The same Edge Function serves Customer + Partners. APNs
                // requires the topic to match the app that owns the FCM token.
                'apns-topic': apnsTopic,
              },
              payload: {
                aps: {
                  alert: { title, body },
                  sound: 'default',
                  badge: 1,
                },
              },
            },
          }
        : {
            android: {
              priority: 'high',
              notification: {
                channel_id: 'hala_talab_orders',
                sound: 'default',
              },
            },
          }

      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: {
            token: row.token,
            notification: { title, body },
            data,
            ...platformConfig,
          },
        }),
      })
      const responseText = await response.text()
      results.push({ token_id: row.id, platform: row.platform, ok: response.ok, status: response.status, response: responseText })

      // FCM marks tokens that belong to an uninstalled/obsolete app instance as
      // UNREGISTERED. Removing only that token preserves other phones signed in
      // to the same Store/Driver account.
      if (!response.ok && responseText.includes('UNREGISTERED')) {
        await supabase.from('device_push_tokens').delete().eq('id', row.id)
      }

      // Production observability without storing the raw token.
      try {
        await supabase.from('push_delivery_attempts').insert({
          notification_id: notificationId,
          notification_table: table,
          recipient_user_id: userId,
          role,
          token_id: row.id,
          platform: row.platform,
          ok: response.ok,
          fcm_status: response.status,
          response_excerpt: responseText.slice(0, 800),
        })
      } catch (_) {}
    }

    const sent = results.filter((x) => x.ok === true).length
    console.info('Hala Talab push result Stage 208 Fix 4', { table, notificationId, role, sent, attempted: results.length })

    // Do not hide a complete FCM delivery failure behind HTTP 200. pg_net/Edge
    // logs will now make a real delivery failure visible immediately.
    const status = sent > 0 ? 200 : 502
    return json({ pipeline_version: PIPELINE_VERSION, notification_id: notificationId, table, role, sent, attempted: results.length, results }, status)
  } catch (error) {
    console.error(error)
    return json({ pipeline_version: PIPELINE_VERSION, error: String(error) }, 500)
  }
})
