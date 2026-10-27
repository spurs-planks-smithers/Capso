"""Private HTTP endpoint. Cloudflare only reaches this through a service binding."""
import json
import multiprocessing
import os
import signal
import socketserver
import shutil
import tempfile
from pathlib import Path
from http.server import BaseHTTPRequestHandler, HTTPServer

from engines import ProductionEngines
from scan import Scanner, strict_json

MAX_REQUEST=36_000_000
MAX_RESPONSE=24_000_000


JOB_PARENT='/tmp'
CLEANUP_FAILED=False


class PrivateHTTPServer(HTTPServer):
    def server_bind(self):
        # Cloudflare's 64-character hostname cannot pass Python's IDNA lookup.
        socketserver.TCPServer.server_bind(self)
        self.server_name='localhost'
        self.server_port=self.server_address[1]


def held(reason):
    return {'version':1,'status':'held','reasonCodes':[reason]}


def child(connection,job):
    try:
        root=Path(os.environ['TMPDIR'])
        engines=ProductionEngines(temporary_root=root)
        connection.send_bytes(json.dumps(Scanner(engines).scan(job)).encode())
    except BaseException: connection.send_bytes(json.dumps(held('scanner_error')).encode())
    finally: connection.close()


def run_job(job):
    global CLEANUP_FAILED
    if CLEANUP_FAILED: return held('scanner_cleanup_failed')
    try: root=Path(tempfile.mkdtemp(prefix='nextshot-job-',dir=JOB_PARENT))
    except OSError: return held('scanner_temporary_storage')
    context=multiprocessing.get_context('fork')
    receive,send=context.Pipe(duplex=False)
    def isolated(connection,value):
        os.setsid()
        os.environ['TMPDIR']=str(root)
        tempfile.tempdir=str(root)
        child(connection,value)
    process=context.Process(target=isolated,args=(send,job))
    result=held('scanner_error')
    started=False
    try:
        process.start(); started=True; send.close()
        if receive.poll(120): result=strict_json(receive.recv_bytes(MAX_RESPONSE))
        else: result=held('scanner_timeout')
    except (OSError,EOFError,ValueError): result=held('scanner_error')
    finally:
        send.close()
        if started:
            # Kill the process group even after its main process exits. A tool
            # must not keep a private file open while the parent removes it.
            try: os.killpg(process.pid,signal.SIGKILL)
            except ProcessLookupError: pass
            except OSError: CLEANUP_FAILED=True
            if process.is_alive():
                try: process.kill()
                except OSError: CLEANUP_FAILED=True
            try: process.join(timeout=2)
            except (OSError,ValueError): CLEANUP_FAILED=True
            if process.is_alive(): CLEANUP_FAILED=True
        try: receive.close()
        except OSError: CLEANUP_FAILED=True
        try: shutil.rmtree(root)
        except OSError: CLEANUP_FAILED=True
    # A cleanup failure disables later jobs until the container is replaced.
    if CLEANUP_FAILED: return held('scanner_cleanup_failed')
    return result


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
    PrivateHTTPServer(('0.0.0.0',8080),Handler).serve_forever()
