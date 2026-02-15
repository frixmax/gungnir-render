#!/usr/bin/env python3
import requests
import socket
import time
import os
import sys
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed

DOMAINS_FILE = 'domains.txt'
OUTPUT_DIR = 'results'
FIRST_RUN_FILE = '/app/.first_run_complete'
CHECK_INTERVAL = 300  # 5 min
SEEN_FILE = '/app/seen_domains.txt'

# Vérifications au démarrage
if not os.path.exists(DOMAINS_FILE):
    print(f"❌ ERREUR: {DOMAINS_FILE} n'existe pas!", file=sys.stderr)
    sys.exit(1)

try:
    with open(DOMAINS_FILE, 'r') as f:
        target_domains = [line.strip().lower() for line in f if line.strip() and not line.startswith('#')]
    
    if not target_domains:
        print(f"❌ ERREUR: {DOMAINS_FILE} est vide!", file=sys.stderr)
        sys.exit(1)
        
except Exception as e:
    print(f"❌ ERREUR lecture {DOMAINS_FILE}: {e}", file=sys.stderr)
    sys.exit(1)

os.makedirs(OUTPUT_DIR, exist_ok=True)
print(f"🎯 Monitoring: {', '.join(target_domains)}", flush=True)

is_first_run = not os.path.exists(FIRST_RUN_FILE)
processed_certs = set()

# ==================== DNS & HTTP CHECKS ====================

def check_dns(domain, timeout=3):
    """Vérifie si domaine résout en DNS"""
    try:
        ip = socket.gethostbyname(domain)
        return ip
    except:
        return None

def check_http(domain, timeout=5):
    """
    Vérifie HTTP status
    Retourne: (status_code, error_type)
    """
    try:
        response = requests.head(f"https://{domain}", timeout=timeout, allow_redirects=True, verify=False)
        return (response.status_code, None)
    except requests.exceptions.Timeout:
        return (None, "timeout")
    except requests.exceptions.ConnectionError:
        return (None, "refused")
    except:
        try:
            response = requests.head(f"http://{domain}", timeout=timeout, allow_redirects=True)
            return (response.status_code, None)
        except requests.exceptions.Timeout:
            return (None, "timeout")
        except requests.exceptions.ConnectionError:
            return (None, "refused")
        except:
            return (None, "error")

def detect_dangling(domain, dns_ip, http_status, http_error):
    """
    Dangling DNS = DNS résout mais HTTP ne répond pas
    Indicateurs:
      - DNS OK + HTTP timeout
      - DNS OK + HTTP connection refused
    """
    if dns_ip is None:
        return False  # DNS ne résout pas
    
    if http_status is not None:
        return False  # HTTP répond (quelque soit le status)
    
    if http_error in ['timeout', 'refused']:
        return True  # DNS OK mais HTTP down = Dangling!
    
    return False

def load_seen_domains():
    if os.path.exists(SEEN_FILE):
        try:
            with open(SEEN_FILE, 'r') as f:
                return set(line.strip().lower() for line in f if line.strip())
        except:
            return set()
    return set()

def save_seen_domain(domain):
    try:
        with open(SEEN_FILE, 'a') as f:
            f.write(f"{domain}\n")
    except:
        pass

seen_domains = load_seen_domains()
print(f"📊 {len(seen_domains)} domaines déjà vus\n", flush=True)

def get_certificates_from_crtsh(domain):
    """Récupère certificats de crt.sh"""
    min_date = (datetime.utcnow() - timedelta(days=2)).strftime('%Y-%m-%d')
    try:
        url = f"https://crt.sh/?q=%.{domain}&output=json&minNotBefore={min_date}"
        response = requests.get(url, timeout=30)
        if response.status_code == 200:
            data = response.json()
            return data if isinstance(data, list) else []
        return []
    except Exception as e:
        print(f"⚠️ crt.sh error {domain}: {str(e)[:50]}", file=sys.stderr, flush=True)
        return []

def is_subdomain_of_target(domain, target):
    """Vérifie si domain est un sous-domaine de target"""
    domain_lower = domain.lower().lstrip('*.')
    return domain_lower.endswith(target) or domain_lower == target

def process_certificate(cert_data, target_domain):
    """Traite un certificat et effectue les vérifications"""
    try:
        cert_id = str(cert_data.get('id', ''))
        if not cert_id or cert_id in processed_certs:
            return
        processed_certs.add(cert_id)
        
        domain = cert_data.get('name_value', '').strip().lower()
        if not domain or not is_subdomain_of_target(domain, target_domain):
            return
        
        domain_clean = domain.lstrip('*.')
        
        if domain_clean in seen_domains:
            return
        
        seen_domains.add(domain_clean)
        save_seen_domain(domain_clean)
        
        timestamp = datetime.now().isoformat()
        
        if is_first_run:
            print(".", end="", flush=True)
            return
        
        # ==================== CHECKS ====================
        print(f"\n[{timestamp}] FOUND: {domain_clean}", flush=True)
        
        # DNS check
        dns_ip = check_dns(domain_clean)
        dns_status = "✅" if dns_ip else "❌"
        print(f"  DNS {dns_status}: {dns_ip if dns_ip else 'NXDOMAIN'}", flush=True)
        
        # HTTP check (seulement si DNS résout)
        http_status = None
        http_error = None
        if dns_ip:
            http_status, http_error = check_http(domain_clean)
            if http_status:
                print(f"  HTTP ✅: {http_status}", flush=True)
            else:
                print(f"  HTTP ❌: {http_error if http_error else 'no response'}", flush=True)
        
        # Dangling DNS detection
        is_dangling = detect_dangling(domain_clean, dns_ip, http_status, http_error)
        if is_dangling:
            print(f"  ⚠️  DANGLING DNS DETECTED!", flush=True)
        
        # ==================== SAVE TO FILE ====================
        output_file = os.path.join(OUTPUT_DIR, target_domain.replace('.', '_'))
        
        # Format: domain|dns_status|http_status|dangling_flag
        line = f"{domain_clean}|{dns_ip if dns_ip else 'N/A'}|{http_status if http_status else http_error if http_error else 'N/A'}|{'DANGLING' if is_dangling else 'OK'}"
        
        try:
            with open(output_file, 'a') as f:
                f.write(f"{line}\n")
        except Exception as e:
            print(f"⚠️ Error writing {output_file}: {str(e)[:50]}", file=sys.stderr, flush=True)
            
    except Exception as e:
        print(f"⚠️ Error processing cert: {str(e)[:50]}", file=sys.stderr, flush=True)

def monitor_loop():
    global is_first_run
    cycle_number = 0
    
    while True:
        try:
            cycle_number += 1
            cycle_start = time.time()
            
            is_first_run = not os.path.exists(FIRST_RUN_FILE)
            
            print(f"\n{'='*60}", flush=True)
            print(f"CYCLE #{cycle_number} - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", flush=True)
            print(f"{'='*60}", flush=True)
            
            for idx, target in enumerate(target_domains, 1):
                print(f"[{idx}/{len(target_domains)}] {target}...", end=" ", flush=True)
                certificates = get_certificates_from_crtsh(target)
                
                if certificates:
                    certificates.sort(key=lambda x: x.get('entry_timestamp', ''), reverse=True)
                    for cert in certificates[:15]:
                        process_certificate(cert, target)
                
                print("OK", flush=True)
                time.sleep(2)
            
            cycle_duration = int(time.time() - cycle_start)
            print(f"\nCycle done in {cycle_duration}s", flush=True)
            
            if is_first_run:
                print("✅ Initialization complete → alerts enabled next cycle", flush=True)
                with open(FIRST_RUN_FILE, 'w') as f:
                    f.write(datetime.now().isoformat())
                for target in target_domains:
                    output_file = os.path.join(OUTPUT_DIR, target.replace('.', '_'))
                    if os.path.exists(output_file):
                        try:
                            os.remove(output_file)
                        except:
                            pass
            else:
                print("📢 Sending notifications...", flush=True)
                ret = os.system('./notify.sh')
                if ret != 0:
                    print(f"⚠️ notify.sh error code: {ret}", file=sys.stderr, flush=True)
            
            print(f"💤 Waiting {CHECK_INTERVAL}s...", flush=True)
            time.sleep(CHECK_INTERVAL)
            
        except KeyboardInterrupt:
            print("\n⚠️ Stopping...", flush=True)
            break
        except Exception as e:
            print(f"\n❌ ERROR: {e}", file=sys.stderr, flush=True)
            import traceback
            traceback.print_exc()
            print("Retry in 60s...", flush=True)
            time.sleep(60)

if __name__ == "__main__":
    try:
        monitor_loop()
    except Exception as e:
        print(f"❌ FATAL: {e}", file=sys.stderr, flush=True)
        import traceback
        traceback.print_exc()
        sys.exit(1)
