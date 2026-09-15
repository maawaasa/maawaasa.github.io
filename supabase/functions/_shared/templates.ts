// =====================================================
// MAAWAA — Shared Email Templates (Phase 1 — Email-First)
// Arabic / RTL / Premium / Minimal
// أحداث العملاء: C-01..C-08, C-14..C-17
// أحداث الملاك/التشغيل: O-01..O-05, O-08
// كل قالب: variables واضحة + action_url واحد رئيسي حسب أفضل UX
// لا تعتمد على Customer Portal — direct action URLs فقط
// =====================================================

export const BRAND = {
  name: 'مأوى للتصوير العقاري',
  site: 'https://maawaa.sa',
  instagram: 'https://instagram.com/Maawaasa',
  customerEmail: 'info@maawaa.sa',
  whatsapp: '+966531646152',
  colors: {
    black: '#0B0B0B',
    wine: '#7A1F2B',
    deepWine: '#5C1620',
    offWhite: '#F7F5F2',
    white: '#FFFFFF',
    gray: '#6B6B6B',
  },
};

export type EmailRender = { subject: string; html: string; text: string };

const esc = (s: unknown): string =>
  String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

const C = BRAND.colors;

// ===== شريط حالة الطلب/الدفع =====
export type StatusTone = 'info' | 'success' | 'warning' | 'danger';
export type Status = { label: string; tone?: StatusTone; detail?: string };

const TONE: Record<StatusTone, { bg: string; edge: string; fg: string; mark: string }> = {
  info:    { bg: '#F5EEF0', edge: '#7A1F2B', fg: '#5C1620', mark: '◆' },
  success: { bg: '#EEF5EF', edge: '#2E7D46', fg: '#1F5433', mark: '✓' },
  warning: { bg: '#FBF3E3', edge: '#B7791F', fg: '#7A5316', mark: '!' },
  danger:  { bg: '#FBECEA', edge: '#B3392F', fg: '#7C261F', mark: '!' },
};

function statusHtml(s: Status): string {
  const t = TONE[s.tone ?? 'info'];
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 18px;">
<tr><td style="background:${t.bg};border-right:4px solid ${t.edge};border-radius:8px;padding:12px 16px;direction:rtl;text-align:right;">
  <span style="font-size:13.5px;font-weight:700;color:${t.fg};"><span dir="ltr">${t.mark}</span>&nbsp;&nbsp;${esc(s.label)}</span>
  ${s.detail ? `<div style="font-size:12px;color:${t.fg};margin-top:3px;opacity:.9;">${esc(s.detail)}</div>` : ''}
</td></tr></table>`;
}

// زر مضمون لـOutlook (جدول + خلية ملونة) — أساسي أو ثانوي
function btnHtml(url: string, label: string, kind: 'primary' | 'secondary'): string {
  const primary = kind === 'primary';
  return `<table role="presentation" cellpadding="0" cellspacing="0" align="center" style="margin:0 auto;"><tr><td align="center" bgcolor="${primary ? C.wine : C.white}" style="border-radius:12px;${primary ? `background:${C.wine};` : `border:2px solid ${C.wine};background:${C.white};`}">
<a class="ma-btn" href="${esc(url)}" target="_blank" style="display:inline-block;padding:14px 36px;font-family:inherit;font-size:15px;font-weight:700;color:${primary ? C.white : C.wine};text-decoration:none;border-radius:12px;text-align:center;">${esc(label)}</a>
</td></tr></table>`;
}

function layout(
  title: string,
  bodyHtml: string,
  cta?: { url: string; label: string },
  note?: string,
  status?: Status,
  secondary?: { url: string; label: string },
  preheader?: string
): string {
  const pre = esc(preheader || title);
  const banner = status ? statusHtml(status) : '';
  const ctaHtml = cta
    ? `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:22px;"><tr><td align="center">
        ${btnHtml(cta.url, cta.label, 'primary')}
        ${secondary ? `<div style="height:10px;line-height:10px;font-size:0;">&nbsp;</div>${btnHtml(secondary.url, secondary.label, 'secondary')}` : ''}
      </td></tr></table>`
    : '';
  const noteHtml = note
    ? `<p style="margin:16px 0 0;font-size:12px;color:${C.gray};line-height:1.9;">${esc(note)}</p>`
    : '';
  return `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>${esc(title)}</title>
<style>
  @media only screen and (max-width:600px){
    .ma-card{width:100%!important;border-radius:0!important}
    .ma-head{padding:18px 16px!important}
    .ma-body{padding:26px 18px 10px!important}
    .ma-h1{font-size:17px!important}
    .ma-foot{padding:16px 18px 24px!important}
    .ma-btn{display:block!important}
  }
</style>
</head>
<body style="margin:0;padding:0;width:100%;background:${C.offWhite};font-family:'IBM Plex Sans Arabic','Segoe UI',Tahoma,Arial,sans-serif;-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%;">
<div style="display:none;max-height:0;max-width:0;overflow:hidden;opacity:0;font-size:1px;line-height:1px;color:transparent;mso-hide:all;">${pre}&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${C.offWhite};">
<tr><td align="center" style="padding:26px 12px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" class="ma-card" style="max-width:560px;background:${C.white};border-radius:16px;overflow:hidden;border:1px solid #ECE8E0;direction:rtl;">
    <tr><td style="height:5px;background:${C.wine};font-size:0;line-height:0;">&nbsp;</td></tr>
    <tr><td class="ma-head" align="center" style="background:${C.black};padding:22px 28px;direction:rtl;">
      <div style="color:${C.white};font-size:21px;font-weight:700;">مأوى<span style="color:#C9506A;">.</span></div>
      <div style="color:#A19B97;font-size:11px;margin-top:4px;">للتصوير العقاري</div>
    </td></tr>
    <tr><td class="ma-body" style="padding:30px 30px 12px;direction:rtl;text-align:right;">
      ${banner}
      <h1 class="ma-h1" style="margin:0 0 16px;font-size:18px;color:${C.black};line-height:1.7;text-align:right;">${esc(title)}</h1>
      ${bodyHtml}
      ${ctaHtml}
      ${noteHtml}
    </td></tr>
    <tr><td class="ma-foot" style="padding:18px 30px 26px;border-top:1px solid #ECE8E0;" align="center">
      <div style="font-size:12px;color:${C.gray};line-height:2;direction:rtl;">
        ${esc(BRAND.name)} · <a href="${BRAND.site}" style="color:${C.wine};text-decoration:none;">maawaa.sa</a>
        · <a href="mailto:${BRAND.customerEmail}" style="color:${C.wine};text-decoration:none;">${BRAND.customerEmail}</a>
        · <a href="${BRAND.instagram}" style="color:${C.wine};text-decoration:none;">إنستغرام</a>
        <br><span dir="ltr">${esc(BRAND.whatsapp)}</span>
        <br><span style="font-size:11px;color:#A19B97;">رسالة آلية من مأوى — لالتواصل مع الفريق: ${esc(BRAND.customerEmail)}</span>
      </div>
    </td></tr>
  </table>
</td></tr></table>
</body></html>`;
}

function kv(rows: Array<[string, unknown]>): string {
  const hasAr = (v: unknown) => /[\u0600-\u06FF]/.test(String(v ?? ''));
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:6px 0 2px;">${rows
    .filter(([, v]) => v !== undefined && v !== null && String(v) !== '')
    .map(([k, v]) => {
      const dir = hasAr(v) ? 'rtl' : 'ltr';
      return `<tr>` +
        `<td style="padding:8px 0;border-bottom:1px dashed #ECE8E0;font-size:13px;color:${C.gray};white-space:nowrap;">${esc(k)}</td>` +
        `<td style="padding:8px 0;border-bottom:1px dashed #ECE8E0;font-size:13px;font-weight:700;color:${C.black};text-align:left;"><span dir="${dir}">${esc(v)}</span></td>` +
        `</tr>`;
    })
    .join('')}</table>`;
}

const p = (t: string) => `<p style="margin:0 0 12px;font-size:14px;color:#3A3A3A;line-height:2;">${esc(t)}</p>`;
const fmt = (n: unknown) => `${Number(n ?? 0).toLocaleString('en-US')} ر.س`;
const WA_LINK = 'https://wa.me/' + BRAND.whatsapp.replace(/[^0-9]/g, '');
const WA_BTN = { url: WA_LINK, label: 'تواصل عبر واتساب' };

// =====================================================
// أنواع البيانات المشتركة
// =====================================================
export type QuoteCtx = {
  quote_number: string;
  total: number;
  valid_until: string;
  summary?: string;
  quote_url?: string;
  client_name?: string;
};
export type ContractCtx = {
  contract_number?: string;
  client_name?: string;
  total?: number;
  deposit?: number;
  remaining?: number;
  shoot_date?: string | null;
  shoot_time?: string | null;
  location?: string | null;
  services?: string | null;
  contract_url?: string;
  calendar_url?: string;
  deposit_upload_url?: string;
  balance_upload_url?: string;
  delivery_url?: string;
  maps_url?: string;
};

// =====================================================
// C — إيميلات العملاء
// =====================================================
export function C01_quoteReady(q: QuoteCtx): EmailRender {
  return {
    subject: `عرض السعر ${q.quote_number} جاهز — مأوى`,
    html: layout(
      'عرض السعر جاهز',
      p(`عزيزنا ${q.client_name || 'العميل الكريم'}،`) +
        p('أرفقنا لك تفاصيل عرض السعر كما تم تحضيره من فريق مأوى:') +
        kv([
          ['رقم العرض', q.quote_number],
          ['الإجمالي', fmt(q.total)],
          ['الصلاحية حتى', q.valid_until],
          ['الخدمات', q.summary || '—'],
        ]),
      q.quote_url ? { url: q.quote_url, label: 'عرض تفاصيل عرض السعر' } : undefined,
      'العرض سارٍ 14 يومًا من تاريخه. لا يتم إنشاء أي حجز تلقائيًا.',
      { label: 'عرض سعر جديد — بانتظار ردك', tone: 'info' }
    ),
    text: `عرض السعر ${q.quote_number} جاهز. الإجمالي ${fmt(q.total)} — الصلاحية حتى ${q.valid_until}. ${q.quote_url || ''}`,
  };
}

export function C02_quoteExpired(q: QuoteCtx): EmailRender {
  return {
    subject: `انتهت صلاحية عرض السعر ${q.quote_number} — مأوى`,
    html: layout(
      'انتهت صلاحية عرض السعر',
      p(`انتهت صلاحية عرض السعر رقم ${q.quote_number} (${fmt(q.total)}).`) +
        p('يمكنك طلب تحديث العرض بأحدث الأسعار في أي وقت — يسرّنا خدمتك.'),
      q.quote_url ? { url: q.quote_url, label: 'طلب تحديث عرض السعر' } : undefined,
      undefined,
      { label: 'انتهت صلاحية العرض', tone: 'danger' }
    ),
    text: `انتهت صلاحية عرض السعر ${q.quote_number}. لتحديث العرض تواصل معنا.`,
  };
}

export function C03_bookingReceived(c: ContractCtx): EmailRender {
  return {
    subject: `تم استلام طلب الحجز ${c.contract_number || ''} — مأوى`,
    html: layout(
      'تم استلام طلب الحجز',
      p(`عزيزنا ${c.client_name || 'العميل الكريم'}،`) +
        p('وصلنا طلبك بنجاح، وفريق مأوى يراجعه الآن. لا يلزمك أي إجراء في هذه المرحلة.') +
        kv([
          ['رقم الطلب', c.contract_number],
          ['الخدمات', c.services],
          ['الموعد المطلوب', c.shoot_date ? `${c.shoot_date}${c.shoot_time ? ' — ' + c.shoot_time : ''}` : '—'],
          ['الموقع', c.location],
        ]),
      undefined,
      'سنراسلك عند الحاجة للخطوة التالية — تأكيد التغطية وتوفر الموعد ثم بيانات العربون.',
      { label: 'تم الاستلام — قيد المراجعة', tone: 'info', detail: 'لا يلزمك أي إجراء الآن' }
    ),
    text: `تم استلام طلب الحجز ${c.contract_number}. سنتواصل معك عند الحاجة للخطوة التالية.`,
  };
}

export function C04_depositHold(c: ContractCtx): EmailRender {
  return {
    subject: `لديك 24 ساعة لتثبيت موعدك ${c.contract_number || ''} — مأوى`,
    html: layout(
      'موعدك محفوظ مؤقتًا — أكمل العربون خلال 24 ساعة',
      p('تم تأكيد تغطية الجلسة وتوفر الموعد والمعدات، وحُفظ موعدك مؤقتًا لمدة 24 ساعة.') +
        kv([
          ['رقم الطلب', c.contract_number],
          ['العربون المطلوب (25%)', fmt(c.deposit)],
          ['الإجمالي', fmt(c.total)],
          ['المتبقي بعد الجلسة', fmt(c.remaining)],
        ]) +
        p('حوّل العربون وارفع الإيصال خلال المهلة لتثبيت الموعد نهائيًا.'),
      c.deposit_upload_url ? { url: c.deposit_upload_url, label: 'رفع إيصال العربون' } : undefined,
      'بعد رفع الإيصال يبقى موعدك محفوظًا أثناء مراجعة مأوى — لن تخسر الموعد بسبب مدة المراجعة.',
      { label: 'بانتظار العربون — مهلة 24 ساعة', tone: 'warning', detail: 'موعدك محفوظ مؤقتًا ولا يثبت إلا برفع الإيصال' },
      WA_BTN,
      'خطوة واحدة متبقية: تحويل العربون ورفع الإيصال خلال 24 ساعة'
    ),
    text: `موعدك محفوظ 24 ساعة. العربون ${fmt(c.deposit)} — ارفع الإيصال: ${c.deposit_upload_url || ''}`,
  };
}

export function C05_receiptReceived(c: ContractCtx): EmailRender {
  return {
    subject: `استلمنا إيصال العربون ${c.contract_number || ''} — مأوى`,
    html: layout(
      'استلمنا إيصال العربون',
      p('وصلنا إيصال التحويل بنجاح، وهو الآن تحت المراجعة من فريق مأوى.') +
        kv([['رقم الطلب', c.contract_number], ['الموعد', c.shoot_date]]),
      undefined,
      'موعدك يبقى محفوظًا أثناء المراجعة — سنؤكد لك الحجز فور اعتماد الدفعة.',
      { label: 'الإيصال تحت المراجعة', tone: 'info', detail: 'موعدك محفوظ — لا يلزمك أي إجراء' }
    ),
    text: `استلمنا إيصال العربون لطلب ${c.contract_number} وهو تحت المراجعة. موعدك محفوظ.`,
  };
}

export function C06_receiptCorrection(c: ContractCtx): EmailRender {
  return {
    subject: `إيصال العربون يحتاج إعادة رفع ${c.contract_number || ''} — مأوى`,
    html: layout(
      'الإيصال يحتاج إعادة رفع',
      p('الإيصال المرفوع غير واضح أو غير مطابق للمبلغ المطلوب. نرجو إعادة رفع إيصال واضح خلال ساعات، فموعدك يبقى محفوظًا مؤقتًا.'),
      c.deposit_upload_url ? { url: c.deposit_upload_url, label: 'إعادة رفع الإيصال' } : undefined,
      undefined,
      { label: 'يحتاج إجراء منك — إعادة رفع الإيصال', tone: 'danger', detail: 'موعدك يبقى محفوظًا مؤقتًا' }
    ),
    text: `يرجى إعادة رفع إيصال العربون واضحًا: ${c.deposit_upload_url || ''}`,
  };
}

export function C07_holdExpired(c: ContractCtx): EmailRender {
  return {
    subject: `انتهت مهلة تثبيت الموعد ${c.contract_number || ''} — مأوى`,
    html: layout(
      'انتهت مهلة الـ24 ساعة',
      p('انتهت مهلة تثبيت الموعد دون استلام إيصال العربون، وتم تحرير الحجز المؤقت.') +
        p('إن كنت ما زلت مهتمًا، يمكنك طلب موعد جديد وسنحاول توفيره.'),
      c.calendar_url ? { url: c.calendar_url, label: 'طلب موعد جديد' } : undefined,
      undefined,
      { label: 'انتهت المهلة — تم تحرير الحجز المؤقت', tone: 'danger' }
    ),
    text: `انتهت مهلة العربون للطلب ${c.contract_number} وحُرر الحجز المؤقت. لطلب موعد جديد: ${c.calendar_url || ''}`,
  };
}

export function C08_bookingConfirmed(c: ContractCtx): EmailRender {
  return {
    subject: `تم تأكيد حجزك ${c.contract_number || ''} — مأوى`,
    html: layout(
      'حجزك مؤكد — نراك يوم الجلسة',
      p(`عزيزنا ${c.client_name || 'العميل الكريم'}،`) +
        p('تم اعتماد العربون وتأكيد الحجز. هذه تفاصيل جلستك:') +
        kv([
          ['رقم الطلب', c.contract_number],
          ['الموعد', c.shoot_date ? `${c.shoot_date}${c.shoot_time ? ' — ' + c.shoot_time : ''}` : '—'],
          ['الموقع', c.location],
          ['الخدمات', c.services],
          ['المدفوع', fmt(c.deposit)],
          ['المتبقي قبل التسليم', fmt(c.remaining)],
        ]) +
        p('ستجد العقد مرفقًا/متاحًا عبر الزر، ويمكنك إضافة الموعد لتقويمك.'),
      c.contract_url ? { url: c.contract_url, label: 'عرض العقد وتفاصيل الجلسة' } : undefined,
      'التسليم القياسي خلال 7–10 أيام عمل من اليوم التالي لاكتمال الجلسة.',
      { label: 'الحجز مؤكد — العربون معتمد', tone: 'success', detail: 'لا يلزمك أي إجراء دفع الآن — نراك يوم الجلسة' },
      undefined,
      `تم تأكيد حجزك ${c.contract_number || ''} — نراك يوم الجلسة`
    ),
    text: `حجزك ${c.contract_number} مؤكد — ${c.shoot_date || ''} ${c.shoot_time || ''}. العقد: ${c.contract_url || ''}`,
  };
}

export function C14_readyBalance(c: ContractCtx): EmailRender {
  return {
    subject: `مخرجاتك جاهزة — المتبقي ${fmt(c.remaining)} ${c.contract_number || ''} — مأوى`,
    html: layout(
      'المخرجات جاهزة — يتبقى سداد الرصيد',
      p('اكتملت معالجة مخرجات جلستك وهي جاهزة للتسليم النهائي.') +
        kv([['رقم الطلب', c.contract_number], ['المتبقي المطلوب', fmt(c.remaining)]]),
      c.balance_upload_url ? { url: c.balance_upload_url, label: 'رفع إيصال السداد النهائي' } : undefined,
      'التسليم النهائي يتم بعد اكتمال السداد مباشرة.',
      { label: 'بانتظار السداد النهائي', tone: 'warning', detail: 'المخرجات جاهزة والتسليم ينتظر اكتمال السداد' }
    ),
    text: `مخرجاتك جاهزة — المتبقي ${fmt(c.remaining)}. ارفع الإيصال: ${c.balance_upload_url || ''}`,
  };
}

export function C15_finalReceiptReceived(c: ContractCtx): EmailRender {
  return {
    subject: `استلمنا إيصال السداد النهائي ${c.contract_number || ''} — مأوى`,
    html: layout(
      'استلمنا إيصال السداد النهائي',
      p('إثبات السداد النهائي تحت التحقق الآن. بمجرد الاعتماد يصلك رابط التسليم النهائي مباشرة.'),
      undefined,
      'لا يلزمك أي إجراء الآن.',
      { label: 'الإيصال تحت التحقق', tone: 'info' }
    ),
    text: `استلمنا إيصال السداد النهائي للطلب ${c.contract_number} وهو تحت التحقق.`,
  };
}

export function C16_finalReceiptCorrection(c: ContractCtx): EmailRender {
  return {
    subject: `إيصال السداد النهائي يحتاج إعادة رفع ${c.contract_number || ''} — مأوى`,
    html: layout(
      'إيصال السداد يحتاج إعادة رفع',
      p('إثبات السداد النهائي غير واضح أو غير مطابق للمبلغ. نرجو إعادة رفع إيصال واضح لتسليم مخرجاتك سريعًا.'),
      c.balance_upload_url ? { url: c.balance_upload_url, label: 'إعادة رفع الإيصال' } : undefined,
      undefined,
      { label: 'يحتاج إجراء منك — إعادة رفع الإيصال', tone: 'danger' }
    ),
    text: `يرجى إعادة رفع إيصال السداد النهائي: ${c.balance_upload_url || ''}`,
  };
}

export function C17_delivery(c: ContractCtx): EmailRender {
  return {
    subject: `مخرجاتك جاهزة للتحميل ${c.contract_number || ''} — مأوى`,
    html: layout(
      'مخرجاتك جاهزة',
      p(`عزيزنا ${c.client_name || 'العميل الكريم'}،`) +
        p('مخرجات جلستك المعالجة جاهزة الآن عبر الرابط:') +
        kv([['رقم الطلب', c.contract_number], ['التسليم', 'مخرجات معالجة فقط — RAW غير مشمول']]),
      c.delivery_url ? { url: c.delivery_url, label: 'فتح وتحميل المخرجات' } : undefined,
      'الملفات تُحفظ 30 يومًا من التسليم. لك جولة تعديلات طفيفة واحدة خلال 7 أيام من اليوم.',
      { label: 'جاهز للتحميل', tone: 'success', detail: 'المخرجات مكتملة — الحفظ 30 يومًا من الآن' },
      WA_BTN,
      `مخرجات طلبك ${c.contract_number || ''} جاهزة للتحميل`
    ),
    text: `مخرجاتك جاهزة: ${c.delivery_url || ''} — الحفظ 30 يومًا، التعديلات الطفيفة خلال 7 أيام.`,
  };
}

// =====================================================
// O — إيميلات الملاك / التشغيل
// =====================================================
export function O01_newOrder(c: ContractCtx & { client_phone?: string; suggested_photographer?: string }): EmailRender {
  return {
    subject: `طلب جديد يحتاج تأكيد تغطية — ${c.contract_number || ''}`,
    html: layout(
      'طلب جديد يحتاج تأكيد تغطية الجلسة',
      kv([
        ['الطلب', c.contract_number],
        ['العميل', c.client_name],
        ['الجوال', c.client_phone],
        ['الخدمات', c.services],
        ['الموعد المطلوب', c.shoot_date ? `${c.shoot_date}${c.shoot_time ? ' — ' + c.shoot_time : ''}` : '—'],
        ['الموقع', c.location],
        ['المصور المقترح', c.suggested_photographer || '—'],
      ]) +
        p('المصور المقترح اقتراح فقط — التأكيد محايد لأي مالك.'),
      c.contract_url ? { url: c.contract_url, label: 'تأكيد تغطية الجلسة' } : undefined
    ),
    text: `طلب جديد ${c.contract_number} — ${c.client_name} — ${c.services} — ${c.shoot_date || ''}. المصور المقترح: ${c.suggested_photographer || '—'}`,
  };
}

export function O02_assigned(c: ContractCtx & { photographer?: string }): EmailRender {
  return {
    subject: `تحديد المصور المسؤول — ${c.contract_number || ''}`,
    html: layout(
      'تم تحديد المصور المسؤول',
      kv([
        ['الطلب', c.contract_number],
        ['المصور المسؤول', c.photographer],
        ['الموعد', c.shoot_date],
      ]),
      undefined,
      'قبل الجلسة يتم التحقق النهائي من توفر المصور والمعدات والموعد.'
    ),
    text: `تم تحديد المصور ${c.photographer || ''} للطلب ${c.contract_number}.`,
  };
}

export function O03_receiptReview(c: ContractCtx & { amount?: number; review_url?: string }): EmailRender {
  return {
    subject: `إيصال دفعة بانتظار المراجعة — ${c.contract_number || ''}`,
    html: layout(
      'إيصال دفعة بانتظار المراجعة',
      kv([
        ['الطلب', c.contract_number],
        ['العميل', c.client_name],
        ['المبلغ المرفوع', fmt(c.amount)],
        ['الموعد المحفوظ', c.shoot_date],
      ]),
      c.review_url ? { url: c.review_url, label: 'مراجعة الإيصال' } : undefined,
      'الموعد محفوظ أثناء المراجعة — الاعتماد يثبت الحجز.'
    ),
    text: `إيصال دفعة بانتظار المراجعة للطلب ${c.contract_number} بمبلغ ${fmt(c.amount)}.`,
  };
}

export function O04_orderNeedsAction(c: ContractCtx & { reason?: string; action_url?: string }): EmailRender {
  return {
    subject: `طلب يحتاج إجراء — ${c.contract_number || ''}`,
    html: layout(
      'طلب يحتاج إجراء',
      kv([
        ['الطلب', c.contract_number],
        ['السبب', c.reason],
        ['العميل', c.client_name],
      ]),
      c.action_url ? { url: c.action_url, label: 'فتح الطلب' } : undefined
    ),
    text: `الطلب ${c.contract_number} يحتاج إجراء: ${c.reason || ''}`,
  };
}

export function O05_bookingConfirmed(c: ContractCtx & { photographer?: string; equipment?: string }): EmailRender {
  return {
    subject: `حجز مؤكد — ${c.contract_number || ''}`,
    html: layout(
      'تم تأكيد الحجز واعتماد العربون',
      kv([
        ['الطلب', c.contract_number],
        ['العميل', c.client_name],
        ['الموعد', c.shoot_date ? `${c.shoot_date}${c.shoot_time ? ' — ' + c.shoot_time : ''}` : '—'],
        ['الموقع', c.location],
        ['الخدمات', c.services],
        ['المصور المسؤول', c.photographer || '—'],
        ['المعدات', c.equipment || '—'],
      ])
    ),
    text: `حجز مؤكد ${c.contract_number} — ${c.shoot_date || ''} — ${c.location || ''}`,
  };
}

export function O08_photographerReminder(
  c: ContractCtx & { photographer_name?: string; photographer_email?: string }
): EmailRender {
  return {
    subject: `تذكير: جلسة غدًا — ${c.contract_number || ''}`,
    html: layout(
      'جلسة التصوير غدًا',
      p(`مرحبًا ${c.photographer_name || ''}،`) +
        kv([
          ['الطلب', c.contract_number],
          ['الموعد', c.shoot_date ? `${c.shoot_date} — ${c.shoot_time || ''}` : '—'],
          ['الموقع', c.location],
          ['الخدمات', c.services],
          ['العميل', c.client_name],
        ]),
      c.maps_url ? { url: c.maps_url, label: 'فتح الموقع على الخرائط' } : undefined,
      'تأكد من تجهيز المعدات والتحقق من الوصول قبل الموعد بساعة.'
    ),
    text: `تذكير: جلسة ${c.contract_number} غدًا ${c.shoot_time || ''} — ${c.location || ''}`,
  };
}

// =====================================================
// P1 — أحداث إضافية (C-09..C-20، O-06..O-12)
// =====================================================

export function C09_contractReady(c: ContractCtx): EmailRender {
  return {
    subject: `عقد جلستك جاهز ${c.contract_number || ''} — مأوى`,
    html: layout(
      'عقد جلستك جاهز',
      p('أصبح عقد جلستك جاهزًا للاطلاع والاعتماد.') +
        kv([['رقم الطلب', c.contract_number], ['الموعد', c.shoot_date]]),
      c.contract_url ? { url: c.contract_url, label: 'عرض العقد' } : undefined,
      undefined,
      { label: 'العقد جاهز للاطلاع والاعتماد', tone: 'info' }
    ),
    text: `عقد جلستك ${c.contract_number} جاهز: ${c.contract_url || ''}`,
  };
}

export function C10_appointmentUpdated(c: ContractCtx): EmailRender {
  return {
    subject: `تحديث موعد جلستك ${c.contract_number || ''} — مأوى`,
    html: layout(
      'تم تحديث موعد جلستك',
      p('بعد الاعتماد، هذا موعد جلستك الجديد:') +
        kv([
          ['رقم الطلب', c.contract_number],
          ['الموعد الجديد', c.shoot_date ? `${c.shoot_date}${c.shoot_time ? ' — ' + c.shoot_time : ''}` : '—'],
          ['الموقع', c.location],
        ]),
      c.calendar_url ? { url: c.calendar_url, label: 'تحديث الموعد في تقويمي' } : undefined,
      undefined,
      { label: 'تم تحديث الموعد', tone: 'info' }
    ),
    text: `موعدك الجديد: ${c.shoot_date || ''} ${c.shoot_time || ''} — ${c.location || ''}`,
  };
}

export function C11_shootReminder(c: ContractCtx): EmailRender {
  return {
    subject: `تذكير: جلستك غدًا ${c.shoot_time || ''} — مأوى`,
    html: layout(
      'جلستك غدًا — نحن بانتظارك',
      p('تذكير سريع بجلسة التصوير غدًا. لضمان أفضل نتيجة:') +
        kv([
          ['الموعد', c.shoot_date ? `${c.shoot_date}${c.shoot_time ? ' — ' + c.shoot_time : ''}` : '—'],
          ['الموقع', c.location],
        ]) +
        p('العقار نظيف ومرتب، جميع الإضاءات تعمل، وإخلاء مدخل الواجهة من السيارات إن أمكن.'),
      c.maps_url ? { url: c.maps_url, label: 'فتح الموقع على الخرائط' } : undefined,
      undefined,
      { label: 'غدًا جلسة التصوير', tone: 'info' }
    ),
    text: `تذكير: جلستك غدًا ${c.shoot_time || ''} — ${c.location || ''}`,
  };
}

export type C12Variant = 'client_cancellation' | 'maawaa_cancellation' | 'force_majeure' | 'late_30' | 'no_show' | 'visit_fee' | 'reschedule';
export function C12_operationalUpdate(c: ContractCtx, variant: C12Variant): EmailRender {
  const m: Record<C12Variant, { t: string; b: string }> = {
    client_cancellation: {
      t: 'إلغاء الجلسة — بطلبكم',
      b: p('تم إلغاء الجلسة بطلبكم.') + p('وفق شروط العقد: الإلغاء قبل أكثر من 48 ساعة يمنح إعادة جدولة مجانية واحدة أو استرداد 50٪ من العربون؛ ومن 24 إلى 48 ساعة يُسترد 50٪ من العربون دون إعادة جدولة؛ وأقل من 24 ساعة أو التأخر أكثر من 30 دقيقة أو عدم الحضور فالعربون غير مسترد.'),
    },
    maawaa_cancellation: {
      t: 'إلغاء الجلسة من مأوى',
      b: p('نعتذر، ألغت مأوى الجلسة لسبب يرجع إليها.') + p('يُسترد كامل ما دُفع عن الخدمة غير المنفذة أو تُعاد الجدولة باتفاقكم — كما ينص العقد.'),
    },
    force_majeure: {
      t: 'تعذر تنفيذ الجلسة — قوة قاهرة',
      b: p('تعذر تنفيذ الجلسة بسبب خارج عن سيطرة مأوى المعقولة (حالة جوية مانعة، أوامر جهات، إغلاق موقع، أو عطل طارئ غير ناتج عن إهمال).') + p('يُعلَّق التنفيذ أو تُعاد الجدولة حتى زوال السبب وفق العقد، وسنتواصل معكم لحسم الموعد البديل.'),
    },
    late_30: {
      t: 'تأخر عن الجلسة أكثر من 30 دقيقة',
      b: p('سجلنا تأخر بدء الجلسة أكثر من 30 دقيقة عن الموعد المتفق عليه.') + p('وفق العقد: العربون غير مسترد في هذه الحالة، ويمكن الاتفاق على إعادة جدولة بشروط العقد.'),
    },
    no_show: {
      t: 'عدم الحضور إلى الجلسة',
      b: p('لم يتمكن فريق مأوى من بدء الجلسة لعدم توفر إمكانية الدخول أو عدم حضور من يتسلم العقار.') + p('وفق العقد: العربون غير مسترد عند عدم الحضور، ويمكن طلب جلسة جديدة بمقابل.'),
    },
    visit_fee: {
      t: 'رسوم زيارة مطبقة',
      b: p('تعذر بدء التصوير أو استكماله لسبب راجع للعقار أو ضمن مسؤوليته (عدم السماح بالدخول، عدم الجاهزية، غياب تصاريح، انقطاع كهرباء).') + p('وفق العقد تُحتسب رسوم زيارة بنسبة 25٪ من قيمة العمل، دون اعتبار ذلك إخلالًا من مأوى.'),
    },
    reschedule: {
      t: 'إعادة جدولة الجلسة',
      b: p('تمت إعادة جدولة جلستك بالتفاهم معكم.') + kv([['الموعد الجديد', c.shoot_date ? `${c.shoot_date}${c.shoot_time ? ' — ' + c.shoot_time : ''}` : '—']]),
    },
  };
  const v = m[variant];
  const tone: StatusTone = variant === 'reschedule' ? 'info'
    : variant === 'force_majeure' || variant === 'visit_fee' ? 'warning' : 'danger';
  return {
    subject: `${v.t} — ${c.contract_number || ''} — مأوى`,
    html: layout(v.t, kv([['رقم الطلب', c.contract_number]]) + v.b,
      variant === 'reschedule' && c.calendar_url ? { url: c.calendar_url, label: 'تحديث التقويم' } : undefined,
      undefined,
      { label: v.t, tone }),
    text: `${v.t} — الطلب ${c.contract_number}. التفاصيل وفق العقد.`,
  };
}

export function C13_processingStarted(c: ContractCtx): EmailRender {
  return {
    subject: `جلسة مكتملة — بدأت المعالجة ${c.contract_number || ''} — مأوى`,
    html: layout(
      'بدأت معالجة مخرجات جلستك',
      p('اكتملت جلسة التصوير بنجاح، ومخرجاتك الآن في مرحلة المعالجة (تصحيح ألوان وتدقيق).') +
        kv([
          ['رقم الطلب', c.contract_number],
          ['التسليم القياسي', '7–10 أيام عمل من اليوم التالي للجلسة'],
        ]),
      undefined,
      'لا يلزمك أي إجراء الآن — سنخبرك عند الجاهزية.',
      { label: 'قيد المعالجة', tone: 'info', detail: 'التسليم خلال 7–10 أيام عمل' }
    ),
    text: `بدأت معالجة مخرجات الطلب ${c.contract_number}. التسليم خلال 7–10 أيام عمل.`,
  };
}

export function C18_retentionReminder(c: ContractCtx): EmailRender {
  return {
    subject: `تذكير: ملفاتك تُحفظ 30 يومًا ${c.contract_number || ''} — مأوى`,
    html: layout(
      'ملفاتك محفوظة لمدة محدودة',
      p('نذكّرك بأن ملفات جلستك تُحفظ على سحابة مأوى 30 يومًا من تاريخ التسليم ثم تُحذف تلقائيًا.') +
        kv([['رقم الطلب', c.contract_number]]),
      c.delivery_url ? { url: c.delivery_url, label: 'تحميل نسختك الآن' } : undefined,
      undefined,
      { label: 'تنتهي مدة الحفظ قريبًا', tone: 'warning' }
    ),
    text: `ملفاتك تُحفظ 30 يومًا من التسليم — حمّلها الآن: ${c.delivery_url || ''}`,
  };
}

export function C19_v360Expiry(c: ContractCtx & { tour_url?: string }): EmailRender {
  return {
    subject: `جولة 360° — استضافتها تنتهي قريبًا ${c.contract_number || ''} — مأوى`,
    html: layout(
      'استضافة الجولة 360° تنتهي قريبًا',
      p('استضافة جولتك الافتراضية 360° تمتد 12 شهرًا من التفعيل والتسليم، وتقترب من الانتهاء.') +
        p('للتجديد تواصل مع مأوى وفق الأسعار السارية، وإلا يتوقف الرابط بعد انتهاء المدة.'),
      c.tour_url ? { url: c.tour_url, label: 'فتح الجولة الحالية' } : undefined,
      undefined,
      { label: 'استضافة الجولة تقترب من الانتهاء', tone: 'warning' }
    ),
    text: `استضافة جولة 360° (${c.contract_number}) تنتهي قريبًا — للتجديد تواصل معنا.`,
  };
}

export function C20_rating(c: ContractCtx & { rating_url?: string }): EmailRender {
  return {
    subject: `كيف كانت تجربتك مع مأوى؟`,
    html: layout(
      'رأيك يصنع مأوى أفضل',
      p(`عزيزنا ${c.client_name || 'العميل الكريم'}، اكتملت خدمتك معنا. نرجو تخصيص دقيقة لتقييم التجربة — ملاحظاتك تنعكس مباشرة على جودة خدمتنا.`),
      c.rating_url ? { url: c.rating_url, label: 'تقييم التجربة' } : undefined,
      undefined,
      { label: 'خدمتك اكتملت — رأيك يهمنا', tone: 'info' }
    ),
    text: `كيف كانت تجربتك مع مأوى؟ قيّم هنا: ${c.rating_url || ''}`,
  };
}

export function O06_operationalUpdate(c: ContractCtx & { reason?: string; admin_url?: string }, variant: 'cancellation' | 'reschedule' | 'force_majeure' | 'visit_fee' | 'late' | 'no_show'): EmailRender {
  const m = {
    cancellation: 'إلغاء طلب',
    reschedule: 'إعادة جدولة طلب',
    force_majeure: 'قوة قاهرة — طلب معلق',
    visit_fee: 'رسوم زيارة مطبقة على طلب',
    late: 'تأخر جلسة أكثر من 30 دقيقة',
    no_show: 'عدم حضور جلسة',
  } as const;
  return {
    subject: `${m[variant]} — ${c.contract_number || ''}`,
    html: layout(
      m[variant],
      kv([
        ['الطلب', c.contract_number],
        ['العميل', c.client_name],
        ['الموعد', c.shoot_date],
        ['تفاصيل', c.reason],
      ]),
      c.admin_url ? { url: c.admin_url, label: 'فتح الطلب في الإدارة' } : undefined
    ),
    text: `${m[variant]} — ${c.contract_number}. ${c.reason || ''}`,
  };
}

export function O07_photographer24h(c: ContractCtx & { photographer_name?: string }): EmailRender {
  return {
    subject: `تذكير بريدي: جلسة غدًا — ${c.contract_number || ''}`,
    html: layout(
      'جلسة التصوير غدًا',
      p(`مرحبًا ${c.photographer_name || ''}،`) +
        kv([
          ['الطلب', c.contract_number],
          ['الموعد', c.shoot_date ? `${c.shoot_date} — ${c.shoot_time || ''}` : '—'],
          ['الموقع', c.location],
          ['الخدمات', c.services],
        ]),
      c.maps_url ? { url: c.maps_url, label: 'فتح الموقع' } : undefined
    ),
    text: `تذكير: جلسة ${c.contract_number} غدًا ${c.shoot_time || ''} — ${c.location || ''}`,
  };
}

export function O09_filesMissing(c: ContractCtx & { admin_url?: string }): EmailRender {
  return {
    subject: `ملفات جلسة غير مرفوعة — ${c.contract_number || ''}`,
    html: layout(
      'ملفات الجلسة لم تُرفع بعد',
      p('انتهت الجلسة ولم تكتمل عملية رفع الملفات وفق سياسة التشغيل.') +
        kv([['الطلب', c.contract_number], ['الموعد', c.shoot_date]]),
      c.admin_url ? { url: c.admin_url, label: 'متابعة رفع الملفات' } : undefined,
      'التسليم للعميل مرتبط باكتمال المعالجة — يرجى المتابعة العاجلة.'
    ),
    text: `ملفات الطلب ${c.contract_number} غير مرفوعة بعد — يرجى المتابعة.`,
  };
}

export function O10_qualityReview(c: ContractCtx & { admin_url?: string }): EmailRender {
  return {
    subject: `مخرجات بانتظار مراجعة الجودة — ${c.contract_number || ''}`,
    html: layout(
      'مخرجات بانتظار مراجعة الجودة',
      p('اكتملت معالجة المخرجات وهي بانتظار مراجعة الجودة قبل طلب السداد النهائي أو التسليم.') +
        kv([['الطلب', c.contract_number], ['العميل', c.client_name]]),
      c.admin_url ? { url: c.admin_url, label: 'بدء مراجعة الجودة' } : undefined
    ),
    text: `مخرجات الطلب ${c.contract_number} بانتظار مراجعة الجودة.`,
  };
}

export function O11_deliveryDelayRisk(c: ContractCtx & { due_date?: string; admin_url?: string }): EmailRender {
  return {
    subject: `خطر تجاوز موعد التسليم — ${c.contract_number || ''}`,
    html: layout(
      'الطلب معرض لتجاوز موعد التسليم',
      kv([
        ['الطلب', c.contract_number],
        ['موعد التسليم المتوقع', c.due_date],
        ['العميل', c.client_name],
      ]) +
        p('بحسب الوتيرة الحالية قد يتجاوز التسليم المدة المعتمدة (7–10 أيام عمل). يرجى التدخل العاجل.'),
      c.admin_url ? { url: c.admin_url, label: 'فتح الطلب' } : undefined
    ),
    text: `خطر تأخير تسليم الطلب ${c.contract_number} — الموعد المتوقع ${c.due_date || ''}.`,
  };
}

export function O12_deliveryClosure(c: ContractCtx & { state?: string; admin_url?: string }): EmailRender {
  return {
    subject: `تحديث التسليم والإغلاق — ${c.contract_number || ''}`,
    html: layout(
      'تحديث التسليم والإغلاق',
      kv([
        ['الطلب', c.contract_number],
        ['الحالة', c.state],
        ['العميل', c.client_name],
      ]),
      c.admin_url ? { url: c.admin_url, label: 'فتح الطلب' } : undefined
    ),
    text: `تحديث التسليم/الإغلاق للطلب ${c.contract_number}: ${c.state || ''}`,
  };
}
