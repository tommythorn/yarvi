/*
 * Trivial serial communication demo program
 */

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

int main(int c, char **v)
{
    for (;;) {
        serial_out_string("\nHello World\nPress key: ");
        char ch = serial_in_char();
        serial_out_string("\nYou Pressed ");
        serial_out_char(ch);
    }
}
