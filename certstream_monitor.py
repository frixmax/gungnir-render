import requests
import time
import os
from datetime import datetime, timedelta

DOMAINS_FILE = 'domains.txt'
OUTPUT_DIR = 'results'
FIRST_RUN_FILE = '/app/.first_run_complete'
CHECK_INTERVAL = 300  # 5 min
SEEN_FILE = '/app/seen_domains.txt'

# Charger domaines
with open(DOMAINS_FILE, 'r') as f:
    target_domains = [line.strip().lower() for line in f if line.strip()]

os.makedirs(OUTPUT_DIR, exist_ok=True)
print(f"Monitoring: {', '.join(target_domains)}")

is_first_run = not os.path.exists(FIRST_RUN_FILE)

# Déduplication globale (cert_id unique)
processed_certs = set()

def get_certificates_from_crtsh(domain):
    # Filtre : seulement certs émis depuis 7 jours
    min_date = (datetime.utcnow() - timedelta(days=7)).strftime('%Y-%m-%d')
    try:
        url = f"https://crt.sh/?q=%.{domain}&output=json&minNotBefore={min_date}"
        response = requests.get(url, timeout=30)
        if response.status_code == 200:
            return response.json()
        return []
    except Exception as e:
        print(f"Error crt.sh {domain}: {e}")
        return []

def process_certificate(cert_data, target_domain):
    cert_id = str(cert_data['id'])
    if cert_id in processed_certs:
        return
    processed_certs.add(cert_id)

    domain = cert_data['name_value'].strip().lower()
    timestamp = datetime.now().isoformat()

    if is_first_run:
        print(".", end="", flush=True)
    else:
        print(f"[{timestamp}] NEW: {domain}")

    output_file = os.path.join(OUTPUT_DIR, target_domain.replace('.', '_'))
    with open(output_file, 'a') as f:
        f.write(f"{domain}\n")

def monitor_loop():
    global is_first_run
    cycle_number = 0

    while True:
        cycle_number += 1
        cycle_start = time.time()

        is_first_run = not os.path.exists(FIRST_RUN_FILE)
        print(f"\n=== CYCLE #{cycle_number} - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ===")

        for idx, target in enumerate(target_domains, 1):
            print(f"[{idx}/{len(target_domains)}] Checking {target}...", end=" ")
            certificates = get_certificates_from_crtsh(target)

            if certificates:
                certificates.sort(key=lambda x: x.get('entry_timestamp', ''), reverse=True)
                for cert in certificates[:15]:  # Limite à 15 les plus récents
                    domain_lower = cert['name_value'].lower().lstrip('*.')
                    if domain_lower.endswith(target) or domain_lower == target:
                        process_certificate(cert, target)

            print("OK")

            time.sleep(2)  # pause entre domaines

        cycle_duration = int(time.time() - cycle_start)
        print(f"\nCycle terminé en {cycle_duration}s")

        if is_first_run:
            print("Initialisation terminée → notifications activées")
            with open(FIRST_RUN_FILE, 'w') as f:
                f.write(datetime.now().isoformat())

        # Appel notify.sh
        os.system('./notify.sh')

        print(f"Attente {CHECK_INTERVAL}s avant prochain cycle...")
        time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    monitor_loop()
