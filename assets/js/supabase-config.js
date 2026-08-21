const SUPABASE_URL = 'https://fivrwlowntwacfrsocge.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZpdnJ3bG93bnR3YWNmcnNvY2dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYyNjU0ODYsImV4cCI6MjA5MTg0MTQ4Nn0.isXqeO1WYGM3EAolRykwU1ppNgMKmKbU7j-U2Nvb9fc';

/* إشعار الطلبات الجديدة على البريد الرسمي — عبر Web3Forms */
const NOTIFY = {
    access_key: 'ebb8784b-cd6e-4b9d-9ef4-92b5cc94444a',
    from_name: 'موقع مأوى'
};

async function notifyOwner(text){
    try{
        if (typeof NOTIFY === 'undefined' || !NOTIFY.access_key) return false;
        const res = await fetch('https://api.web3forms.com/submit', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
            body: JSON.stringify({
                access_key: NOTIFY.access_key,
                subject: 'طلب جديد من موقع مأوى',
                from_name: NOTIFY.from_name,
                message: text
            })
        });
        const data = await res.json();
        return !!data.success;
    }catch(e){ return false; }
}
