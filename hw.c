/*
 * Trivial serial communication demo program
 */

#define csr_read(csr)						\
({								\
    register unsigned long __v;                                 \
    __asm__ __volatile__ ("csrr %0, " #csr : "=r" (__v));       \
    __v;							\
})

#define serial_data		(*(volatile unsigned char *)0x80000000)
#define serial_readsize		(*(volatile unsigned short *)0x80000002)
#define serial_writesize	(*(volatile unsigned short *)0x80000006)

static void serial_out_char(char ch)
{
    while (serial_writesize == 0)
        ;
    serial_data = ch;
}

static char serial_in_char(void)
{
    while (serial_readsize == 0)
        ;

    return serial_data;
}

static void serial_out_string(char *s)
{
    while (*s)
        serial_out_char(*s++);
}

static void serial_out_nibble(unsigned long v)
{
    serial_out_char(v < 10 ? v + '0' : v - 10 + 'a');
}

static void serial_out_hex(unsigned long v)
{
    for (int i = 0; i < 8; ++i)
        serial_out_nibble(v >> (28 - i*4) & 15);
}

int main(int c, char **v)
{
    for (;;) {
        serial_out_hex(csr_read(time));
        serial_out_string("\nHello World\nPress key: ");
        char ch = serial_in_char();
        serial_out_string("\nYou Pressed ");
        serial_out_char(ch);
    }
}
