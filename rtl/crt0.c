extern int main() __attribute__((noreturn));

int _start(void)
{
    return main();
}
