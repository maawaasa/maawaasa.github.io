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

// ===== Email Design System V2 — SaaS Premium =====
// accent مخصص لكل حدث (Light + Dark variants) · الهوية: Burgundy #7A1F2B / Black #0B0B0B / Off-white #F7F5F2
// القاعدة: اللون في chip + حد البطاقة + فاصل العنوان فقط — body محايد دائمًا
export type AccentKey =
  | 'burgundy'|'slate'|'indigo'|'amber'|'blue'|'red'|'darkred'|'green'
  | 'purple'|'teal'|'cyan'|'blue2'|'orange'|'azure'|'emerald'|'deepgreen'
  | 'gold'|'violet'|'forest';

export type Status = { label: string; accent: AccentKey; icon?: string; detail?: string };
export type StatusTone = AccentKey;

type AccentTheme = {
  l: string;  d: string;    // accent: فاتح / داكن (أفتح وأكثر إشباعًا)
  lbg: string; dbg: string; // خلفية الشارة
  lfg: string; dfg: string; // نص الشارة
  lbd: string; dbd: string; // حد الشارة
};

const ACC: Record<AccentKey, AccentTheme> = {
  burgundy:  { l:'#7A1F2B', d:'#D06A78', lbg:'#F6F1F0', dbg:'#2A1B1E', lfg:'#5C1620', dfg:'#F2C4CC', lbd:'#E8D5D8', dbd:'#4A2F35' },
  slate:     { l:'#667085', d:'#98A2B3', lbg:'#F4F6F8', dbg:'#1B1F27', lfg:'#404855', dfg:'#C9CFDA', lbd:'#E3E7ED', dbd:'#333A45' },
  indigo:    { l:'#4F46E5', d:'#8B85F0', lbg:'#F0F0FD', dbg:'#1B1A33', lfg:'#3730A3', dfg:'#C7C4F5', lbd:'#DDDBFA', dbd:'#2E2B55' },
  amber:     { l:'#C58B22', d:'#E8B84A', lbg:'#FBF3E0', dbg:'#2B2313', lfg:'#7A5510', dfg:'#F3DCA8', lbd:'#F0DFB6', dbd:'#4A3C1E' },
  blue:      { l:'#2563EB', d:'#6EA8FE', lbg:'#EBF1FE', dbg:'#141C30', lfg:'#1D4ED8', dfg:'#BBD0FC', lbd:'#D3E0FC', dbd:'#22304F' },
  red:       { l:'#B42318', d:'#F97066', lbg:'#FCEEEC', dbg:'#331512', lfg:'#8F1B12', dfg:'#F6C6C2', lbd:'#F6D5D2', dbd:'#4C1D18' },
  darkred:   { l:'#8F2A22', d:'#F97066', lbg:'#F9ECEA', dbg:'#2E1512', lfg:'#6E211B', dfg:'#F6C6C2', lbd:'#EFD5D2', dbd:'#40201B' },
  green:     { l:'#2E7D4F', d:'#58C27D', lbg:'#EAF4EE', dbg:'#12241B', lfg:'#1F5C3A', dfg:'#BFE8CD', lbd:'#D4E8DC', dbd:'#1E3A2C' },
  purple:    { l:'#7C3AED', d:'#B49AF8', lbg:'#F3EEFE', dbg:'#1F1733', lfg:'#5B21B6', dfg:'#D6C8FB', lbd:'#E2D6FB', dbd:'#2F2450' },
  teal:      { l:'#0F766E', d:'#4FD1C5', lbg:'#EAF5F4', dbg:'#0F2020', lfg:'#0B544E', dfg:'#B8E5E0', lbd:'#CFE9E6', dbd:'#1A3A38' },
  cyan:      { l:'#0E7490', d:'#67C3DE', lbg:'#E9F5F8', dbg:'#0E1F26', lfg:'#0A586E', dfg:'#B8E2EE', lbd:'#CDE7EF', dbd:'#17323F' },
  blue2:     { l:'#3157A4', d:'#7FA4EC', lbg:'#EEF3FB', dbg:'#151D31', lfg:'#254581', dfg:'#C3D5F6', lbd:'#D8E2F6', dbd:'#243252' },
  orange:    { l:'#C26A15', d:'#F0A44C', lbg:'#FBF1E6', dbg:'#2A1F10', lfg:'#8A4A0C', dfg:'#F6DCBC', lbd:'#F2DFC7', dbd:'#4A3419' },
  azure:     { l:'#1677B8', d:'#5EB2E8', lbg:'#E9F4FB', dbg:'#0F1F2C', lfg:'#0F5E90', dfg:'#BEE0F6', lbd:'#CFE7F5', dbd:'#1A3448' },
  emerald:   { l:'#178F62', d:'#4CC58F', lbg:'#EAF6F0', dbg:'#0F231B', lfg:'#0F6B47', dfg:'#BEE8D2', lbd:'#CDEADF', dbd:'#16352A' },
  deepgreen: { l:'#236B45', d:'#5FBE8B', lbg:'#EAF4EE', dbg:'#0F2118', lfg:'#174D33', dfg:'#BCE5CF', lbd:'#CFE8DA', dbd:'#173425' },
  gold:      { l:'#A97917', d:'#E5C15C', lbg:'#FAF3E2', dbg:'#28200E', lfg:'#73550C', dfg:'#F0DFAC', lbd:'#EFE3BE', dbd:'#423715' },
  violet:    { l:'#6D5BD0', d:'#A99BF0', lbg:'#F1EFFC', dbg:'#1A1730', lfg:'#4C3FA8', dfg:'#D5CEFA', lbd:'#DEDAF8', dbd:'#282247' },
  forest:    { l:'#285943', d:'#57B183', lbg:'#ECF3EF', dbg:'#101F18', lfg:'#1C4232', dfg:'#C2E4D2', lbd:'#D5E6DD', dbd:'#1B3328' },
};

// Dark-mode overrides لكل accent — تُحقن في <style> القالب
const CHIP_DARK_CSS = Object.entries(ACC)
  .map(([k, a]) => `.ma-chip.ac-${k}{background:${a.dbg}!important;color:${a.dfg}!important;border-color:${a.dbd}!important}`)
  .join('\n  ');
const DIV_DARK_CSS = Object.entries(ACC)
  .map(([k, a]) => `.ma-div.ac-${k}{background:${a.d}!important}`)
  .join('\n  ');

// شارة الحالة — chip صغير (ليس banner)
function chipHtml(s: Status): string {
  const icon = s.icon ? `<span dir="ltr" style="opacity:.8;">${s.icon}</span>&nbsp; ` : '';
  return `<span class="ma-chip ac-${s.accent}" style="display:inline-block;padding:6px 14px;border-radius:999px;background:${ACC[s.accent].lbg};border:1px solid ${ACC[s.accent].lbd};color:${ACC[s.accent].lfg};font-size:12.5px;font-weight:700;line-height:1.5;">${icon}${esc(s.label)}</span>`;
}

// أزرار SaaS — أساسي Burgundy · تصحيح Red · ثانوي outline
function btnHtml(url: string, label: string, kind: 'primary' | 'danger' | 'secondary'): string {
  if (kind === 'secondary') {
    return `<table role="presentation" cellpadding="0" cellspacing="0" align="center" style="margin:0 auto;"><tr><td align="center" class="ma-btn2td" style="border-radius:12px;border:1px solid #D0D5DD;background:#FFFFFF;">
<a class="ma-btn ma-btn2" href="${esc(url)}" target="_blank" style="display:inline-block;padding:14px 30px;font-family:inherit;font-size:14.5px;font-weight:700;color:#344054;text-decoration:none;border-radius:12px;text-align:center;">${esc(label)}</a>
</td></tr></table>`;
  }
  const danger = kind === 'danger';
  return `<table role="presentation" cellpadding="0" cellspacing="0" align="center" style="margin:0 auto;"><tr><td align="center" class="${danger ? 'ma-btnd-td' : 'ma-btnp-td'}" bgcolor="${danger ? '#B42318' : '#7A1F2B'}" style="border-radius:12px;background:${danger ? '#B42318' : '#7A1F2B'};">
<a class="ma-btn ${danger ? 'ma-btnd' : 'ma-btnp'}" href="${esc(url)}" target="_blank" style="display:inline-block;padding:15px 36px;font-family:inherit;font-size:14.5px;font-weight:700;text-decoration:none;border-radius:12px;text-align:center;"><span class="ma-btn-t" style="color:#FFFFFF;">${esc(label)}</span></a>
</td></tr></table>`;
}

function layout(
  title: string,
  bodyHtml: string,
  cta?: { url: string; label: string },
  note?: string,
  status?: Status,
  secondary?: { url: string; label: string },
  ref?: string,
  preheader?: string
): string {
  const pre = esc(preheader || title);
  const accent = status?.accent ?? 'burgundy';
  const A = ACC[accent];
  const banner = status
    ? `<table role="presentation" cellpadding="0" cellspacing="0"><tr><td style="padding:0 0 16px;">${chipHtml(status)}${status.detail ? `<div style="font-size:12px;color:#6B6B6B;margin-top:6px;">${esc(status.detail)}</div>` : ''}</td></tr></table>`
    : '';
  const refHtml = ref
    ? `<div style="margin:0 0 16px;"><span dir="ltr" class="ma-ref" style="display:inline-block;padding:6px 16px;border:1.5px solid #E5DED6;border-radius:999px;font-size:13px;font-weight:700;color:#0B0B0B;background:#F7F5F2;">${esc(ref)}</span></div>`
    : '';
  const ctaKind = status && (status.accent === 'red' || status.accent === 'darkred') ? 'danger' : 'primary';
  const ctaHtml = cta
    ? `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:26px;"><tr><td align="center">
        ${btnHtml(cta.url, cta.label, ctaKind)}
        ${secondary ? `<div style="height:11px;line-height:11px;font-size:0;">&nbsp;</div>${btnHtml(secondary.url, secondary.label, 'secondary')}` : ''}
      </td></tr></table>`
    : '';
  const noteHtml = note
    ? `<p class="ma-note" style="margin:18px 0 0;font-size:12.5px;color:#6B6B6B;line-height:1.9;">${esc(note)}</p>`
    : '';
  const signatureHtml = `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:28px;">
<tr><td style="padding-top:18px;border-top:1px solid #F0EDE8;">
  <p class="ma-sig" style="margin:0;font-size:13.5px;color:#344054;line-height:1.9;">مع تحيات فريق <span class="ma-sig-b" style="font-weight:700;color:#0B0B0B;">مأوى</span> للتصوير العقاري</p>
  <p class="ma-note" style="margin:2px 0 0;font-size:12px;color:#6B6B6B;">نشكر ثقتكم — نحن على واتساب دائمًا في خدمتكم</p>
</td></tr></table>`;
  return `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>${esc(title)}</title>
<style>
  body{margin:0;padding:0;width:100%;-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%}
  @media only screen and (max-width:600px){
    .ma-card{width:100%!important;border-radius:0!important}
    .ma-head{padding:24px 18px 6px!important}
    .ma-body{padding:26px 18px 12px!important}
    .ma-h1{font-size:20px!important}
    .ma-foot{padding:18px 18px 26px!important}
    .ma-btn,.ma-btn2{display:block!important;padding:15px 14px!important;min-height:48px!important}
    .ma-kv-body{padding:8px 14px!important}
    .ma-kv-l,.ma-kv-v{display:block!important;width:100%!important;white-space:normal!important;text-align:right!important}
    .ma-kv-l{padding-bottom:2px!important;font-size:11.5px!important;border-bottom:none!important}
    .ma-kv-v{padding-bottom:10px!important}
  }
  @media (prefers-color-scheme:dark){
    .ma-page{background:#0B0D10!important}
    .ma-card{background:#15171B!important;border-color:#262A31!important}
    .ma-wordmark{color:#F5F7FA!important}
    .ma-wordmark-dot{color:#D06A78!important}
    .ma-tagline{color:#9299A5!important}
    .ma-title{color:#F5F7FA!important}
    .ma-body-p{color:#D7DCE3!important}
    .ma-note{color:#AEB4BE!important}
    .ma-sig{color:#D7DCE3!important}
    .ma-sig-b{color:#F5F7FA!important}
    .ma-ref{color:#F5F7FA!important;background:#181B20!important;border-color:#262A31!important}
    .ma-kvc{background:#181B20!important;border-color:#262A31!important}
    .ma-kv-l{color:#9299A5!important;border-bottom-color:#262A31!important}
    .ma-kv-v{color:#F5F7FA!important}
    .ma-foot{background:#111318!important;border-top-color:#262A31!important}
    .ma-foot,.ma-foot a{color:#AEB4BE!important}
    .ma-btn2td{background:#15171B!important;border-color:#3A4048!important}
    .ma-btn2{color:#D7DCE3!important}
    ${CHIP_DARK_CSS}
    ${DIV_DARK_CSS}
    .ma-btnd-td{background:#F97066!important}
    .ma-btnd{background:#F97066!important}
    .ma-btnd .ma-btn-t{color:#2A0E0B!important}
  }
</style>
</head>
<body class="ma-page" style="margin:0;padding:0;width:100%;background:#F3F4F6;font-family:'IBM Plex Sans Arabic','Segoe UI',Tahoma,Arial,sans-serif;-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%;">
<div style="display:none;max-height:0;max-width:0;overflow:hidden;opacity:0;font-size:1px;line-height:1px;color:transparent;mso-hide:all;">${pre}&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" class="ma-page" style="background:#F3F4F6;">
<tr><td align="center" style="padding:30px 12px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" class="ma-card" style="max-width:600px;background:#FFFFFF;border-radius:18px;border:1px solid #EAECF0;direction:rtl;">
    <tr><td class="ma-head" align="center" style="padding:28px 20px 8px;direction:rtl;">
      <div class="ma-wordmark" style="font-size:23px;font-weight:700;color:#0B0B0B;">مأوى<span class="ma-wordmark-dot" style="color:#7A1F2B;">.</span></div>
      <div class="ma-tagline" style="font-size:11px;color:#98A2B3;margin-top:4px;">للتصوير العقاري</div>
    </td></tr>
    <tr><td class="ma-body" style="padding:26px 32px 14px;direction:rtl;text-align:right;">
      ${banner}
      ${refHtml}
      <h1 class="ma-h1" style="margin:0 0 8px;font-size:23px;color:#0B0B0B;line-height:1.6;text-align:right;">${esc(title)}</h1>
      <div class="ma-div ac-${accent}" style="width:44px;height:3px;background:${A.l};border-radius:2px;margin:0 0 20px;"></div>
      ${bodyHtml}
      ${ctaHtml}
      ${noteHtml}
      ${signatureHtml}
    </td></tr>
    <tr><td class="ma-foot" style="padding:20px 30px 26px;border-top:1px solid #EAECF0;background:#FAFAFA;" align="center">
      <div style="font-size:13px;font-weight:700;color:#0B0B0B;margin-bottom:6px;">مأوى<span style="color:#7A1F2B;">.</span></div>
      <div style="font-size:12px;line-height:2;direction:rtl;">
        <a href="${BRAND.site}" style="color:#344054;text-decoration:none;">maawaa.sa</a>
        &nbsp;·&nbsp; <a href="mailto:${BRAND.customerEmail}" style="color:#344054;text-decoration:none;">info@maawaa.sa</a>
        &nbsp;·&nbsp; <span dir="ltr"><a href="https://wa.me/${BRAND.whatsapp.replace(/[^0-9]/g,'')}" style="color:#344054;text-decoration:none;">WhatsApp</a></span>
        &nbsp;·&nbsp; <a href="${BRAND.instagram}" style="color:#344054;text-decoration:none;">Instagram</a>
      </div>
      <div style="font-size:11px;color:#98A2B3;margin-top:8px;">هذه رسالة آلية من مأوى للتصوير العقاري — لالدعم: ${esc(BRAND.customerEmail)}</div>
    </td></tr>
  </table>
</td></tr></table>
</body></html>`;
}

function kv(rows: Array<[string, unknown]>): string {
  const hasAr = (v: unknown) => /[\u0600-\u06FF]/.test(String(v ?? ''));
  const inner = rows
    .filter(([, v]) => v !== undefined && v !== null && String(v) !== '')
    .map(([k, v]) => {
      const dir = hasAr(v) ? 'rtl' : 'ltr';
      return `<tr>` +
        `<td class="ma-kv-l" style="padding:10px 0;border-bottom:1px solid #EAECF0;font-size:12.5px;color:#6B6B6B;white-space:nowrap;">${esc(k)}</td>` +
        `<td class="ma-kv-v" style="padding:10px 0;border-bottom:1px solid #EAECF0;font-size:13.5px;font-weight:700;color:#0B0B0B;text-align:left;word-break:break-word;"><span dir="${dir}">${esc(v)}</span></td>` +
        `</tr>`;
    })
    .join('');
  if (!inner) return '';
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" class="ma-kvc" style="margin:12px 0 8px;background:#F8F9FB;border:1px solid #EAECF0;border-radius:14px;">
<tr><td class="ma-kv-body" style="padding:6px 16px;direction:rtl;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${inner}</table>
</td></tr></table>`;
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
          ['الإجمالي', fmt(q.total)],
          ['الصلاحية حتى', q.valid_until],
          ['الخدمات', q.summary || '—'],
        ]),
      q.quote_url ? { url: q.quote_url, label: 'عرض تفاصيل عرض السعر' } : undefined,
      'العرض سارٍ 14 يومًا من تاريخه. لا يتم إنشاء أي حجز تلقائيًا.',
      { label: 'عرض سعر جديد — بانتظار ردك', accent: 'burgundy', icon: '◆' },
      undefined,
      q.quote_number
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
      { label: 'انتهت صلاحية العرض', accent: 'slate', icon: '×' },
      undefined,
      q.quote_number
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
          ['الخدمات', c.services],
          ['الموعد المطلوب', c.shoot_date ? `${c.shoot_date}${c.shoot_time ? ' — ' + c.shoot_time : ''}` : '—'],
          ['الموقع', c.location],
        ]),
      undefined,
      'سنراسلك عند الحاجة للخطوة التالية — تأكيد التغطية وتوفر الموعد ثم بيانات العربون.',
      { label: 'تم الاستلام — قيد المراجعة', accent: 'indigo', icon: '◆', detail: 'لا يلزمك أي إجراء الآن' },
      undefined,
      c.contract_number
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
          ['العربون المطلوب (25%)', fmt(c.deposit)],
          ['الإجمالي', fmt(c.total)],
          ['المتبقي بعد الجلسة', fmt(c.remaining)],
        ]) +
        p('حوّل العربون وارفع الإيصال خلال المهلة لتثبيت الموعد نهائيًا.'),
      c.deposit_upload_url ? { url: c.deposit_upload_url, label: 'رفع إيصال العربون' } : undefined,
      'بعد رفع الإيصال يبقى موعدك محفوظًا أثناء مراجعة مأوى — لن تخسر الموعد بسبب مدة المراجعة.',
      { label: 'بانتظار العربون — مهلة 24 ساعة', accent: 'amber', icon: '!', detail: 'موعدك محفوظ مؤقتًا ولا يثبت إلا برفع الإيصال' },
      WA_BTN,
      c.contract_number,
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
        kv([['الموعد', c.shoot_date]]),
      undefined,
      'موعدك يبقى محفوظًا أثناء المراجعة — سنؤكد لك الحجز فور اعتماد الدفعة.',
      { label: 'الإيصال تحت المراجعة', accent: 'blue', icon: '◆', detail: 'موعدك محفوظ — لا يلزمك أي إجراء' },
      undefined,
      c.contract_number
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
      { label: 'يحتاج إجراء منك — إعادة رفع الإيصال', accent: 'red', icon: '!', detail: 'موعدك يبقى محفوظًا مؤقتًا' },
      undefined,
      c.contract_number
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
      { label: 'انتهت المهلة — تم تحرير الحجز المؤقت', accent: 'darkred', icon: '!' },
      undefined,
      c.contract_number
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
          ['الموعد', c.shoot_date ? `${c.shoot_date}${c.shoot_time ? ' — ' + c.shoot_time : ''}` : '—'],
          ['الموقع', c.location],
          ['الخدمات', c.services],
          ['المدفوع', fmt(c.deposit)],
          ['المتبقي قبل التسليم', fmt(c.remaining)],
        ]) +
        p('ستجد العقد مرفقًا/متاحًا عبر الزر، ويمكنك إضافة الموعد لتقويمك.'),
      c.contract_url ? { url: c.contract_url, label: 'عرض العقد وتفاصيل الجلسة' } : undefined,
      'التسليم القياسي خلال 7–10 أيام عمل من اليوم التالي لاكتمال الجلسة.',
      { label: 'الحجز مؤكد — العربون معتمد', accent: 'green', icon: '✓', detail: 'لا يلزمك أي إجراء دفع الآن — نراك يوم الجلسة' },
      undefined,
      c.contract_number,
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
        kv([['المتبقي المطلوب', fmt(c.remaining)]]),
      c.balance_upload_url ? { url: c.balance_upload_url, label: 'رفع إيصال السداد النهائي' } : undefined,
      'التسليم النهائي يتم بعد اكتمال السداد مباشرة.',
      { label: 'بانتظار السداد النهائي', accent: 'orange', icon: '!', detail: 'المخرجات جاهزة والتسليم ينتظر اكتمال السداد' },
      undefined,
      c.contract_number
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
      { label: 'الإيصال تحت التحقق', accent: 'azure', icon: '◆' }
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
      { label: 'يحتاج إجراء منك — إعادة رفع الإيصال', accent: 'red', icon: '!' }
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
        kv([['التسليم', 'مخرجات معالجة فقط — RAW غير مشمول']]),
      c.delivery_url ? { url: c.delivery_url, label: 'فتح وتحميل المخرجات' } : undefined,
      'الملفات تُحفظ 30 يومًا من التسليم. لك جولة تعديلات طفيفة واحدة خلال 7 أيام من اليوم.',
      { label: 'جاهز للتحميل', accent: 'deepgreen', icon: '✓', detail: 'المخرجات مكتملة — الحفظ 30 يومًا من الآن' },
      WA_BTN,
      c.contract_number,
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
        kv([['الموعد', c.shoot_date]]),
      c.contract_url ? { url: c.contract_url, label: 'عرض العقد' } : undefined,
      undefined,
      { label: 'العقد جاهز للاطلاع والاعتماد', accent: 'purple', icon: '◆' },
      undefined,
      c.contract_number
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
          ['الموعد الجديد', c.shoot_date ? `${c.shoot_date}${c.shoot_time ? ' — ' + c.shoot_time : ''}` : '—'],
          ['الموقع', c.location],
        ]),
      c.calendar_url ? { url: c.calendar_url, label: 'تحديث الموعد في تقويمي' } : undefined,
      undefined,
      { label: 'تم تحديث الموعد', accent: 'teal', icon: '◆' },
      undefined,
      c.contract_number
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
      { label: 'غدًا جلسة التصوير', accent: 'cyan', icon: '◆' },
      undefined,
      c.contract_number
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
  const accent: AccentKey = variant === 'reschedule' ? 'slate'
    : variant === 'force_majeure' || variant === 'visit_fee' ? 'amber' : 'red';
  const c12icon = accent === 'slate' ? '\u25c6' : '!';
  return {
    subject: `${v.t} — ${c.contract_number || ''} — مأوى`,
    html: layout(v.t, v.b,
      variant === 'reschedule' && c.calendar_url ? { url: c.calendar_url, label: 'تحديث التقويم' } : undefined,
      undefined,
      { label: v.t, accent, icon: c12icon },
      undefined,
      c.contract_number),
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
          ['التسليم القياسي', '7–10 أيام عمل من اليوم التالي للجلسة'],
        ]),
      undefined,
      'لا يلزمك أي إجراء الآن — سنخبرك عند الجاهزية.',
      { label: 'قيد المعالجة', accent: 'blue2', icon: '▸', detail: 'التسليم خلال 7–10 أيام عمل' },
      undefined,
      c.contract_number
    ),
    text: `بدأت معالجة مخرجات الطلب ${c.contract_number}. التسليم خلال 7–10 أيام عمل.`,
  };
}

export function C18_retentionReminder(c: ContractCtx): EmailRender {
  return {
    subject: `تذكير: ملفاتك تُحفظ 30 يومًا ${c.contract_number || ''} — مأوى`,
    html: layout(
      'ملفاتك محفوظة لمدة محدودة',
      p('نذكّرك بأن ملفات جلستك تُحفظ على سحابة مأوى 30 يومًا من تاريخ التسليم ثم تُحذف تلقائيًا.'),
      c.delivery_url ? { url: c.delivery_url, label: 'تحميل نسختك الآن' } : undefined,
      undefined,
      { label: 'تنتهي مدة الحفظ قريبًا', accent: 'gold', icon: '!' },
      undefined,
      c.contract_number
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
      { label: 'استضافة الجولة تقترب من الانتهاء', accent: 'violet', icon: '◆' },
      undefined,
      c.contract_number
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
      { label: 'خدمتك اكتملت — رأيك يهمنا', accent: 'forest', icon: '◆' },
      undefined,
      c.contract_number
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
