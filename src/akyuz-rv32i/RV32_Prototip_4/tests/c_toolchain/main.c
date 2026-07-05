// main.c — Simple Camera & VGA Demo
#define LED_REG    (*(volatile unsigned int *)0x00020008)
#define SWITCH_REG (*(volatile unsigned int *)0x0002000C)
#define CYCLE_REG  (*(volatile unsigned int *)0x00020010)
#define BUTTON_REG (*(volatile unsigned int *)0x00020014)
#define VGA_DATA   (*(volatile unsigned int *)0x00030000)
#define VGA_CURSOR (*(volatile unsigned int *)0x00030004)
#define VGA_CTRL   (*(volatile unsigned int *)0x00030008)

void vga_cursor(int r, int c) {
    asm volatile("nop\nnop");
    VGA_CURSOR = (r << 8) | c;
    asm volatile("nop\nnop");
}

void vga_putc(char c, int fg, int bg) {
    asm volatile("nop\nnop");
    VGA_DATA = (bg << 12) | (fg << 8) | c;
    asm volatile("nop\nnop");
}

void clear_screen() {
    VGA_CTRL = 1; // hardware clear
    volatile int c = 300000;
    while(c > 0) c--;
}

void draw_text(const char *text, int r, int c, int fg) {
    while (*text) { vga_cursor(r, c++); vga_putc(*text++, fg, 0); }
}

int main() {
    LED_REG = 0xAAAA; // Initial LED pattern
    clear_screen();
    
    draw_text("RV32_Prototip_4: Camera & VGA", 2, 5, 0xF);
    draw_text("-----------------------------", 3, 5, 0x7);
    
    draw_text("System Status: OK", 5, 5, 0xA);
    draw_text("Camera stream: Active on SW[15]", 7, 5, 0xE);
    
    draw_text("Use SW[15] to toggle between this", 10, 5, 0x7);
    draw_text("text and the live camera image.", 11, 5, 0x7);
    
    while (1) {
        LED_REG = SWITCH_REG; // Reflect switches to LEDs
    }
    
    return 0;
}
