#!/usr/bin/env python3
"""Run one shell command on the frame's USB ACM console and print the output.

Usage: scripts/acm-run.py '<command>' [seconds-to-wait]
The console is the shell our initramfs (or later systemd) starts on ttyGS0;
it appears on macOS as /dev/cu.usbmodem*.
"""
import glob, os, select, sys, termios, time

devs = glob.glob('/dev/cu.usbmodem*')
if not devs:
    sys.exit('no /dev/cu.usbmodem* (frame console not connected)')
fd = os.open(devs[0], os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[0] = attrs[1] = attrs[3] = 0                      # raw
attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
attrs[4] = attrs[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, attrs)


def drain(seconds):
    out, end = b'', time.time() + seconds
    while time.time() < end:
        if select.select([fd], [], [], 0.2)[0]:
            try:
                out += os.read(fd, 65536)
            except BlockingIOError:
                pass
            except OSError:      # device went away (e.g. after "reboot")
                break
    return out


drain(0.5)
os.write(fd, sys.argv[1].encode() + b'\n')
sys.stdout.write(drain(float(sys.argv[2]) if len(sys.argv) > 2 else 3)
                 .decode(errors='replace').replace('\r', ''))
