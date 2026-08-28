const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const NOTION_VERSION = '2026-03-11';
const DATA_SOURCE_TITLE = 'إدارة طلبات مأوى';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...CORS, 'Content-Type': 'application/json' },
});

function bytesToHex(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function signatureFor(contractId: string, expires: number, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  return bytesToHex(new Uint8Array(await crypto.subtle.sign(
    'HMAC', key, new TextEncoder().encode(`${contractId}.${expires}`),
  )));
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return result === 0;
}

async function supabase(path: string, init: RequestInit = {}): Promise<any> {
  const url = Deno.env.get('SUPABASE_URL') || '';
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  const response = await fetch(`${url}${path}`, {
    ...init,
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', ...(init.headers || {}) },
  });
  const body = await response.json().catch(() => null);
  if (!response.ok) throw new Error(`supabase_${response.status}:${JSON.stringify(body)?.slice(0, 300)}`);
  return body;
}

async function notion(path: string, init: RequestInit = {}): Promise<any> {
  const token = Deno.env.get('NOTION_TOKEN') || '';
  const response = await fetch(`https://api.notion.com/v1${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${token}`, 'Notion-Version': NOTION_VERSION, 'Content-Type': 'application/json' },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`notion_${response.status}:${body?.message || ''}`);
  return body;
}

function plainText(items: any): string {
  return Array.isArray(items) ? items.map((item) => item?.plain_text || item?.text?.content || '').join('') : '';
}

async function dataSource(): Promise<any> {
  const configured = Deno.env.get('NOTION_ORDERS_DATA_SOURCE_ID')?.trim();
  if (configured) return notion(`/data_sources/${encodeURIComponent(configured)}`);
  const found = await notion('/search', {
    method: 'POST', body: JSON.stringify({ query: DATA_SOURCE_TITLE, filter: { property: 'object', value: 'data_source' }, page_size: 100 }),
  });
  const match = found.results?.find((item: any) => plainText(item.title) === DATA_SOURCE_TITLE);
  if (!match?.id) throw new Error('notion_data_source_not_found');
  return notion(`/data_sources/${encodeURIComponent(match.id)}`);
}

async function notionOrder(contractId: string): Promise<{ page: any; paid: number; extras: Record<string, unknown> }> {
  const schema = await dataSource();
  const result = await notion(`/data_sources/${encodeURIComponent(schema.id)}/query`, {
    method: 'POST',
    body: JSON.stringify({ filter: { property: 'ملاحظات', rich_text: { contains: contractId } }, page_size: 1 }),
  });
  const page = result.results?.[0];
  if (!page) throw new Error('notion_order_not_found');
  const paidProp = page.properties?.['إجمالي المدفوع من العميل'];
  const paid = Number(paidProp?.number ?? paidProp?.formula?.number ?? 0);
  const num = (name: string) => {
    const prop = page.properties?.[name];
    const value = Number(prop?.number ?? prop?.formula?.number ?? NaN);
    return Number.isFinite(value) ? value : 0;
  };
  const text = (name: string) => plainText(page.properties?.[name]?.rich_text || []).trim();
  const date = (name: string) => page.properties?.[name]?.date?.start || null;
  const extras = {
    base_package: num('قيمة الباقة الأساسية'),
    discount_amount: num('قيمة الخصم'),
    discount_reason: text('سبب الخصم'),
    shooting_date: date('موعد جلسة التصوير'),
    order_number: text('رقم الطلب'),
  };
  return { page, paid: Number.isFinite(paid) ? paid : 0, extras };
}

async function verifySignatureFor(contractId: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  return bytesToHex(new Uint8Array(await crypto.subtle.sign(
    'HMAC', key, new TextEncoder().encode(`verify:${contractId}`),
  ))).slice(0, 16);
}

async function loadContract(contractId: string): Promise<any> {
  const contracts = await supabase(`/rest/v1/contracts?id=eq.${contractId}&select=id,contract_number,client_id,service_type,total_amount,property_type,property_location,rooms_count,shoot_date,notes,created_at`);
  if (!contracts?.[0]) throw new Error('contract_not_found');
  const contract = contracts[0];
  const clients = await supabase(`/rest/v1/clients?id=eq.${contract.client_id}&select=id,full_name,phone_number,email`);
  const services = await supabase(`/rest/v1/contract_services?contract_id=eq.${contractId}&select=service_name,package_type`);
  if (!clients?.[0]) throw new Error('client_not_found');
  return { contract, client: clients[0], services: services || [] };
}

function pdfBase64(value: string): string {
  const comma = value.indexOf(',');
  const encoded = (comma >= 0 ? value.slice(comma + 1) : value).replace(/\s+/g, '');
  if (!encoded || encoded.length > 14_000_000) throw new Error('invalid_pdf');
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) throw new Error('invalid_pdf');
  return encoded;
}

function decodePdf(value: string): Uint8Array {
  let binary = '';
  try {
    binary = atob(pdfBase64(value));
  } catch {
    throw new Error('invalid_pdf');
  }
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  if (bytes.length < 100 || new TextDecoder().decode(bytes.slice(0, 5)) !== '%PDF-') throw new Error('invalid_pdf');
  return bytes;
}

function deliverableEmail(value: unknown): boolean {
  const email = String(value || '').trim().toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) &&
    !/\.(example|invalid|test)$/.test(email);
}

function buildContractEmail(details: any, paid: number, required: number): { html: string; text: string } {
  const contract = details.contract;
  const client = details.client;
  const total = Number(contract.total_amount || 0);
  const remaining = Math.max(0, total - paid);
  const number = escapeHtml(contract.contract_number || '—');
  const services = Array.isArray(details.services) && details.services.length
    ? details.services.map((item: any) => escapeHtml(item.service_name || 'خدمة تصوير عقاري'))
    : String(contract.service_type || 'خدمات تصوير عقاري').split(/[،,]/).map((item) => escapeHtml(item.trim())).filter(Boolean);
  const serviceRows = services.map((name: string, index: number) => `
    <tr>
      <td style="padding:13px 16px;border-bottom:1px solid #ece8e3;color:#817a74;font-size:13px;width:34px;">${index + 1}</td>
      <td style="padding:13px 0;border-bottom:1px solid #ece8e3;color:#201d1b;font-size:14px;font-weight:700;">${name}</td>
      <td style="padding:13px 16px;border-bottom:1px solid #ece8e3;color:#817a74;font-size:12px;text-align:left;">مشمول بالعقد</td>
    </tr>`).join('');
  const appointmentDate = shootDate(contract.shoot_date);
  const appointmentTime = shootTime(contract.notes);
  const appointment = appointmentDate ? `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:18px;background:#fff8e9;border:1px solid #ead8ad;border-radius:14px;">
      <tr><td style="padding:18px 20px;">
        <div style="font-size:11px;font-weight:800;letter-spacing:.8px;color:#926b17;margin-bottom:7px;">موعد جلسة التصوير</div>
        <div style="font-size:17px;font-weight:800;color:#2a251e;">${escapeHtml(appointmentDate)}</div>
        ${appointmentTime ? `<div style="font-size:14px;color:#6e6252;margin-top:3px;">وقت البداية: <strong>${escapeHtml(appointmentTime)}</strong></div>` : ''}
      </td></tr>
    </table>` : '';
  const infoRow = (label: string, value: unknown) => `
    <tr><td style="padding:8px 0;color:#857e78;font-size:13px;width:38%;">${label}</td><td style="padding:8px 0;color:#211e1c;font-size:13px;font-weight:700;">${escapeHtml(value || 'غير محدد')}</td></tr>`;
  const html = `<!doctype html>
<html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f2f0ed;font-family:Tahoma,Arial,sans-serif;color:#211e1c;direction:rtl;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">تم اعتماد عقد مأوى رقم ${number} وإرفاق نسختك الرسمية المختومة.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f2f0ed;"><tr><td align="center" style="padding:34px 14px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:640px;background:#fbfaf7;border:1px solid #ded9d3;border-radius:20px;overflow:hidden;box-shadow:0 12px 34px rgba(28,24,22,.08);">
    <tr><td style="height:5px;background:#a4243b;font-size:0;line-height:0;">&nbsp;</td></tr>
    <tr><td align="center" bgcolor="#090808" style="padding:24px 32px;background-color:#090808!important;color:#fff;text-align:center;">
      <img src="https://maawaa.sa/assets/logo2026/mawa-wide-white.svg" width="170" alt="مأوى" style="display:block;width:170px;max-width:100%;height:auto;margin:0 auto;border:0;outline:none;">
    </td></tr>
    <tr><td style="padding:34px 32px 10px;">
      <span style="display:inline-block;padding:7px 12px;border-radius:999px;background:#f7eff0;color:#a4243b;font-size:12px;font-weight:800;">تم اعتماد العقد وتأكيد الحجز</span>
      <h1 style="margin:18px 0 9px;font-size:27px;line-height:1.35;color:#171412;">عقدك الرسمي أصبح جاهزًا</h1>
      <p style="margin:0;color:#706963;font-size:15px;line-height:1.9;">مرحبًا <strong style="color:#211e1c;">${escapeHtml(client.full_name || 'عميلنا الكريم')}</strong>، تم اعتماد عقدك وختمه رسميًا من مأوى. أرفقنا النسخة النهائية بهذه الرسالة لسهولة الحفظ والرجوع إليها.</p>
    </td></tr>
    <tr><td style="padding:16px 32px 0;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#fff;border:1px solid #e5e0da;border-radius:14px;">
        <tr><td style="padding:18px 20px;border-bottom:1px solid #ece8e3;">
          <div style="font-size:11px;color:#8c847e;margin-bottom:5px;">رقم الطلب / العقد</div>
          <div dir="ltr" style="font-family:Arial,sans-serif;font-size:21px;font-weight:900;color:#a4243b;direction:ltr;unicode-bidi:isolate;text-align:right;"><span dir="ltr" style="direction:ltr;unicode-bidi:isolate;">${number}</span></div>
        </td></tr>
        <tr><td style="padding:12px 20px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0">
          ${infoRow('نوع العقار', propertyLabel(contract.property_type))}
          ${infoRow('الموقع', contract.property_location)}
          ${infoRow('عدد الغرف / المساحة', contract.rooms_count)}
          ${infoRow('رقم التواصل', client.phone_number)}
        </table></td></tr>
      </table>
      ${appointment}
    </td></tr>
    <tr><td style="padding:26px 32px 0;">
      <div style="font-size:16px;font-weight:900;margin-bottom:10px;">الخدمات المعتمدة</div>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#fff;border:1px solid #e5e0da;border-radius:14px;overflow:hidden;">${serviceRows}</table>
    </td></tr>
    <tr><td style="padding:26px 32px 0;">
      <div style="font-size:16px;font-weight:900;margin-bottom:10px;">الملخص المالي</div>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#151311;border-radius:14px;color:#fff;">
        <tr>
          <td style="padding:20px;border-left:1px solid #393431;"><div style="font-size:11px;color:#aaa29d;">إجمالي العقد</div><div style="margin-top:5px;font-size:18px;font-weight:900;">${formatSar(total)}</div></td>
          <td style="padding:20px;border-left:1px solid #393431;"><div style="font-size:11px;color:#aaa29d;">المدفوع</div><div style="margin-top:5px;font-size:18px;font-weight:900;color:#72d89d;">${formatSar(paid)}</div></td>
          <td style="padding:20px;"><div style="font-size:11px;color:#aaa29d;">المبلغ المعلّق</div><div style="margin-top:5px;font-size:18px;font-weight:900;color:#ff7b7b;">${formatSar(remaining)}</div></td>
        </tr>
      </table>
      ${paid >= required ? `<div style="margin-top:10px;color:#367452;font-size:12px;">تم استلام العربون المطلوب لتأكيد الحجز (${formatSar(required)}).</div>` : ''}
    </td></tr>
    <tr><td style="padding:26px 32px 0;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f7f3f1;border-right:4px solid #a4243b;border-radius:10px;"><tr><td style="padding:17px 18px;">
        <div style="font-size:13px;font-weight:900;color:#342e2a;">ملف العقد الرسمي مرفق</div>
        <div style="font-size:12px;color:#7b736d;margin-top:4px;line-height:1.7;">ستجد ملف PDF المتجهي المختوم مرفقًا بهذه الرسالة باسم عقد مأوى ${number}. احتفظ به ضمن مستندات الطلب.</div>
      </td></tr></table>
    </td></tr>
    <tr><td style="padding:28px 32px 34px;">
      <div style="font-size:15px;font-weight:900;margin-bottom:10px;">ماذا بعد؟</div>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
        <tr><td style="width:26px;vertical-align:top;color:#a4243b;font-weight:900;">01</td><td style="padding-bottom:10px;color:#655e58;font-size:13px;line-height:1.7;">سيبقى فريق مأوى على تواصل معك لتأكيد تفاصيل الجلسة والاستعدادات.</td></tr>
        <tr><td style="width:26px;vertical-align:top;color:#a4243b;font-weight:900;">02</td><td style="padding-bottom:10px;color:#655e58;font-size:13px;line-height:1.7;">يُرجى تجهيز العقار وإتاحة الدخول في الموعد المتفق عليه لضمان أفضل نتيجة.</td></tr>
        <tr><td style="width:26px;vertical-align:top;color:#a4243b;font-weight:900;">03</td><td style="color:#655e58;font-size:13px;line-height:1.7;">لأي تعديل أو استفسار، رُد مباشرة على هذه الرسالة أو تواصل معنا عبر واتساب.</td></tr>
      </table>
      <table role="presentation" cellpadding="0" cellspacing="0" style="margin-top:22px;"><tr><td style="background:#a4243b;border-radius:9px;"><a href="https://wa.me/966531646152" style="display:inline-block;padding:12px 20px;color:#fff;text-decoration:none;font-size:13px;font-weight:900;">التواصل مع فريق مأوى</a></td></tr></table>
    </td></tr>
    <tr><td style="padding:22px 32px;background:#ece8e3;color:#756e68;font-size:11px;line-height:1.8;text-align:center;">
      <strong style="color:#28231f;">مأوى للتصوير العقاري</strong><br>
      الرياض، المملكة العربية السعودية &nbsp;·&nbsp; +966 53 164 6152 &nbsp;·&nbsp; info@maawaa.sa<br>
      <span style="color:#9a928c;">هذه رسالة آلية مرتبطة بطلبك لدى مأوى.</span>
    </td></tr>
  </table>
</td></tr></table></body></html>`;
  const text = [
    `تم اعتماد عقد مأوى رقم ${contract.contract_number || '—'}`,
    `العميل: ${client.full_name || '—'}`,
    `الخدمات: ${services.join('، ')}`,
    appointmentDate ? `موعد التصوير: ${appointmentDate}${appointmentTime ? ` — ${appointmentTime}` : ''}` : '',
    `إجمالي العقد: ${formatSar(total)}`,
    `المدفوع: ${formatSar(paid)}`,
    `المتبقي: ${formatSar(remaining)}`,
    '', 'العقد الرسمي المختوم مرفق بهذه الرسالة.', 'مأوى للتصوير العقاري', '+966 53 164 6152', 'info@maawaa.sa',
  ].filter(Boolean).join('\n');
  return { html, text };
}

async function sendContract(contractId: string, pdfData: string, details: any, page: any): Promise<any> {
  const total = Number(details.contract.total_amount || 0);
  const { paid } = await notionOrder(contractId);
  const required = Math.round(total * 0.25 * 100) / 100;
  if (paid < required) return json({ error: 'deposit_not_received', paid, required }, 409);
  if (!details.client.email) return json({ error: 'customer_email_missing' }, 409);
  if (!deliverableEmail(details.client.email)) return json({ error: 'customer_email_invalid' }, 409);

  const existing = await supabase(`/rest/v1/contract_deliveries?contract_id=eq.${contractId}&select=status,sent_at`);
  if (existing?.[0]?.status === 'sent') return json({ error: 'already_sent', sent_at: existing[0].sent_at }, 409);

  await supabase('/rest/v1/contract_deliveries?on_conflict=contract_id', {
    method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
    body: JSON.stringify({ contract_id: contractId, status: 'processing', approved_at: new Date().toISOString(), recipient_email: details.client.email, updated_at: new Date().toISOString() }),
  });

  const pdf = decodePdf(pdfData);
  const safeNumber = String(details.contract.contract_number || contractId).replace(/[^A-Za-z0-9_-]/g, '-');
  const storagePath = `${contractId}/${safeNumber}.pdf`;
  const storageUrl = `${Deno.env.get('SUPABASE_URL')}/storage/v1/object/customer-contracts/${storagePath}`;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  const upload = await fetch(storageUrl, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/pdf', 'x-upsert': 'true' }, body: pdf });
  if (!upload.ok) throw new Error(`storage_${upload.status}`);

  const emailContent = buildContractEmail(details, paid, required);
  const email = await fetch('https://api.resend.com/emails', {
    method: 'POST', headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: 'مأوى للتصوير العقاري <info@maawaa.sa>', to: [details.client.email], subject,
      reply_to: 'info@maawaa.sa',
      html: emailContent.html,
      text: emailContent.text,
      attachments: [{ filename: `عقد-مأوى-${safeNumber}.pdf`, content: pdfBase64(pdfData) }],
    }),
  });
  const emailBody = await email.json().catch(() => ({}));

  const emailBody = await email.json().catch(() => ({}));
  if (!email.ok) throw new Error(`resend_${email.status}:${emailBody?.message || ''}`);

  // ثبّت نجاح الإرسال أولًا حتى لا يتكرر البريد إذا تعذر تحديث نوشن لاحقًا.
  await supabase(`/rest/v1/contract_deliveries?contract_id=eq.${contractId}`, {
    method: 'PATCH', headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({ status: 'sent', sent_at: new Date().toISOString(), storage_path: storagePath, resend_email_id: emailBody.id || null, last_error: null, updated_at: new Date().toISOString() }),
  });

  try {
    const signed = await supabase(`/storage/v1/object/sign/customer-contracts/${storagePath}`, { method: 'POST', body: JSON.stringify({ expiresIn: 31536000 }) });
    const fileUrl = `${Deno.env.get('SUPABASE_URL')}/storage/v1${signed.signedURL}`;
    const props: Record<string, any> = {};
    if (page.properties?.['حالة العقد']?.type === 'select') props['حالة العقد'] = { select: { name: 'تم الإرسال للعميل' } };
    if (page.properties?.['حالة العقد']?.type === 'status') props['حالة العقد'] = { status: { name: 'تم الإرسال للعميل' } };
    if (page.properties?.['العقد']?.type === 'files') props['العقد'] = { files: [{ name: `عقد مأوى ${safeNumber}.pdf`, type: 'external', external: { url: fileUrl } }] };
    if (Object.keys(props).length) await notion(`/pages/${encodeURIComponent(page.id)}`, { method: 'PATCH', body: JSON.stringify({ properties: props }) });
  } catch (error) {
    console.error('Contract sent, but Notion update failed', error);
  }
  return json({ ok: true, contract_number: details.contract.contract_number, recipient: details.client.email });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
    const contractId = String(body.contract_id || '');
    const expires = Number(body.expires || 0);
    const supplied = String(body.signature || '');

    // مسار التحقق العام — يُستخدم من صفحة verify.html عبر رمز QR على العقد
    if (body.action === 'verify') {
      const secret = Deno.env.get('CONTRACT_APPROVAL_SECRET') || '';
      if (!UUID.test(contractId) || !secret) return json({ error: 'invalid_request' }, 400);
      const expectedVerify = await verifySignatureFor(contractId, secret);
      if (!constantTimeEqual(supplied, expectedVerify)) return json({ valid: false });
      let payload: Record<string, unknown> = { valid: true };
      try {
        const details = await loadContract(contractId);
        const deliveries = await supabase(`/rest/v1/contract_deliveries?contract_id=eq.${contractId}&select=status,sent_at&limit=1`);
        payload = {
          valid: true,
          contract_number: details.contract.contract_number || '',
          client_name: details.client.full_name || '',
          total_amount: Number(details.contract.total_amount || 0),
          delivery_status: deliveries?.[0]?.status || 'pending',
        };
      } catch (error) {
        console.error('verify lookup failed', error);
      }
      return json(payload);
    }

    if (!UUID.test(contractId) || !Number.isInteger(expires) || expires < Math.floor(Date.now() / 1000)) return json({ error: 'invalid_or_expired_link' }, 401);
    const secret = Deno.env.get('CONTRACT_APPROVAL_SECRET') || '';
    const expected = await signatureFor(contractId, expires, secret);
    if (!secret || !constantTimeEqual(supplied, expected)) return json({ error: 'invalid_or_expired_link' }, 401);

    const details = await loadContract(contractId);
    const order = await notionOrder(contractId);
    const required = Math.round(Number(details.contract.total_amount || 0) * 0.25 * 100) / 100;
    const verifySig = secret ? await verifySignatureFor(contractId, secret) : '';
    const verifyUrl = verifySig ? `https://maawaa.sa/verify.html?c=${contractId}&s=${verifySig}` : '';
    if (body.action === 'preview') return json({ ok: true, ...details, payment: { paid: order.paid, required, sufficient: order.paid >= required }, notion: order.extras, verify: { url: verifyUrl } });
    if (body.action === 'email_preview') {
      const email = buildContractEmail(details, order.paid, required);
      return json({ ok: true, html: email.html, text: email.text });
    }
    if (body.action === 'send') return await sendContract(contractId, String(body.pdf_base64 || ''), details, order.page);
    return json({ error: 'invalid_action' }, 400);
  } catch (error) {
    console.error(error);
    const contractId = String(body.contract_id || '');
    const message = error instanceof Error ? error.message : String(error);
    if (UUID.test(contractId)) {
      await supabase(`/rest/v1/contract_deliveries?contract_id=eq.${contractId}`, {
        method: 'PATCH', headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({ status: 'failed', last_error: message.slice(0, 1000), updated_at: new Date().toISOString() }),
      }).catch(() => null);
    }
    const publicError = message.startsWith('resend_')
      ? 'email_delivery_failed'
      : message.startsWith('storage_')
      ? 'contract_storage_failed'
      : message === 'invalid_pdf'
      ? 'invalid_pdf'
      : 'contract_approval_failed';
    return json({ error: publicError }, 500);
  }
});
