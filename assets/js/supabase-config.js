const SUPABASE_URL = 'https://fivrwlowntwacfrsocge.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZpdnJ3bG93bnR3YWNmcnNvY2dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYyNjU0ODYsImV4cCI6MjA5MTg0MTQ4Nn0.isXqeO1WYGM3EAolRykwU1ppNgMKmKbU7j-U2Nvb9fc';

/* إشعار الطلبات الجديدة على واتساب المالك — عبر CallMeBot */
const NOTIFY = {
    phone: '966531646152',
    apikey: 'TODO' /* يُستبدل بالمفتاح بعد تفعيل CallMeBot */
};

async function notifyOwner(text){
    try{
        if (typeof NOTIFY === 'undefined' || !NOTIFY.apikey || NOTIFY.apikey === 'TODO') return false;
        const url = 'https://api.callmebot.com/whatsapp.php?phone=' + NOTIFY.phone +
                    '&apikey=' + NOTIFY.apikey + '&text=' + encodeURIComponent(text);
        await fetch(url, { mode: 'no-cors' });
        return true;
    }catch(e){ return false; }
}

let _supabase = null;

function getSupabase() {
    if (_supabase) return _supabase;
    _supabase = window.supabase
        ? window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
        : null;
    if (!_supabase) console.error('Supabase JS library not loaded');
    return _supabase;
}
