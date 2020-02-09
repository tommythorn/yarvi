int main()
{
    char *d = (char *)0x8000FF00;
    char *s = "Hello World!";

    while (*s)
        *d++ = *s++;

    for (;;) {
        volatile int c = 0;
        *(volatile int *)0x8000FFF0 += 1;
        *(volatile int *)0x8000FFF4 = c++;
    }
}
