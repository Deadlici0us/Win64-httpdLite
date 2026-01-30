import socket
import threading
import sys
import time
import os

HOST = '127.0.0.1'
PORT = 8080
METHODS = ['GET', 'POST', 'HEAD', 'PUT', 'PATCH', 'DELETE']
HTML_PATH = os.path.join(os.path.dirname(__file__), 'html', 'index.html')

# Read expected HTML exactly as binary
with open(HTML_PATH, 'rb') as f:
    EXPECTED_BODY = f.read()
EXPECTED_LEN = len(EXPECTED_BODY)

results = {"success": 0, "failure": 0}
lock = threading.Lock()

def test_method(method):
    global results
    
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(3)
            s.connect((HOST, PORT))
            request = f"{method} / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
            s.sendall(request.encode())
            
            data = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                data += chunk
            
            if len(data) == 0:
                print(f"[{method}] Failed: No response")
                return False

            header_end = data.find(b'\r\n\r\n')
            if header_end == -1:
                # Malformed response
                print(f"[{method}] Failed: Malformed response (no header end)")
                return False
            
            headers_raw = data[:header_end].decode()
            body = data[header_end+4:]
            
            status_line = headers_raw.split('\r\n')[0]
            
            if method == 'GET':
                if "200 OK" not in status_line:
                    print(f"[{method}] Failed: Status not 200. Got: {status_line}")
                    return False
                if body != EXPECTED_BODY:
                    print(f"[{method}] Failed: Body mismatch")
                    return False

            elif method == 'HEAD':
                if "200 OK" not in status_line:
                    print(f"[{method}] Failed: Status not 200. Got: {status_line}")
                    return False
                if len(body) > 0:
                    print(f"[{method}] Failed: HEAD should not return body. Got {len(body)} bytes")
                    return False
                # Check Content-Length header is present and correct (case-insensitive check needed really, but server sends PascalCase)
                if f"Content-Length: {EXPECTED_LEN}" not in headers_raw:
                     print(f"[{method}] Failed: Missing or incorrect Content-Length for HEAD")
                     return False

            else:
                # POST, PUT, DELETE, etc.
                # Should return 405 Method Not Allowed
                if "405" not in status_line:
                    print(f"[{method}] Failed: Status should be 405. Got: {status_line}")
                    return False
                    
            return True

    except Exception as e:
        print(f"[{method}] Error: {e}")
        return False

def run_tests():
    global results
    failed = False
    print(f"Testing methods: {', '.join(METHODS)}")
    
    for method in METHODS:
        if test_method(method):
            with lock:
                results["success"] += 1
            print(f"[{method}] Passed")
        else:
            with lock:
                results["failure"] += 1
            failed = True
            
    print(f"\nResults: Success: {results['success']}, Failure: {results['failure']}")
    sys.exit(1 if failed else 0)

if __name__ == "__main__":
    run_tests()
