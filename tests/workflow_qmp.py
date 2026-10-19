"""Small QMP test driver; uses QEMU's virtual keyboard, not a desktop session."""
import json
import socket
import sys

class QMP:
    def __init__(self, path):
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.settimeout(15)
        self.socket.connect(path)
        self.stream = self.socket.makefile('rwb', buffering=0)
        self.read()
        self.command('qmp_capabilities')

    def read(self):
        return json.loads(self.stream.readline())

    def command(self, name, arguments=None):
        value = {'execute': name}
        if arguments is not None:
            value['arguments'] = arguments
        self.stream.write(json.dumps(value).encode() + b'\n')
        while True:
            answer = self.read()
            if 'error' in answer:
                raise RuntimeError(answer['error'])
            if 'return' in answer:
                return answer['return']

if __name__ == '__main__':
    qmp = QMP(sys.argv[1])
    if sys.argv[2] == 'key':
        qmp.command('send-key', {'keys': [{'type': 'qcode', 'data': sys.argv[3]}], 'hold-time': 150})
    elif sys.argv[2] == 'screenshot':
        qmp.command('screendump', {'filename': sys.argv[3]})
    else:
        print(qmp.command('query-status'))
