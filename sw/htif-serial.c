/*
 * Utility to up- and down-load memory contents:
 * 1) ctrlyarvi $PORT read $ADDRESS $N > $FILE
 * 2) ctrlyarvi $PORT write $ADDRESS < $FILE
 * 3) ctrlyarvi $PORT monitor
 *
 * $N has to be a multiple of 4.  $ADDRESS and $N have to be in hex
 * monitor is for a TBD IO protocol
 */


// From: http://stackoverflow.com/questions/6947413/how-to-open-read-and-write-from-serial-port-in-c
// ... but that didn't work for me on Mac OS X so it's modified.

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

#define MAX_MEMORY_SIZE (256*1024)

static int
set_interface_attribs(int fd, int speed, int parity)
{
    struct termios tty = { 0 };

    // memset(&tty, 0, sizeof tty);

    if (tcgetattr(fd, &tty) != 0)
        err(1, "error from tcgetattr");

    cfsetospeed(&tty, speed);
    cfsetispeed(&tty, speed);

    tty.c_cflag = (tty.c_cflag & ~CSIZE) | CS8;     // 8-bit chars

    // disable IGNBRK for mismatched speed tests; otherwise receive break
    // as \000 chars
    tty.c_iflag &= ~IGNBRK;         // disable break processing
    tty.c_lflag = 0;                // no signaling chars, no echo,
    // no canonical processing
    tty.c_oflag = 0;                // no remapping, no delays
    tty.c_cc[VMIN]  = 0;            // read doesn't block
    tty.c_cc[VTIME] = 5;            // 0.5 seconds read timeout

    tty.c_iflag &= ~(IXON | IXOFF | IXANY); // shut off xon/xoff ctrl

    tty.c_cflag |= CLOCAL | CREAD;  // ignore modem controls,
    // enable reading
    tty.c_cflag &= ~(PARENB | PARODD);      // shut off parity
    tty.c_cflag |= parity;
    tty.c_cflag &= ~CSTOPB;
    tty.c_cflag &= ~CRTSCTS;

    if (tcsetattr(fd, TCSANOW, &tty) != 0)
        err(1, "error from tcsetattr");

    return 0;
}

static void
set_blocking(int fd, int should_block)
{
    struct termios tty = { 0 };

    // memset(&tty, 0, sizeof tty);

    if (tcgetattr(fd, &tty) != 0)
        err(1, "error from tggetattr");

    tty.c_cc[VMIN]  = should_block ? 1 : 0;
    tty.c_cc[VTIME] = 5;            // 0.5 seconds read timeout

    if (tcsetattr(fd, TCSANOW, &tty) != 0)
        err(1, "error setting term attributes");
}

static uint32_t
fromhex(const char *s)
{
    char *p;
    uint32_t res = strtol(s, &p, 16);

    if (*p)
        errx(1, "%s is a hex value", s);

    return res;
}

static void
write4(int fd, uint32_t v)
{
    union {
        uint8_t b[4];
        uint32_t w;
    } data;

    data.w = v;

    write(fd, data.b, 4);
}

static uint32_t
read4(int fd)
{
    int n = 4;

    union {
        uint8_t b[4];
        uint32_t w;
    } data;

    uint8_t *p = data.b;

    while (n) {
        int got = read(fd, p, n);
        if (got < 0) {
            if (errno != EAGAIN)
                err(1, "reading from serial");
        } else {
            n -= got;
            p += got;
        }

        //usleep(10);
    }

    return data.w;
}

static void
write_to_yarvi(int fd, uint8_t *data, uint32_t addr, ssize_t len)
{
    uint32_t *wp = (uint32_t *)data;

    write(fd, "a", 1);
    write4(fd, addr);

    while (len >= 4) {
        write(fd, "w", 1);
        write4(fd, *wp++);
        len -= 4;
    }
}

static void
read_from_yarvi(int fd, uint8_t *data, uint32_t addr, ssize_t len)
{
    uint32_t *wp = (uint32_t *)data;
    int rs;

    write(fd, "a", 1);
    write4(fd, addr);

    if (len >= 8)
        write(fd, "R", 1), rs = 8;
    else if (len >= 4)
        write(fd, "r", 1), rs = 4;

    while (rs) {
        int nrs;
        if (len - rs >= 8)
            write(fd, "R", 1), nrs = 8;
        else if (len - rs >= 4)
            write(fd, "r", 1), nrs = 4;
        else
            nrs = 0;

        *wp++ = read4(fd);
        if (rs > 4)
            *wp++ = read4(fd);

        len -= rs;
        rs = nrs;
    }
}

int
main(int argc, char **argv)
{
    if (argc < 2)
        errx(1, "Usage: %s $PORT ( read $ADDR $LEN | write $ADDR )", argv[0]);

    int fd = open(argv[1], O_RDWR | O_NOCTTY /* | O_SYNC */ | O_NONBLOCK);
    if (fd < 0)
        err(1, "error opening %s", argv[1]);

    fprintf(stderr, "%s is open\n", argv[1]);

    set_interface_attribs(fd, B115200, 0);  // set speed to 115_200 bps, 8n1 (no parity)
    set_blocking(fd, 1);                    // set blocking

    argv += 2;
    argc -= 2;

    if (argc == 3 && strcmp(argv[0], "read") == 0) {
        uint32_t addr = fromhex(argv[1]);
        uint32_t len  = fromhex(argv[2]);
        uint8_t *buf  = (uint8_t *)malloc(len);

        read_from_yarvi(fd, buf, addr, len);
        write(1, buf, len);
        free(buf);
    } else if (argc == 2 && strcmp(argv[0], "write") == 0) {
        uint32_t addr = fromhex(argv[1]);
        uint8_t *buf  = (uint8_t *)malloc(MAX_MEMORY_SIZE);
        int      len  = read(0, buf, MAX_MEMORY_SIZE);
        write_to_yarvi(fd, buf, addr, len);
        free(buf);
    } else {
        errx(1, "Sorry, I can't do that");
    }

    return 0;
}
