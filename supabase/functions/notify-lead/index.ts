const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const RATE_WINDOW_MS = 60_000;
const RATE_MAX = 5;
const MAX_TEXT_LENGTH = 4000;
const NOTION_API_VERSION = '2026-03-11';
const ORDERS_DATA_SOURCE_TITLE = 'إدارة طلبات مأوى';
const APPROVAL_PAGE_URL = 'https://maawaa.sa/approve-contract.html';
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type DeliveryChannel = 'telegram' | 'web3forms' | 'notion';

type DeliveryResult = {
  channel: DeliveryChannel;
  ok: boolean;
  status: number;
};

type ContractRecord = {
  id: string;
  contract_number: string | null;
  client_id: string;
  service_type: string | null;
  total_amount: number | string | null;
  property_type: string | null;
  property_location: string | null;
  rooms_count: string | null;
  shoot_date: string | null;
  notes: string | null;
  created_at: string | null;
};

type ClientRecord = {
  id: string;
  full_name: string;
  phone_number: string | null;
  email: string | null;
};

type NotionSchema = {
  id: string;
  properties: Record<string, { id?: string; type?: string }>;
};

const hits = new Map<string, number[]>();
let ordersDataSourcePromise: Promise<NotionSchema> | null = null;

function rateLimited(ip: string): boolean {
  const now = Date.now();
  const list = (hits.get(ip) ?? []).filter((time) => now - time < RATE_WINDOW_MS);
  if (list.length >= RATE_MAX) {
    hits.set(ip, list);
    return true;
  }
  list.push(now);
  hits.set(ip, list);
  return false;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

function plainText(value: string): string {
  return value
    .replace(/<[^>]*>/g, '')
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '')
    .trim();
}

function notionRichText(value: string): Array<Record<string, unknown>> {
  const text = value.trim();
  if (!text) return [];

  const chunks: string[] = [];
  for (let offset = 0; offset < text.length && chunks.length < 20; offset += 2000) {
    chunks.push(text.slice(offset, offset + 2000));
  }

  return chunks.map((content) => ({
    type: 'text',
    text: { content },
  }));
}

function bytesToHex(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function contractApprovalUrl(contractId: string): Promise<string> {
  const secret = Deno.env.get('CONTRACT_APPROVAL_SECRET')?.trim() ?? '';
  if (!secret) throw new Error('contract_approval_secret_missing');
  const expires = Math.floor(Date.now() / 1000) + (90 * 24 * 60 * 60);
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signed = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(`${contractId}.${expires}`),
  );
  const url = new URL(APPROVAL_PAGE_URL);
  url.searchParams.set('contract', contractId);
  url.searchParams.set('expires', String(expires));
  url.searchParams.set('signature', bytesToHex(new Uint8Array(signed)));
  return url.toString();
}

async function notionRequest(
  token: string,
  path: string,
  init: RequestInit = {},
): Promise<{ status: number; body: Record<string, unknown> }> {
  const response = await fetch(`https://api.notion.com/v1${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      'Notion-Version': NOTION_API_VERSION,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
  const body = await response.json().catch(() => ({})) as Record<string, unknown>;

  if (!response.ok) {
    const message = typeof body.message === 'string' ? body.message : 'unknown_error';
    throw new Error(`notion_${response.status}: ${message.slice(0, 500)}`);
  }

  return { status: response.status, body };
}

function notionTitle(value: unknown): string {
  if (!Array.isArray(value)) return '';
  return value
    .map((item) => {
      if (!item || typeof item !== 'object') return '';
      const titleItem = item as Record<string, unknown>;
      if (typeof titleItem.plain_text === 'string') return titleItem.plain_text;
      const text = titleItem.text;
      if (text && typeof text === 'object' && typeof (text as Record<string, unknown>).content === 'string') {
        return (text as Record<string, unknown>).content as string;
      }
      return '';
    })
    .join('');
}

async function resolveOrdersDataSource(token: string): Promise<NotionSchema> {
  const configuredId = Deno.env.get('NOTION_ORDERS_DATA_SOURCE_ID')?.trim();
  let dataSourceId = configuredId || '';

  if (!dataSourceId) {
    const search = await notionRequest(token, '/search', {
      method: 'POST',
      body: JSON.stringify({
        query: ORDERS_DATA_SOURCE_TITLE,
        filter: { property: 'object', value: 'data_source' },
        page_size: 100,
      }),
    });

    const results = Array.isArray(search.body.results) ? search.body.results : [];
    const exact = results.find((result) => {
      if (!result || typeof result !== 'object') return false;
      return notionTitle((result as Record<string, unknown>).title) === ORDERS_DATA_SOURCE_TITLE;
    }) as Record<string, unknown> | undefined;

    if (!exact || typeof exact.id !== 'string') {
      throw new Error(`notion_data_source_not_found: ${ORDERS_DATA_SOURCE_TITLE}`);
    }
    dataSourceId = exact.id;
  }

  const retrieved = await notionRequest(token, `/data_sources/${encodeURIComponent(dataSourceId)}`);
  let properties = retrieved.body.properties;
  if (!properties || typeof properties !== 'object' || Array.isArray(properties)) {
    throw new Error('notion_invalid_data_source_schema');
  }

  if (!(properties as Record<string, unknown>)['موعد جلسة التصوير']) {
    const updated = await notionRequest(
      token,
      `/data_sources/${encodeURIComponent(dataSourceId)}`,
      {
        method: 'PATCH',
        body: JSON.stringify({
          properties: {
            'موعد جلسة التصوير': { date: {} },
          },
        }),
      },
    );
    properties = updated.body.properties;
    if (!properties || typeof properties !== 'object' || Array.isArray(properties)) {
      throw new Error('notion_schema_update_failed');
    }
  }

  const typedProperties = properties as Record<string, { id?: string; type?: string }>;
  if (typedProperties['رقم الطلب'] && typedProperties['رقم الطلب'].type !== 'rich_text') {
    const renamed = await notionRequest(
      token,
      `/data_sources/${encodeURIComponent(dataSourceId)}`,
      {
        method: 'PATCH',
        body: JSON.stringify({
          properties: {
            'رقم الطلب': { name: 'رقم داخلي لنوشن' },
          },
        }),
      },
    );
    properties = renamed.body.properties;
    if (!properties || typeof properties !== 'object' || Array.isArray(properties)) {
      throw new Error('notion_contract_number_rename_failed');
    }
  }

  if (!(properties as Record<string, unknown>)['رقم الطلب']) {
    const added = await notionRequest(
      token,
      `/data_sources/${encodeURIComponent(dataSourceId)}`,
      {
        method: 'PATCH',
        body: JSON.stringify({
          properties: {
            'رقم الطلب': { rich_text: {} },
          },
        }),
      },
    );
    properties = added.body.properties;
    if (!properties || typeof properties !== 'object' || Array.isArray(properties)) {
      throw new Error('notion_contract_number_property_failed');
    }
  }

  if (!(properties as Record<string, unknown>)['اعتماد وإرسال العقد']) {
    const added = await notionRequest(
      token,
      `/data_sources/${encodeURIComponent(dataSourceId)}`,
      {
        method: 'PATCH',
        body: JSON.stringify({
          properties: {
            'اعتماد وإرسال العقد': { url: {} },
          },
        }),
      },
    );
    properties = added.body.properties;
    if (!properties || typeof properties !== 'object' || Array.isArray(properties)) {
      throw new Error('notion_approval_url_property_failed');
    }
  }

  return {
    id: dataSourceId,
    properties: properties as Record<string, { id?: string; type?: string }>,
  };
}

async function getOrdersDataSource(token: string): Promise<NotionSchema> {
  if (!ordersDataSourcePromise) {
    ordersDataSourcePromise = resolveOrdersDataSource(token);
  }

  try {
    return await ordersDataSourcePromise;
  } catch (error) {
    ordersDataSourcePromise = null;
    throw error;
  }
}

async function getSupabaseRecord<T>(
  table: string,
  select: string,
  id: string,
): Promise<T> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')?.trim() ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim() ?? '';
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error('supabase_server_credentials_missing');
  }

  const url = new URL(`${supabaseUrl}/rest/v1/${table}`);
  url.searchParams.set('select', select);
  url.searchParams.set('id', `eq.${id}`);
  url.searchParams.set('limit', '1');

  const response = await fetch(url, {
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      Accept: 'application/json',
    },
  });
  const body = await response.json().catch(() => null);

  if (!response.ok) {
    throw new Error(`supabase_${table}_${response.status}`);
  }
  if (!Array.isArray(body) || body.length !== 1) {
    throw new Error(`${table}_record_not_found`);
  }

  return body[0] as T;
}

function propertyType(schema: NotionSchema, name: string): string {
  return schema.properties[name]?.type ?? '';
}

function serviceNames(value: string | null): string[] {
  if (!value) return [];
  return [...new Set(
    value
      .split(/[،,\n]+/)
      .map((item) => item.trim())
      .filter(Boolean)
      .map((item) => item.slice(0, 100)),
  )].slice(0, 20);
}

function propertyTypeLabel(value: string | null): string {
  const labels: Record<string, string> = {
    villa: 'فيلا',
    apartment: 'شقة',
    office: 'مكتب',
    land: 'أرض',
    commercial: 'عقار تجاري',
    compound: 'مجمع',
    other: 'أخرى',
  };
  return value ? (labels[value] ?? value) : '';
}

function extractShootTime(notes: string | null): string {
  const match = notes?.match(/الساعة\s+([01]?\d|2[0-3]):([0-5]\d)/);
  if (!match) return '';
  return `${match[1].padStart(2, '0')}:${match[2]}`;
}

function shootDateTimeStart(contract: ContractRecord): string {
  if (!contract.shoot_date) return '';
  const shootTime = extractShootTime(contract.notes);
  return shootTime
    ? `${contract.shoot_date}T${shootTime}:00+03:00`
    : contract.shoot_date;
}

function formatDateArabic(value: string | null): string {
  if (!value) return 'لم يحدد';
  const date = new Date(`${value}T12:00:00+03:00`);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat('ar-SA-u-ca-gregory', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    timeZone: 'Asia/Riyadh',
  }).format(date);
}

function formatTimeArabic(value: string): string {
  if (!value) return 'لم يحدد';
  const [hourText, minute = '00'] = value.split(':');
  const hour = Number(hourText);
  if (!Number.isInteger(hour) || hour < 0 || hour > 23) return value;
  if (hour === 0) return `12:${minute} منتصف الليل`;
  if (hour === 12) return `12:${minute} ظهرًا`;
  return hour < 12
    ? `${hour}:${minute} صباحًا`
    : `${hour - 12}:${minute} مساءً`;
}

function formatMoney(value: number): string {
  return new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(value);
}

function formatCreatedAt(value: string | null): string {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat('ar-SA-u-ca-gregory', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'Asia/Riyadh',
  }).format(date);
}

function escapeTelegramHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

async function loadContractDetails(contractId: string): Promise<{
  contract: ContractRecord;
  client: ClientRecord;
}> {
  const contract = await getSupabaseRecord<ContractRecord>(
    'contracts',
    'id,contract_number,client_id,service_type,total_amount,property_type,property_location,rooms_count,shoot_date,notes,created_at',
    contractId,
  );
  const client = await getSupabaseRecord<ClientRecord>(
    'clients',
    'id,full_name,phone_number,email',
    contract.client_id,
  );
  return { contract, client };
}

function formatOrderNotification(contract: ContractRecord, client: ClientRecord): string {
  const totalAmount = Number(contract.total_amount ?? 0);
  const safeTotal = Number.isFinite(totalAmount) ? totalAmount : 0;
  const deposit = Math.round(safeTotal * 0.25);
  const shootTime = extractShootTime(contract.notes);
  const bookingStatus = contract.notes?.includes('حجز مؤكد')
    ? 'حجز مؤكد — بانتظار استلام العربون'
    : contract.shoot_date
    ? 'موعد مفضل — بانتظار التأكيد'
    : 'طلب عرض سعر — لم يحدد موعدًا';
  const customerNotes = contract.notes
    ? contract.notes
      .split(/\s*\|\s*/)
      .map((note) => note.trim())
      .filter(Boolean)
      .filter((note) => !/^(حجز مؤكد:|عربون مستحق:|موعد التصوير:)/.test(note))
    : [];
  const noteLines = customerNotes.length > 0
    ? customerNotes.map((note) => `• ${note}`)
    : ['• لا توجد ملاحظات إضافية'];

  return [
    '🔴 طلب جديد من موقع مأوى',
    '━━━━━━━━━━━━━━━━',
    'بيانات العميل',
    `الاسم: ${client.full_name || '—'}`,
    `الجوال: ${client.phone_number || '—'}`,
    `البريد: ${client.email || 'لم يحدد'}`,
    '',
    'تفاصيل الطلب',
    `الخدمات: ${contract.service_type || '—'}`,
    `نوع العقار: ${propertyTypeLabel(contract.property_type) || 'لم يحدد'}`,
    `الموقع: ${contract.property_location || 'لم يحدد'}`,
    `عدد الغرف/المساحة: ${contract.rooms_count || 'لم يحدد'}`,
    '',
    '📅 موعد جلسة التصوير',
    `حالة الحجز: ${bookingStatus}`,
    `التاريخ: ${formatDateArabic(contract.shoot_date)}`,
    `وقت بداية الجلسة: ${formatTimeArabic(shootTime)}`,
    '',
    '💰 الحسابات',
    `إجمالي الطلب: ${formatMoney(safeTotal)} ر.س`,
    `العربون المطلوب (25٪): ${formatMoney(deposit)} ر.س`,
    `المتبقي بعد العربون: ${formatMoney(safeTotal - deposit)} ر.س`,
    '',
    'الملاحظات الإضافية',
    ...noteLines,
    '',
    'بيانات الطلب',
    `وقت استلام الطلب: ${formatCreatedAt(contract.created_at)}`,
    `رقم الطلب/العقد: ${contract.contract_number || 'لم يُنشأ بعد'}`,
  ].join('\n');
}

function formatTelegramNotification(message: string): string {
  const headings = new Set([
    '🔴 طلب جديد من موقع مأوى',
    'بيانات العميل',
    'تفاصيل الطلب',
    '📅 موعد جلسة التصوير',
    '💰 الحسابات',
    'الملاحظات الإضافية',
    'بيانات الطلب',
  ]);
  return message
    .split('\n')
    .map((line) => {
      const escaped = escapeTelegramHtml(line);
      return headings.has(line) ? `<b>${escaped}</b>` : escaped;
    })
    .join('\n');
}

async function syncContractToNotion(
  notionToken: string,
  contract: ContractRecord,
  client: ClientRecord,
  approvalUrl: string,
): Promise<DeliveryResult> {
  try {
    const schema = await getOrdersDataSource(notionToken);
    let existingPageId = '';

    if (propertyType(schema, 'ملاحظات') === 'rich_text') {
      const duplicateCheck = await notionRequest(
        notionToken,
        `/data_sources/${encodeURIComponent(schema.id)}/query`,
        {
          method: 'POST',
          body: JSON.stringify({
            filter: {
              property: 'ملاحظات',
              rich_text: { contains: contract.id },
            },
            page_size: 1,
          }),
        },
      );
      if (Array.isArray(duplicateCheck.body.results) && duplicateCheck.body.results.length > 0) {
        const existingPage = duplicateCheck.body.results[0] as Record<string, unknown> | undefined;
        if (existingPage && typeof existingPage.id === 'string') {
          existingPageId = existingPage.id;
        }
      }
    }

    const properties: Record<string, unknown> = {};
    const setProperty = (name: string, expectedType: string, value: unknown): void => {
      if (propertyType(schema, name) === expectedType) properties[name] = value;
    };

    setProperty('اسم العميل', 'title', {
      title: notionRichText(client.full_name || 'عميل من الموقع'),
    });
    setProperty('مرحلة الطلب', 'status', {
      status: { name: 'طلب جديد' },
    });
    if (contract.contract_number) {
      setProperty('رقم الطلب', 'rich_text', {
        rich_text: notionRichText(contract.contract_number),
      });
    }
    setProperty('اعتماد وإرسال العقد', 'url', {
      url: approvalUrl,
    });
    if (client.phone_number) {
      setProperty('رقم الجوال', 'phone_number', {
        phone_number: client.phone_number,
      });
    }
    if (client.email) {
      setProperty('البريد الإلكتروني', 'email', {
        email: client.email,
      });
    }

    const propertyLabel = propertyTypeLabel(contract.property_type);
    if (propertyLabel) {
      setProperty('نوع العقار', 'select', {
        select: { name: propertyLabel.slice(0, 100) },
      });
    }

    const services = serviceNames(contract.service_type);
    if (services.length > 0) {
      setProperty('الخدمات المطلوبة', 'multi_select', {
        multi_select: services.map((name) => ({ name })),
      });
    }

    const totalAmount = Number(contract.total_amount ?? 0);
    if (Number.isFinite(totalAmount)) {
      setProperty('قيمة الباقة الأساسية', 'number', {
        number: totalAmount,
      });
      if (!existingPageId) {
        setProperty('إجمالي المدفوع من العميل', 'number', {
          number: 0,
        });
      }
    }

    if (contract.shoot_date) {
      setProperty('موعد جلسة التصوير', 'date', {
        date: { start: shootDateTimeStart(contract) },
      });
    }

    const shootTime = extractShootTime(contract.notes);
    const notes = [
      'المصدر: الموقع الإلكتروني',
      `معرّف الطلب في Supabase: ${contract.id}`,
      contract.property_location ? `الموقع: ${contract.property_location}` : '',
      contract.rooms_count ? `عدد الغرف/المساحة: ${contract.rooms_count}` : '',
      contract.shoot_date ? `موعد التصوير المفضل: ${contract.shoot_date}` : '',
      shootTime ? `وقت بداية جلسة التصوير: ${formatTimeArabic(shootTime)}` : '',
      contract.notes ? `ملاحظات العميل: ${contract.notes}` : '',
    ].filter(Boolean).join('\n');
    setProperty('ملاحظات', 'rich_text', {
      rich_text: notionRichText(notes),
    });

    const saved = existingPageId
      ? await notionRequest(notionToken, `/pages/${encodeURIComponent(existingPageId)}`, {
        method: 'PATCH',
        body: JSON.stringify({ properties }),
      })
      : await notionRequest(notionToken, '/pages', {
        method: 'POST',
        body: JSON.stringify({
          parent: { type: 'data_source_id', data_source_id: schema.id },
          properties,
        }),
      });

    return { channel: 'notion', ok: true, status: saved.status };
  } catch (error) {
    console.error('Notion sync failed', error);
    return { channel: 'notion', ok: false, status: 0 };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  if (req.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405);
  }

  const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
  if (rateLimited(ip)) {
    return json({ error: 'rate_limited' }, 429);
  }

  let text = '';
  let contractId = '';
  try {
    const body = await req.json();
    if (typeof body?.text === 'string') text = body.text.trim();
    if (typeof body?.contract_id === 'string') contractId = body.contract_id.trim();
  } catch {
    text = '';
  }

  if (!text || text.length > MAX_TEXT_LENGTH) {
    return json({ error: 'invalid_text' }, 400);
  }
  if (contractId && !UUID_PATTERN.test(contractId)) {
    return json({ error: 'invalid_contract_id' }, 400);
  }

  const telegramToken = Deno.env.get('TELEGRAM_TOKEN')?.trim() ?? '';
  const telegramChat = Deno.env.get('TELEGRAM_CHAT')?.trim() ?? '';
  const web3formsKey = Deno.env.get('WEB3FORMS_ACCESS_KEY')?.trim() ?? '';
  const fromName = Deno.env.get('NOTIFY_FROM_NAME')?.trim() || 'موقع مأوى';
  const notionToken = Deno.env.get('NOTION_TOKEN')?.trim() ?? '';

  if (!telegramToken || !telegramChat || !web3formsKey) {
    return json({ error: 'notification_not_configured' }, 503);
  }
  if (contractId && !notionToken) {
    return json({ error: 'notion_not_configured' }, 503);
  }

  let contract: ContractRecord | null = null;
  let client: ClientRecord | null = null;
  let approvalUrl = '';
  if (contractId) {
    try {
      const details = await loadContractDetails(contractId);
      contract = details.contract;
      client = details.client;
      approvalUrl = await contractApprovalUrl(contractId);
    } catch (error) {
      console.error('Contract lookup failed', error);
      return json({ error: 'contract_lookup_failed' }, 502);
    }
  }

  const baseMessage = contract && client ? formatOrderNotification(contract, client) : text;
  const message = plainText(
    approvalUrl
      ? `${baseMessage}\n\nاعتماد العقد بعد تسجيل العربون في نوشن:\n${approvalUrl}`
      : baseMessage,
  );
  const telegramMessage = contract && client
    ? formatTelegramNotification(message)
    : escapeTelegramHtml(message);
  const jobs: Promise<DeliveryResult>[] = [];

  jobs.push(
    fetch(`https://api.telegram.org/bot${telegramToken}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: telegramChat,
        text: telegramMessage,
        parse_mode: 'HTML',
        disable_web_page_preview: true,
      }),
    })
      .then((response) => ({
        channel: 'telegram' as const,
        ok: response.ok,
        status: response.status,
      }))
      .catch(() => ({ channel: 'telegram' as const, ok: false, status: 0 })),
  );

  jobs.push(
    fetch('https://api.web3forms.com/submit', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        access_key: web3formsKey,
        subject: 'طلب جديد من موقع مأوى',
        from_name: fromName,
        message,
      }),
    })
      .then(async (response) => {
        const body = await response.json().catch(() => null);
        return {
          channel: 'web3forms' as const,
          ok: response.ok && body?.success === true,
          status: response.status,
        };
      })
      .catch(() => ({ channel: 'web3forms' as const, ok: false, status: 0 })),
  );

  if (contract && client) {
    jobs.push(syncContractToNotion(notionToken, contract, client, approvalUrl));
  }

  const results = await Promise.all(jobs);
  const failed = results.filter((result) => !result.ok);
  if (failed.length > 0) {
    console.error('Delivery failed', failed);
    return json({
      error: 'delivery_failed',
      failed_channels: failed.map((result) => result.channel),
      failed_statuses: Object.fromEntries(
        failed.map((result) => [result.channel, result.status]),
      ),
    }, 502);
  }

  return json({
    ok: true,
    channels: results.map((result) => result.channel),
  });
});
