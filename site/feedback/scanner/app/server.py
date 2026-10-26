"""Private HTTP endpoint. Cloudflare only reaches this through a service binding."""
import json
import multiprocessing
import os
import signal
from http.server import BaseHTTPRequestHandler, HTTPServer

from engines import ProductionEngines
from scan import Scanner, strict_json

MAX_REQUEST=36_000_000
MAX_RESPONSE=24_000_000


def child(connection,job):
    try: connection.send_bytes(json.dumps(Scanner(ProductionEngines()).scan(job)).encode())
    except BaseException: connection.send_bytes(b'{"version":1,"status":"held","reasonCodes":["scanner_error"]}')
    finally: connection.close()


def run_job(job):
    # A job gets a fresh process. Timeout terminates its parser and all child tools.
    context=multiprocessing.get_context('fork')
    receive,send=context.Pipe(duplex=False)
    def isolated(connection,value):
        os.setsid()
        child(connection,value)
    process=context.Process(target=isolated,args=(send,job)); process.start(); send.close()
    try:
        if receive.poll(120): return strict_json(receive.recv_bytes(MAX_RESPONSE))
        return {'version':1,'status':'held','reasonCodes':['scanner_timeout']}
    finally:
        if process.is_alive():
            try: os.killpg(process.pid,signal.SIGKILL)
            except ProcessLookupError: pass
        process.join(timeout=2); receive.close()


class Handler(BaseHTTPRequestHandler):
    protocol_version='HTTP/1.1'
    def log_message(self,*args): pass
    def reply(self,status,value):
        body=json.dumps(value,separators=(',',':')).encode()
        if len(body)>MAX_RESPONSE:
            status=503; body=b'{"version":1,"status":"held","reasonCodes":["scanner_output_limit"]}'
        self.send_response(status); self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(body))); self.send_header('Connection','close'); self.end_headers()
        self.wfile.write(body); self.close_connection=True
    def do_GET(self):
        if self.path=='/ready': self.reply(200,{'ready':True})
        else: self.reply(404,{'error':'not_found'})
    def do_POST(self):
        self.connection.settimeout(15)
        if self.path!='/scan' or self.headers.get('Transfer-Encoding'):
            self.reply(400,{'error':'invalid_request'}); return
        try:
            length=int(self.headers.get('Content-Length','0'))
            if not 1<=length<=MAX_REQUEST: raise ValueError()
            if self.headers.get_content_type()!='application/json': raise ValueError()
            body=self.rfile.read(length)
            if len(body)!=length: raise ValueError()
            result=run_job(strict_json(body))
            self.reply(200,result)
        except Exception:
            self.reply(400,{'version':1,'status':'held','reasonCodes':['invalid_job']})


if __name__=='__main__':
    HTTPServer(('0.0.0.0',8080),Handler).serve_forever()
