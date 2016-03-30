/*
 * Trivial serial communication demo program
 */

#define csr_read(csr)                                           \
({                                                              \
    register unsigned long __v;                                 \
    __asm__ __volatile__ ("csrr %0, " #csr : "=r" (__v));       \
    __v;                                                        \
})

/* We follow Altera's JTAG UART interface:

  The core has two registers, data (addr 0) and control (addr 1):

   data    (R/W): RAVAIL:16        RVALID:1 RSERV:7          DATA:8
   control (R/W): WSPACE:16        RSERV:5 AC:1 WI:1 RI:1    RSERV:6 WE:1 RE:1
*/

#define serial_data     (*(volatile unsigned *)0x80000000)
#define serial_control  (*(volatile unsigned *)0x80000004)



static void serial_out_char(char ch)
{
    unsigned control;

    do
        control = serial_control;
    while (control < 0x10000);

    serial_data = ch;
}

static void serial_out_string(char *s)
{
    while (*s)
        serial_out_char(*s++);
}

static void serial_out_nibble(unsigned long v)
{
    serial_out_char(v < 10 ? v + '0' : v - 10 + 'A');
}

static void serial_out_hex(int len, unsigned long v)
{
    for (int i = 8 - len; i < 8; ++i)
        serial_out_nibble(v >> (28 - i*4) & 15);
}

static unsigned char serial_in_char(void)
{
    unsigned data;

    do
        data = serial_data;
    while (data < 0x10000);

    return data;
}

static void readline(char *buf, unsigned buf_size)
{
    char *p = buf;

    for (;;) {
        unsigned ch = serial_in_char();

        switch (ch) {
        case 127:
            if (p != buf) {
                --p;
                serial_out_string("\b \b");
            }
            break;

        case 10:
            *p = 0;
            serial_out_char('\n');
            return;

        default:
            if (' ' <= ch && ch < 127 && p != buf + buf_size) {
                *p++ = ch;
                serial_out_char(ch);
            }
            break;
        }
    }
}

int main()
{
    char c, e, f, *p, buf[99];
    int i = 0;
    volatile char *d;

    d = (char *) 0;  // Yes, write to address zero

    for (p = "Hello World\n"; *p; ++p, ++d)
        *d = *p;
    d[1] = 0;

    for (;;) {
        asm("");
        *d = ++i;
    }

    serial_out_string("\nOk\n");

    for (;;) {
        readline(buf, sizeof buf);
        serial_out_string("Got: ");
        serial_out_string(buf);
        serial_out_string("\n");
    }
}
