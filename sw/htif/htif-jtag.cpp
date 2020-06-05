#include <stdio.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <assert.h>
#include <time.h>
#include <stdlib.h>
#include "jtag_atlantic.h"
#include "common.h"

static JTAGATLANTIC *atlantic;
static char transmission[16*1024];
static int pending = 0;
static int total = 0;
static int verbose = 0;

static void htif_write(const char *data, size_t len, int flush) {
    if ((flush && pending) || pending + len >= sizeof transmission) {
        char *p = transmission;
        size_t n = pending;

        do {
            int wrote = jtagatlantic_write(atlantic, p, n);

            if (wrote == 0) {
                usleep(10000);
                if (verbose)
                    fputc('.', stderr);
            } else if (wrote < 0) {
                fprintf(stderr, "write failure %d\n", wrote);
                jtagatlantic_close(atlantic);
                atlantic = jtagatlantic_open(NULL, -1, -1, "htif");
                wrote = 0;
                if (verbose)
                    fputc('!', stderr);
            }

            n -= wrote;
            p += wrote;
            total += wrote;
        } while (0 < n);
        pending = 0;
    }

    memcpy(transmission + pending, data, len);
    pending += len;

    if (flush && jtagatlantic_flush(atlantic))
        if (verbose)
            fprintf(stderr, "flush error\n");
}

static void htif_read(char *data, size_t len) {
    char *p = data;
    size_t n = len;

    htif_write(NULL, 0, 1);

    do {
        int read = jtagatlantic_read(atlantic, p, n);

        if (read == 0) {
            usleep(10000);
            if (verbose)
                fputc('.', stderr);
        } else if (read < 0) {
            fprintf(stderr, "read failure %d\n", read);
            jtagatlantic_close(atlantic);
            atlantic = jtagatlantic_open(NULL, -1, -1, "htif");
            read = 0;
            if (verbose)
                fputc('!', stderr);
        }

        n -= read;
        p += read;
        total += read;
    } while (0 < n);
}

static int parse_addr(const char *v, uint32_t *res) {
    char *p;

    *res = strtol(v, &p, 16);

    return *p != 0;
}

static void htif_cmd_write(uint32_t addr) {
    htif_write("a", 1, 0);
    htif_write((char *)&addr, sizeof addr, 0);

    for (;;) {
        uint32_t data = 0;

        if (fread(&data, sizeof data, 1, stdin) != 1)
            break;

        htif_write("w", 1, 0);
        htif_write((char *)&data, sizeof data, 0);
    }
}

static void htif_cmd_read(uint32_t addr, int32_t len) {
    htif_write("a", 1, 0);
    htif_write((char *)&addr, sizeof addr, 0);

    for (int n = 0; n < len; n += 8)
        htif_write("R", 1, 0);

    char *buf = (char*)malloc(len);

    htif_read(buf, len);
    fwrite(buf, len, 1, stdout);
    free(buf);
}

static void usage(void) {
    fprintf(stderr,
            "htif write $ADDR < $binary_file\n"
            "htif read $ADDR $LEN > $binary_file\n"
            "    where $ADDR and $LEN is 32-bit aligned\n");

    exit(EXIT_FAILURE);
}


int main(int c, char **v) {
    int device = 1;
    int instance = 0;
    uint32_t addr, len;

    --c, ++v;
    if (c == 0)
        usage();

    if (strcmp(v[0], "-v") == 0)
        verbose = 1, --c, ++v;

    atlantic = jtagatlantic_open(NULL, device, instance, "htif");
    if (!atlantic) {
        show_err();
	exit(EXIT_FAILURE);
    }

    if (verbose) {
        show_info(atlantic);

        if (jtagatlantic_cable_warning(atlantic))
            fprintf(stderr, "Warning: older ByteBlaster, might be less reliable\n");
    }

    struct timespec t_start;
    clock_gettime(CLOCK_MONOTONIC, &t_start);


    for (;;)
        if (c >= 2 && !strcmp(v[0], "write") && !parse_addr(v[1], &addr)) {
            htif_cmd_write(addr);
            v += 2;
            c -= 2;
        }
        else if (c >= 3 && !strcmp(v[0], "read") && !parse_addr(v[1], &addr) &&
                 !parse_addr(v[2], &len)) {
            htif_cmd_read(addr, len);
            v += 3;
            c -= 3;
        } else
            break;

    htif_write(NULL, 0, 1);

    struct timespec t_stop;
    clock_gettime(CLOCK_MONOTONIC, &t_stop);

    double duration =
      t_stop.tv_sec - t_start.tv_sec +
      (t_stop.tv_nsec - t_start.tv_nsec)*1e-9;

    if (verbose)
        fprintf(stderr, "\nTook %.2f s, %.1f kB/s\n",
                duration, total / duration / 1000);
    jtagatlantic_close(atlantic);

    return 0;
}
