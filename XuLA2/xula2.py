import sys
import select
import tty
import termios
import struct
from xstools.xscomm import XsComm

USB_ID = 0  # This is the USB index for the XuLA board connected to the host PC.
comm = XsComm(xsusb_id=USB_ID, module_id=255)
addr_tracker = 0xFFFFFFFF

# Adapted from
# http://stackoverflow.com/questions/24582491/python-non-blocking-non-messing-my-tty-key-press-detection
class NonBlockingConsole(object):

    def __enter__(self):
        try:
            self.old_settings = termios.tcgetattr(sys.stdin)
            tty.setcbreak(sys.stdin.fileno())
        finally:
          return self

    def __exit__(self, type, value, traceback):
        try: termios.tcsetattr(sys.stdin, termios.TCSADRAIN, self.old_settings)
        finally:
            pass

    def get_data(self):
        if select.select([sys.stdin], [], [], 0) == ([sys.stdin], [], []):
            return sys.stdin.read(1)
        return False

def r32(addr):
    global addr_tracker
    if addr_tracker == addr:
        comm.send([ord('r')], wait=True)
    else:
        comm.send([ord(c) for c in 'a'+struct.pack("I", addr)+'r'], wait=True)
    packet = ''.join([chr(d.unsigned) for d in comm.receive(num_words=4)])
    addr_tracker = addr + 4
    return struct.unpack("I", packet)[0]

def w32(addr,data):
    global addr_tracker
    if addr_tracker == addr:
        comm.send([ord(c) for c in 'w'+struct.pack("I", data)], wait=True)
    else:
        comm.send([ord(c) for c in 'a'+struct.pack("I", addr)+
                                   'w'+struct.pack("I", data)], wait=True)
    addr_tracker = addr + 4

def demo():
    print "Before"
    addr = 0
    while addr < 32:
        print "%08x" % r32(addr)
        addr = addr + 4

    w32( 0, 0x11111)
    w32( 4, 0x44444)
    w32(12, 0xCCCCC)

    print "After"
    addr = 0
    while addr < 32:
        print "%08x" % r32(addr)
        addr = addr + 4

if __name__ == '__main__':

    with NonBlockingConsole() as nbc:

        demo()
