#define BUTTON_REG (*(volatile unsigned int *)0x00020014)
#define UART_DATA  (*(volatile unsigned int *)0x00020000)
#define UART_STAT  (*(volatile unsigned int *)0x00020004)

void delay() {
    for (volatile int i = 0; i < 500000; i++);
}

void putc(char c) {
    while ((UART_STAT & 1) == 0);
    UART_DATA = c;
}

void print_hex(unsigned int val) {
    for (int i = 7; i >= 0; i--) {
        int nibble = (val >> (i * 4)) & 0xF;
        if (nibble < 10) putc('0' + nibble);
        else             putc('A' + nibble - 10);
    }
    putc('\r');
    putc('\n');
}

int main() {
    while (1) {
        unsigned int btns = BUTTON_REG;
        print_hex(btns);
        delay();
    }
    return 0;
}
