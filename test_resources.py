import socket
import sys
import time
import os

HOST = '127.0.0.1'
PORT = 80
RESOURCE_PATH = os.path.join(os.path.dirname(__file__), 'html', 'httpdLite.png')

def test_resource():
    print(f"Loading expected content from {RESOURCE_PATH}")
    with open(RESOURCE_PATH, 'rb') as f:
        expected_data = f.read()

    try:
        print(f"Requesting /httpdLite.png from {HOST}:{PORT}...")
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect((HOST, PORT))
        
        request = b"GET /httpdLite.png HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        s.sendall(request)
        
        data = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        
        s.close()
        
        header_end = data.find(b'\r\n\r\n')
        if header_end == -1:
            print("Test Failed: Malformed response")
            return False
            
        headers_raw = data[:header_end].decode()
        body = data[header_end+4:]
        
        lines = headers_raw.split('\r\n')
        status_line = lines[0]
        
        if "200 OK" not in status_line:
            print(f"Test Failed: Status not 200. Got: {status_line}")
            return False

        headers = {}
        for line in lines[1:]:
            if ':' in line:
                key, val = line.split(':', 1)
                headers[key.strip().lower()] = val.strip()

        # Check Content-Type for PNG
        content_type = headers.get('content-type', '')
        if 'image/png' not in content_type:
             print(f"Test Failed: Content-Type should be image/png. Got: {content_type}")
             return False

        # Check Content
        if body != expected_data:
            print(f"Test Failed: Body mismatch. Expected {len(expected_data)} bytes, got {len(body)}")
            return False
            
        print("Test Passed: Served /httpdLite.png correctly with image/png type.")
        return True

    except Exception as e:
        print(f"Test Failed: {e}")
        return False

if __name__ == "__main__":
    if test_resource():
        sys.exit(0)
    else:
        sys.exit(1)