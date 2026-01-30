import socket
import sys
import time
import os

HOST = '127.0.0.1'
PORT = 8080
HTML_PATH = os.path.join(os.path.dirname(__file__), 'html', 'index.html')

def test_server():
    print(f"Loading expected content from {HTML_PATH}")
    # Read expected HTML exactly as binary
    with open(HTML_PATH, 'rb') as f:
        expected_html = f.read()

    max_retries = 3
    for i in range(max_retries):
        try:
            print(f"Connecting to {HOST}:{PORT} (Attempt {i+1}/{max_retries})...")
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(5)
            s.connect((HOST, PORT))
            print("Connected.")
            
            request = b"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
            print("Sending GET request...")
            s.sendall(request)
            
            # Read all data
            data = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                data += chunk
            
            s.close()
            
            if len(data) == 0:
                print("Test Failed: No data received")
                return

            # Parse response
            header_end = data.find(b'\r\n\r\n')
            if header_end == -1:
                print("Test Failed: Malformed response (no header end)")
                return
                
            headers_raw = data[:header_end].decode()
            body = data[header_end+4:]
            
            lines = headers_raw.split('\r\n')
            status_line = lines[0]
            
            # 1. Check Status Line strict format
            if status_line != "HTTP/1.1 200 OK":
                print(f"Test Failed: Bad Status Line: '{status_line}'")
                print("Expected: 'HTTP/1.1 200 OK'")
                return

            # 2. Check Headers
            headers = {}
            for line in lines[1:]:
                if ':' in line:
                    key, val = line.split(':', 1)
                    headers[key.strip().lower()] = val.strip()
            
            # Check Content-Type
            if headers.get('content-type') != 'text/html':
                print(f"Test Failed: Bad Content-Type: {headers.get('content-type')}")
                return
            
            # Check Connection
            if headers.get('connection') != 'close':
                print(f"Test Failed: Bad Connection header: {headers.get('connection')}")
                return

            # Check Content-Length
            content_length = int(headers.get('content-length', -1))
            if content_length != len(expected_html):
                print(f"Test Failed: Content-Length header mismatch. Header: {content_length}, Expected: {len(expected_html)}")
                return
            
            if len(body) != content_length:
                 print(f"Test Failed: Actual body length ({len(body)}) != Content-Length header ({content_length})")
                 return

            # 3. Check Body Exact Match
            if body != expected_html:
                print("Test Failed: Body mismatch")
                print(f"Expected len: {len(expected_html)}, Got len: {len(body)}")
                return
                
            print("Test Passed: Status 200, Headers Correct (Type, Len, Conn), Body Exact Match")
            return
            
        except (ConnectionRefusedError, socket.timeout):
            if i < max_retries - 1:
                time.sleep(1)
                continue
            print("Test Failed: Connection refused or timed out.")
        except Exception as e:
            print(f"Test Failed: Exception: {e}")
            break

if __name__ == "__main__":
    test_server()