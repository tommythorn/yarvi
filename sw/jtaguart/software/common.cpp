#include <stdio.h>
#include "jtag_atlantic.h"

void show_info(JTAGATLANTIC *atlantic) {
    char const *cable;
    int device, instance;
    jtagatlantic_get_info(atlantic, &cable, &device, &instance);
    fprintf(stderr, "Connected to cable '%s', device %d, instance %d\n", cable, device, instance);
}

static const char *err_msgs[] = {
    "No error",
    "Unable to connect to local JTAG server",
    "More than one cable available, provide more specific cable name",
    "Cable not available",
    "Selected cable is not plugged",
    "JTAG not connected to board, or board powered down",
    "Another program is already using the UART",
    "More than one UART available, specify device/instance",
    "No UART matching the specified device/instance",
    "Selected UART is not compatible with this version of the library"
};
void show_err() {
    char const *progname = NULL;
    int err = jtagatlantic_get_error(&progname);
    if(err >= -9 && err <= 0)
        fprintf(stderr, "%s\n", err_msgs[-err]);
    if(progname != NULL && progname[0])
        fprintf(stderr, "progname: '%s'\n", progname);
}
