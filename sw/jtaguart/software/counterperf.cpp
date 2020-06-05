#include <stdio.h>
#include <unistd.h>
#include <assert.h>
#include <time.h>
#include "jtag_atlantic.h"
#include "common.h"

static const unsigned int bytes_to_receive = 1<<20;
static unsigned char buf[8192];

static double time_diff(struct timespec &t_end, struct timespec &t_start) {
    double diff = t_end.tv_sec - t_start.tv_sec;
    diff += 1.e-9 * (t_end.tv_nsec - t_start.tv_nsec);
    return diff;
}

int main() {
    JTAGATLANTIC *atlantic = jtagatlantic_open(NULL, -1, -1, "counterperf");
    if(!atlantic) {
        show_err();
        return 1;
    }
    show_info(atlantic);
    
    struct timespec t_start, t_end;
    clock_gettime(CLOCK_MONOTONIC, &t_start);
    
    unsigned int bytes_received = 0;
    while(bytes_received < bytes_to_receive) {
        int ret = jtagatlantic_read(atlantic, (char*)buf, sizeof(buf));
        assert(ret >= 0);
        assert((unsigned int)ret <= sizeof(buf));
        if(ret == 0)
            usleep(100000);
        for(int i = 1; i < ret; i++)
            assert(buf[i] == ((buf[i-1] + 1) & 0xFF));
        bytes_received += ret;
    }
    
    clock_gettime(CLOCK_MONOTONIC, &t_end);
    
    double t_diff = time_diff(t_end, t_start);
    double datarate = 8. * bytes_received / t_diff;
    printf("time spent = %.3f s\n", t_diff);
    printf("received = %.3e bits\n", 8. * bytes_received);
    printf("data rate = %.3e bit/s\n", datarate);
    
    jtagatlantic_close(atlantic);
    return 0;
}
