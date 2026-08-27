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

async function notionOrder(contractId: string): Promise<{ page: any; paid: number }> {
  const schema = await dataSource();
  const result = await notion(`/data_sources/${encodeURIComponent(schema.id)}/query`, {
    method: 'POST',
    body: JSON.stringify({ filter: { property: 'ملاحظات', rich_text: { contains: contractId } }, page_size: 1 }),
  });
  const page = result.results?.[0];
  if (!page) throw new Error('notion_order_not_found');
  const paidProp = page.properties?.['إجمالي المدفوع من العميل'];
  const paid = Number(paidProp?.number ?? paidProp?.formula?.number ?? 0);
  return { page, paid: Number.isFinite(paid) ? paid : 0 };
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

function decodePdf(value: string): Uint8Array {
  const encoded = value.replace(/^data:application\/pdf;base64,/, '');
  if (!encoded || encoded.length > 14_000_000) throw new Error('invalid_pdf');
  const binary = atob(encoded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  if (bytes.length < 100 || new TextDecoder().decode(bytes.slice(0, 5)) !== '%PDF-') throw new Error('invalid_pdf');
  return bytes;
}

async function sendContract(contractId: string, pdfData: string, details: any, page: any): Promise<any> {
  const total = Number(details.contract.total_amount || 0);
  const { paid } = await notionOrder(contractId);
  const required = Math.round(total * 0.25 * 100) / 100;
  if (paid < required) return json({ error: 'deposit_not_received', paid, required }, 409);
  if (!details.client.email) return json({ error: 'customer_email_missing' }, 409);

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

  const resendKey = Deno.env.get('RESEND_API_KEY') || '';
  const subject = `عقد مأوى المعتمد — ${details.contract.contract_number || ''}`;
  const email = await fetch('https://api.resend.com/emails', {
    method: 'POST', headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: 'عقود مأوى <info@maawaa.sa>', to: [details.client.email], subject,
      html: `<div dir="rtl" style="font-family:Arial,sans-serif;line-height:1.9;color:#181818"><h2 style="color:#A4243B">عقد مأوى المعتمد</h2><p>مرحبًا ${details.client.full_name}،</p><p>نرفق لك عقد الطلب رقم <strong>${details.contract.contract_number || '—'}</strong> بعد اعتماده وختمه من مأوى.</p><p>تم تسجيل العربون وتأكيد الحجز. احتفظ بهذه الرسالة والعقد المرفق للرجوع إليهما.</p><p>مع التحية،<br><strong>مأوى للتصوير العقاري</strong><br>info@maawaa.sa</p></div>`,
      attachments: [{ filename: `عقد-مأوى-${safeNumber}.pdf`, content: pdfData.replace(/^data:application\/pdf;base64,/, '') }],
    }),
  });
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
  try {
    const body = await req.json();
    const contractId = String(body.contract_id || '');
    const expires = Number(body.expires || 0);
    const supplied = String(body.signature || '');
    if (!UUID.test(contractId) || !Number.isInteger(expires) || expires < Math.floor(Date.now() / 1000)) return json({ error: 'invalid_or_expired_link' }, 401);
    const secret = Deno.env.get('CONTRACT_APPROVAL_SECRET') || '';
    const expected = await signatureFor(contractId, expires, secret);
    if (!secret || !constantTimeEqual(supplied, expected)) return json({ error: 'invalid_or_expired_link' }, 401);

    const details = await loadContract(contractId);
    const order = await notionOrder(contractId);
    const required = Math.round(Number(details.contract.total_amount || 0) * 0.25 * 100) / 100;
    if (body.action === 'preview') return json({ ok: true, ...details, payment: { paid: order.paid, required, sufficient: order.paid >= required } });
    if (body.action === 'send') return await sendContract(contractId, String(body.pdf_base64 || ''), details, order.page);
    return json({ error: 'invalid_action' }, 400);
  } catch (error) {
    console.error(error);
    return json({ error: 'contract_approval_failed' }, 500);
  }
});
