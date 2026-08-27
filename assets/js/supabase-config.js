const SUPABASE_URL = 'https://fivrwlowntwacfrsocge.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZpdnJ3bG93bnR3YWNmcnNvY2dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYyNjU0ODYsImV4cCI6MjA5MTg0MTQ4Nn0.isXqeO1WYGM3EAolRykwU1ppNgMKmKbU7j-U2Nvb9fc';

let _sbClient = null;

function getSupabase(){
    if (typeof window === 'undefined' || !window.supabase || !window.supabase.createClient) return null;
    if (!_sbClient) _sbClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    return _sbClient;
}

/* إشعار الطلبات — عبر دالة خادمية (Edge Function)، لا توجد أسرار في الواجهة */
const NOTIFY_ENDPOINT = SUPABASE_URL + '/functions/v1/notify-lead';

async function notifyOwner(text, contractId){
    try{
        const payload = { text: String(text || '').slice(0, 4000) };
        if (typeof contractId === 'string' && /^[0-9a-f-]{36}$/i.test(contractId)) {
            payload.contract_id = contractId;
        }
        const response = await fetch(NOTIFY_ENDPOINT, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ' + SUPABASE_ANON_KEY
            },
            body: JSON.stringify(payload)
        });
        return response.ok;
    }catch(e){ return false; }
}
