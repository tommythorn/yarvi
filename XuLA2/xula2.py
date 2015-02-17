import sys
import select
import tty
import termios
from xstools.xscomm import XsComm

USB_ID = 0  # This is the USB index for the XuLA board connected to the host PC.
comm = XsComm(xsusb_id=USB_ID, module_id=255)

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

if __name__ == '__main__':

    with NonBlockingConsole() as nbc:

        ch = False

        while True:
            if comm.get_send_buffer_space() > 0:
                ch = nbc.get_data()
                if ch:
                    comm.send(ord(ch), wait=True)

            buf = ''.join([chr(d.unsigned) for d in comm.receive(always_list=True)])
            if not (buf == ""):
                sys.stdout.write(buf)
                sys.stdout.flush()
