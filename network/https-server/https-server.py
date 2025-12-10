#! /usr/bin/python3

import ssl
from http.server import HTTPServer, SimpleHTTPRequestHandler

# bind to all interfaces, use port 4433
httpd = HTTPServer(('0.0.0.0', 4433), SimpleHTTPRequestHandler)

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain("cert.pem", "key.pem")

httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
print("Starting HTTPS server on port 4433...")
httpd.serve_forever()
