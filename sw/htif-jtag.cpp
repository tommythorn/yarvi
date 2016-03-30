#include <stdio.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <assert.h>
#include <time.h>
#include <stdlib.h>
#include "jtag_atlantic.h"
#include "common.h"

static const unsigned int bytes_to_receive = 1<<20;
static char buf[8192];

static int
parse_addr(const char *v, uint32_t *res)
{
    char *p;

    *res = strtol(v, &p, 16);

    return *p != 0;
}

static void
usage(void)
{
    fprintf(stderr,
            "htif write $ADDR < $binary_file\n"
            "htif read $ADDR $LEN > $binary_file\n"
            "    where $ADDR and $LEN is 32-bit aligned\n");

    exit(EXIT_FAILURE);
}

static void
htif_write(uint32_t addr)
{
    JTAGATLANTIC *atlantic = jtagatlantic_open(NULL, -1, -1, "htif");

    if (!atlantic) {
        show_err();
	return;
    }

    show_info(atlantic);

    struct timespec t_start;
    clock_gettime(CLOCK_MONOTONIC, &t_start);

    buf[0] = 'a';
    memcpy(buf + 1, &addr, sizeof addr);
    if (jtagatlantic_write(atlantic, buf, 5) != 5) {
      fprintf(stderr, "short write\n");
      goto exit;
    }
    buf[0] = 'w';

    for (;;) {
        uint32_t data = 0;

        size_t n = fread(&data, sizeof data, 1, stdin);

        if (n) {
            memcpy(buf + 1, &data, sizeof data);
            if (jtagatlantic_write(atlantic, buf, 5) != 5) {
	      fprintf(stderr, "short write\n");
	      goto exit;
	    }
        }

        if (n < sizeof data)
            break;
    }

    if (jtagatlantic_flush(atlantic)) {
      fprintf(stderr, "fail on flush\n");
      goto exit;
    }

exit:
    jtagatlantic_close(atlantic);
}

static void
htif_read(uint32_t addr, int32_t len)
{
    JTAGATLANTIC *atlantic = jtagatlantic_open(NULL, -1, -1, "htif");

    if (!atlantic) {
        show_err();
	return;
    }

    show_info(atlantic);

    buf[0] = 'a';
    memcpy(buf + 1, &addr, sizeof addr);
    if (jtagatlantic_write(atlantic, buf, 5) < 0) {
      fprintf(stderr, "short write\n");
      goto exit;
    }

    for (; len >= 8; len -= 8) {
        buf[0] = 'R';

	if (jtagatlantic_write(atlantic, buf, 1) != 1) {
	  fprintf(stderr, "short write\n");
	  goto exit;
	}

	if (jtagatlantic_flush(atlantic)) {
	  fprintf(stderr, "flush error\n");
	  goto exit;
	}

	int n = 8;
	char *p = buf;

	do {
	  int got = jtagatlantic_read(atlantic, p, n);

          if (got == 0)
              usleep(1000);
          else if (got < 0) {
	    fprintf(stderr, "short read %d\n", got);
	    jtagatlantic_close(atlantic);
	    atlantic = jtagatlantic_open(NULL, -1, -1, "htif");
	    got = 0;
	  }

	  p += got;
	  n -= got;
	} while (n > 0);

	fwrite(buf, 8, 1, stdout);
    }

 exit:
    fprintf(stderr, "close\n");
    jtagatlantic_close(atlantic);
}

int
main(int c, char **v)
{
  uint32_t addr, len;

  if (c == 3 && !strcmp(v[1], "write") && !parse_addr(v[2], &addr))
    htif_write(addr);
  else if (c == 4 && !strcmp(v[1], "read") && !parse_addr(v[2], &addr) && !parse_addr(v[3], &len))
    htif_read(addr, len);
  else
    usage();

  return 0;
}
