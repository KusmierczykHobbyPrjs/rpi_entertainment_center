import requests
import argparse
from concurrent.futures import ThreadPoolExecutor
from collections import defaultdict

# Domyślny User-Agent, często akceptowany przez serwery streamujące
DEFAULT_USER_AGENT = 'VLC'

def check_stream_reachability(url, timeout, user_agent):
    """
    Attempts to check the stream URL using a HEAD request and returns raw result data.
    
    Returns:
        A dictionary containing 'url', 'status_code' (int or None), and 
        'exception' (str or None).
    """
    headers = {'User-Agent': user_agent}
    try:
        # Użycie metody HEAD z User-Agent, aby pobrać tylko nagłówki.
        # W tym miejscu używamy CZYSTEGO adresu URL, bez opcji M3U.
        response = requests.head(url, timeout=timeout, allow_redirects=True, headers=headers)
        return {'url': url, 'status_code': response.status_code, 'exception': None}
        
    except requests.exceptions.RequestException as e:
        # Wychwytuje błędy: timeout, DNS, brak połączenia, błędy SSL itp.
        return {'url': url, 'status_code': None, 'exception': type(e).__name__}

def get_stream_status(result):
    """
    Determinuje finalny status (OK, ALIVE, FAIL) i powód na podstawie surowego wyniku.
    
    Polityka filtrowania (zmodyfikowana): 
    - OK i ALIVE są ZACHOWYWANE.
    - FAIL jest ODRZUCANY.
    
    Returns:
        A tuple: (status_verdict: str, reason: str, is_working: bool)
    """
    status_code = result['status_code']
    exception = result['exception']
    
    # 1. Błędy Połączenia/Wyjątki
    if exception:
        # Błędy połączenia (Timeout, DNS) to wyraźna awaria - ODRZUCAMY
        return 'FAIL', f"Connection Failed ({exception})", False
    
    # 2. Statusy OK (2xx)
    if 200 <= status_code < 300:
        # Zdecydowanie działa - ZACHOWUJEMY
        return 'OK', f"Success ({status_code})", True
        
    # 3. Statusy ALIVE (Serwer odpowiada, ale odmawia dostępu/metody)
    # 400, 403, 405 (Method Not Allowed), 421 (Misdirected Request)
    if status_code in (400, 403, 405, 421):
        # Serwer żyje, ale odrzucił HEAD. ZACHOWUJEMY jako "ALIVE".
        return 'ALIVE', f"Server Responded ({status_code})", True

    # 4. Statusy FAIL (Wyraźna awaria)
    if status_code == 404:
        # Nie znaleziono - ODRZUCAMY
        return 'FAIL', f"Not Found ({status_code})", False
    
    if 500 <= status_code < 600:
        # Błąd serwera - ODRZUCAMY
        return 'FAIL', f"Server Error ({status_code})", False
        
    # 5. Domyślny FAIL dla wszystkich innych kodów (np. 401 Unauthorized, 409 Conflict)
    # Jeśli serwer odrzucił połączenie z innego powodu niż 400/403/405/421, to
    # jest to duża szansa na trwały problem (np. wymagana autoryzacja). ODRZUCAMY
    return 'FAIL', f"Unexpected Error ({status_code})", False


def process_m3u_file(input_file, output_file, timeout, max_workers, user_agent):
    """Reads the M3U file, filters streams, and writes a new list."""
    
    print(f"Loading input file: {input_file}...")
    
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Error: Input file not found: {input_file}")
        return

    working_streams = []
    urls_to_check = []
    # Zmieniamy mapowanie, aby przechowywać (nagłówek EXTINF, oryginalna pełna linia streamu)
    # Kluczem jest CZYSTY adres URL.
    url_to_extinf_and_line = {}
    current_extinf = None
    stream_results = [] # Lista do przechowywania pełnych wyników w oryginalnej kolejności

    for line in lines:
        line = line.strip()
        
        # Filtracja pustych linii
        if not line:
            continue
            
        if line.startswith('#EXTM3U'):
             working_streams.append(line)
        elif line.startswith('#EXTINF'):
            current_extinf = line
        elif current_extinf and line.startswith('http'):
            
            original_stream_line = line # Pełna linia, np. 'http://url|User-Agent=VLC'
            clean_url = original_stream_line
            
            # --- DODANA LOGIKA OBSŁUGI OPCJI M3U (np. |User-Agent=...) ---
            if '|' in original_stream_line:
                # Rozdzielamy pełną linię na czysty URL i opcje, ale używamy tylko czystego URL do sprawdzenia
                clean_url = original_stream_line.split('|', 1)[0].strip()
            # -------------------------------------------------------------
            
            urls_to_check.append(clean_url)
            # Mapujemy CZYSTY URL na parę: (EXTINF, oryginalna linia streamu z opcjami)
            url_to_extinf_and_line[clean_url] = (current_extinf, original_stream_line)
            current_extinf = None
        
    print(f"Found {len(urls_to_check)} streams to check. Starting test with {max_workers} threads...")
    print(f"Using User-Agent: {user_agent}")
    
    # Użycie ThreadPoolExecutor do równoległego sprawdzania streamów
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Tworzymy listę argumentów, które mają być przekazane do funkcji check_stream_reachability
        args_list = [(url, timeout, user_agent) for url in urls_to_check]
        
        # Metoda submit pozwala na użycie wielu argumentów
        futures = [executor.submit(check_stream_reachability, *args) for args in args_list]
        
        # Pobieranie wyników w kolejności ich złożenia (gwarantuje zachowanie kolejności)
        stream_results = [f.result() for f in futures]

    status_summary = defaultdict(int)
    success_count = 0
    
    print("\n--- CHECKING RESULTS ---")
    
    # Przetwarzanie surowych wyników i budowanie listy
    for result in stream_results:
        clean_url = result['url'] # Klucz to czysty URL
        status, reason, is_working = get_stream_status(result)
        
        # Śledzenie statusu dla podsumowania
        status_summary[(status, reason)] += 1
        
        # Wypisywanie decyzji
        print(f"[{status:<5}] {reason:<30} - {clean_url}")

        if is_working:
            # Pobieramy oryginalne dane streamu
            extinf, original_line = url_to_extinf_and_line.get(clean_url)
            if extinf:
                # Dodawanie nagłówka i ORYGINALNEJ LINI (z opcjami) do listy wyjściowej
                working_streams.append(extinf)
                working_streams.append(original_line)
                success_count += 1

    # Zapisywanie wyników do pliku wyjściowego
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write('\n'.join(working_streams) + '\n')
    except Exception as e:
        print(f"Error writing to file {output_file}: {e}")
        return
    
    print(f"\n--- COMPLETED AND SUMMARY ---")
    print(f"Total streams checked: {len(urls_to_check)}")
    print(f"Streams included in '{output_file}': {success_count}")
    print("\nOBSERVED STATUS CODES AND DECISIONS:")

    # Sortowanie podsumowania wg statusu (OK, ALIVE, FAIL)
    status_order = {'OK': 0, 'ALIVE': 1, 'FAIL': 2}
    sorted_summary = sorted(status_summary.items(), key=lambda item: (status_order[item[0][0]], item[1]), reverse=False)
    
    for (status, reason), count in sorted_summary:
        print(f"  {count:>4} streams -> [{status:<5}] {reason}")
    
    print("\nDecision Policy:")
    print("  [OK]: Stream jest DEFINITYWNIE działający (HTTP 2xx). Zachowany.")
    print("  [ALIVE]: Stream jest PRAWDOPODOBNIE działający (HTTP 400, 403, 405, 421 - Serwer odpowiada, ale odrzucił HEAD). Zachowany.")
    print("  [FAIL]: Stream jest USZKODZONY (HTTP 404, 5xx, inne 4xx lub błąd połączenia). Usunięty.")


def main():
    """Sets up argument parsing and runs the M3U processing function."""
    parser = argparse.ArgumentParser(
        description="M3U Stream Checker: Filters an M3U playlist based on stream reachability.",
        formatter_class=argparse.RawTextHelpFormatter
    )

    # Wymagane argumenty
    parser.add_argument(
        '-i', '--input',
        type=str,
        required=True,
        help="Path to the input M3U playlist file (e.g., 'input.m3u')."
    )
    
    # Opcjonalne argumenty
    parser.add_argument(
        '-o', '--output',
        type=str,
        default='working_list.m3u',
        help="Path for the output file with working streams (Default: 'working_list.m3u')."
    )
    parser.add_argument(
        '-t', '--timeout',
        type=int,
        default=5,
        help="Timeout in seconds for checking each stream (Default: 5)."
    )
    parser.add_argument(
        '-w', '--workers',
        type=int,
        default=20,
        help="Number of concurrent threads to use for checking streams (Default: 20)."
    )
    parser.add_argument(
        '-u', '--user-agent',
        type=str,
        default=DEFAULT_USER_AGENT,
        help=f"Custom User-Agent string for HTTP requests (Default: '{DEFAULT_USER_AGENT}')."
    )

    args = parser.parse_args()
    
    # Uruchomienie głównej funkcji przetwarzającej
    process_m3u_file(
        input_file=args.input,
        output_file=args.output,
        timeout=args.timeout,
        max_workers=args.workers,
        user_agent=args.user_agent
    )

if __name__ == '__main__':
    main()
