// Using the QEMU UART which isn't ideal as it has no backpressure

static void my_putchar(int ch)
{
    *(volatile char *)0x40002000 = ch;
}

static void my_puts(const char *s)
{
    for (; *s; ++s) {
        if (*s == 10)
            my_putchar(13);
        my_putchar(*s);
    }
}

int main(int c, char **v)
{
    for (;;) {
        my_puts("Hello RISC-V World!\n");
    }

    return 0;
}
