import socket
import threading
import time
import sys
import os

HOST = '127.0.0.1'
PORT = 80
CLIENT_COUNT = 50
HTTP_REQUEST = b"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
HTML_PATH = os.path.join(os.path.dirname(__file__), 'html', 'index.html')

# Read expected HTML exactly as binary
with open(HTML_PATH, 'rb') as f:
    EXPECTED_BODY = f.read()

success_count = 0
lock = threading.Lock()

def client_task(client_id):
    global success_count
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5)
            s.connect((HOST, PORT))
            s.sendall(HTTP_REQUEST)
            
            data = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                data += chunk

            header_end = data.find(b'\r\n\r\n')
            if header_end == -1:
                print(f"Client {client_id}: Malformed response")
                return
                
            body = data[header_end+4:]
            
            if body == EXPECTED_BODY:
                with lock:
                    success_count += 1
            else:
                print(f"Client {client_id}: Mismatch. Got len {len(body)}, expected {len(EXPECTED_BODY)}")

    except Exception as e:
        print(f"Client {client_id}: Connection Error: {type(e).__name__} - {e}")

def wait_for_server(host, port, timeout=5):
    """Wait for the server to be ready to accept connections."""
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            with socket.create_connection((host, port), timeout=1):
                return True
        except (ConnectionRefusedError, socket.timeout):
            time.sleep(0.1)
    return False

def run_test():
    if not wait_for_server(HOST, PORT):
        print(f"Error: Server at {HOST}:{PORT} not responding.")
        sys.exit(1)
        
    print(f"Starting {CLIENT_COUNT} clients...")
    threads = []
    for i in range(CLIENT_COUNT):
        t = threading.Thread(target=client_task, args=(i,))
        threads.append(t)
        t.start()
    
    for t in threads:
        t.join()

    print(f"Finished. Success: {success_count}/{CLIENT_COUNT}")
    if success_count == CLIENT_COUNT:
        print("Concurrency Test PASSED")
        sys.exit(0)
    else:
        print("Concurrency Test FAILED")
        sys.exit(1)

if __name__ == "__main__":
    run_test()
