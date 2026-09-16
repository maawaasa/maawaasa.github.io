// =====================================================
// preview-emails.ts — معاينات محلية لقوالب العملاء (بلا إرسال)
// تشغيل: deno run --allow-write scripts/preview-emails.ts
// المخرجات: preview/*.html — للمراجعة البصرية فقط
// =====================================================
import {
  C01_quoteReady, C02_quoteExpired, C03_bookingReceived, C04_depositHold,
  C06_receiptCorrection, C07_holdExpired, C08_bookingConfirmed,
  C11_shootReminder, C14_readyBalance, C17_delivery,
} from '../supabase/functions/_shared/templates.ts';

const OUT = 'preview';
const D = new Date();
const fmtDate = (offset: number) => new Date(D.getTime() + offset * 86400000).toISOString().slice(0, 10);

const samples: Array<[string, { subject: string; html: string }]> = [
  ['c01-quote-ready', C01_quoteReady({
    quote_number: 'Q-1042', total: 2000, valid_until: fmtDate(14),
    summary: 'تصوير HDR + فيديو سينمائي', client_name: 'عبدالله المطيري',
  })],
  ['c02-quote-expired', C02_quoteExpired({ quote_number: 'Q-0999', total: 2000 })],
  ['c03-request-received', C03_bookingReceived({
    contract_number: 'MAW-1200', services: 'تصوير HDR — فيديو سينمائي',
    shoot_date: fmtDate(3), shoot_time: '10:00 — 12:00',
    location: 'الرياض — حي النرجس', client_name: 'عبدالله المطيري',
  })],
  ['c04-deposit-hold', C04_depositHold({
    contract_number: 'MAW-1200', deposit: 500, total: 2000, remaining: 1500,
    services: 'تصوير HDR — فيديو سينمائي', shoot_date: fmtDate(3), location: 'الرياض — حي النرجس',
    deposit_upload_url: 'https://maawaa.sa/receipt.html?t=PREVIEW&p=deposit_receipt',
    client_name: 'عبدالله المطيري',
  })],
  ['c06-receipt-correction', C06_receiptCorrection({
    contract_number: 'MAW-1200', deposit_upload_url: 'https://maawaa.sa/receipt.html?t=PREVIEW&p=deposit_receipt',
  })],
  ['c07-hold-expired', C07_holdExpired({
    contract_number: 'MAW-1200', calendar_url: 'https://maawaa.sa/calculator/',
  })],
  ['c08-booking-confirmed', C08_bookingConfirmed({
    contract_number: 'MAW-1200', shoot_date: fmtDate(3), shoot_time: '10:00 — 12:00',
    location: 'الرياض — حي النرجس', services: 'تصوير HDR — فيديو سينمائي',
    deposit: 500, remaining: 1500,
    contract_url: 'https://maawaa.sa/contract.html?t=PREVIEW', client_name: 'عبدالله المطيري',
  })],
  ['c11-shoot-reminder', C11_shootReminder({
    shoot_date: fmtDate(1), shoot_time: '10:00 — 12:00',
    location: 'الرياض — حي النرجس', maps_url: 'https://maps.google.com/?q=Riyadh',
  })],
  ['c14-balance-request', C14_readyBalance({
    contract_number: 'MAW-1200', remaining: 1500,
    balance_upload_url: 'https://maawaa.sa/receipt.html?t=PREVIEW&p=balance_receipt',
  })],
  ['c17-fully-paid', C17_delivery({
    contract_number: 'MAW-1200', delivery_url: 'https://maawaa.sa/delivery?token=PREVIEW',
    client_name: 'عبدالله المطيري',
  })],
];

try {
  await Deno.mkdir(OUT, { recursive: true });
} catch { /* موجود */ }

const index: string[] = [];
for (const [name, email] of samples) {
  const file = `${OUT}/${name}.html`;
  await Deno.writeTextFile(file, email.html);
  index.push(`<li><a href="${name}.html">${email.subject}</a></li>`);
  console.log('✓', file);
}

await Deno.writeTextFile(
  `${OUT}/index.html`,
  `<!DOCTYPE html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><title>معاينة قوالب العملاء — مأوى</title>
<style>body{font-family:'Segoe UI',Tahoma,sans-serif;background:#F7F5F2;padding:28px;direction:rtl}h1{color:#0B0B0B}li{margin:6px 0}a{color:#7A1F2B}</style></head>
<body><h1>معاينة قوالب العملاء — مأوى</h1><ol>${index.join('')}</ol>
<p style="color:#6B6B6B">ملفات محلية للمراجعة البصرية — ليست رسائل فعلية.</p></body></html>`,
);
console.log(`✓ ${OUT}/index.html`);
