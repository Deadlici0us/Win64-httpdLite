import socket
import sys
import time

HOST = '127.0.0.1'
PORT = 8080

def test_request(path, expected_status="200 OK"):
    print(f"Requesting {path}...")
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect((HOST, PORT))
        
        request = f"GET {path} HTTP/1.1\r\nHost: {HOST}\r\nConnection: close\r\n\r\n"
        s.sendall(request.encode())
        
        data = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        s.close()
        
        if not data:
            print("Failed: No data received")
            return False
            
        header_end = data.find(b'\r\n\r\n')
        headers = data[:header_end].decode()
        status_line = headers.split('\r\n')[0]
        
        if expected_status in status_line:
            print(f"Success: {status_line}")
            return True
        else:
            print(f"Failed: Expected {expected_status}, got {status_line}")
            return False
            
    except Exception as e:
        print(f"Exception: {e}")
        return False

if __name__ == "__main__":
    success = True
    if not test_request("/index.html"): success = False
    if not test_request("/subdir/sub.html"): success = False
    
    if success:
        print("All recursive tests passed.")
        sys.exit(0)
    else:
        sys.exit(1)
