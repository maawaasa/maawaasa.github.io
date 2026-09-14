/*
 * إعدادات تنسيق مشتركة للعقود والواجهات.
 * لا تعرض هذه الوحدة اختيار لغة أو عملة؛ الاستعمال الحالي يبقى عربيًا وبالريال.
 */
(function (global) {
  'use strict';

  const DEFAULT_LANGUAGE = 'ar';
  const DEFAULT_CURRENCY = 'SAR';
  const LOCALES = Object.freeze({ ar: 'ar-SA', en: 'en-US' });
  const CURRENCY_LABELS = Object.freeze({ SAR: 'ر.س', USD: 'USD' });

  function normalizeLanguage(language) {
    return Object.prototype.hasOwnProperty.call(LOCALES, language)
      ? language
      : DEFAULT_LANGUAGE;
  }

  function normalizeCurrency(currency) {
    return Object.prototype.hasOwnProperty.call(CURRENCY_LABELS, currency)
      ? currency
      : DEFAULT_CURRENCY;
  }

  function formatLanguage(language) {
    const value = normalizeLanguage(language);
    return {
      code: value,
      locale: LOCALES[value],
      direction: value === 'ar' ? 'rtl' : 'ltr'
    };
  }

  function formatAmount(amount, options) {
    const settings = options || {};
    const language = normalizeLanguage(settings.language);
    const currency = normalizeCurrency(settings.currency);
    const value = Number(amount);
    const safeAmount = Number.isFinite(value) ? value : 0;
    const minimumFractionDigits = settings.minimumFractionDigits === undefined
      ? 0
      : settings.minimumFractionDigits;
    const maximumFractionDigits = settings.maximumFractionDigits === undefined
      ? 2
      : settings.maximumFractionDigits;
    const formatted = new Intl.NumberFormat('en-US', {
      minimumFractionDigits: minimumFractionDigits,
      maximumFractionDigits: maximumFractionDigits
    }).format(safeAmount);

    return {
      amount: safeAmount,
      currency: currency,
      language: language,
      locale: LOCALES[language],
      direction: 'ltr',
      text: formatted + ' ' + CURRENCY_LABELS[currency]
    };
  }

  global.MawaLocalization = Object.freeze({
    DEFAULT_LANGUAGE: DEFAULT_LANGUAGE,
    DEFAULT_CURRENCY: DEFAULT_CURRENCY,
    normalizeLanguage: normalizeLanguage,
    normalizeCurrency: normalizeCurrency,
    formatLanguage: formatLanguage,
    formatAmount: formatAmount
  });
}(window));
