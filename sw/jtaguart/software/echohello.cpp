#include <stdio.h>
#include <unistd.h>
#include <assert.h>
#include "jtag_atlantic.h"
#include "common.h"

static const char data_to_send[] = "Hello world\n";
static const int times_to_send = 20;
static char buf[16];

int main() {
    JTAGATLANTIC *atlantic = jtagatlantic_open(NULL, -1, -1, "echohello");
    if(!atlantic) {
        show_err();
        return 1;
    }
    show_info(atlantic);
    fprintf(stderr, "Unplug the cable or press ^C to stop.\n");
    for(int i = 0; i < times_to_send; i++) {
        int ret = jtagatlantic_write(atlantic, data_to_send, sizeof(data_to_send));
        assert(ret == sizeof(data_to_send));
    }
    jtagatlantic_flush(atlantic);
    while(1) {
        int ret = jtagatlantic_read(atlantic, buf, sizeof(buf));
        if(ret < 0)
            break;
        fwrite(buf, ret, 1, stdout);
        usleep(10000);
    }
    jtagatlantic_close(atlantic);
    return 0;
}
