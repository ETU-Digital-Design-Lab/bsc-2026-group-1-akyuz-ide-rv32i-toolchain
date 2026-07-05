// main.c — Snake & Mayin Tarlasi (Minesweeper) + Menu System on VGA Terminal
#define LED_REG    (*(volatile unsigned int *)0x00020008)
#define SWITCH_REG (*(volatile unsigned int *)0x0002000C)
#define CYCLE_REG  (*(volatile unsigned int *)0x00020010)
#define BUTTON_REG (*(volatile unsigned int *)0x00020014)
#define CAM_REG    (*(volatile unsigned int *)0x00020018)
#define VGA_DATA   (*(volatile unsigned int *)0x00030000)
#define VGA_CURSOR (*(volatile unsigned int *)0x00030004)
#define VGA_CTRL   (*(volatile unsigned int *)0x00030008)

#define BTN_L (1 << 0)
#define BTN_R (1 << 1)
#define BTN_D (1 << 2)
#define BTN_U (1 << 3)
#define BTN_C (1 << 4)

// SW[14] held during countdown opens settings
#define SW_SETTINGS (1 << 14)

static unsigned int sw_delay_poll(int loops) {
    unsigned int captured = 0;
    volatile int c = loops;
    while (c > 0) { captured |= BUTTON_REG; c--; }
    return captured;
}

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
    VGA_CTRL = 1;
    sw_delay_poll(300000);
}

void draw_border() {
    for (int x = 0; x < 40; x++) {
        vga_cursor(0,  x); vga_putc('#', 7, 0);
        vga_cursor(23, x); vga_putc('#', 7, 0);
    }
    for (int y = 0; y < 24; y++) {
        vga_cursor(y, 0);  vga_putc('#', 7, 0);
        vga_cursor(y, 39); vga_putc('#', 7, 0);
    }
}

void draw_text(const char *text, int r, int c, int fg) {
    while (*text) { vga_cursor(r, c++); vga_putc(*text++, fg, 0); }
}

void show_display_info() {
    vga_cursor(0,65); vga_putc('6',0x7,0); vga_cursor(0,66); vga_putc('4',0x7,0);
    vga_cursor(0,67); vga_putc('0',0x7,0); vga_cursor(0,68); vga_putc('x',0x7,0);
    vga_cursor(0,69); vga_putc('4',0x7,0); vga_cursor(0,70); vga_putc('8',0x7,0);
    vga_cursor(0,71); vga_putc('0',0x7,0); vga_cursor(0,72); vga_putc(' ',0x7,0);
    vga_cursor(0,73); vga_putc('6',0x7,0); vga_cursor(0,74); vga_putc('0',0x7,0);
    vga_cursor(0,75); vga_putc('H',0x7,0); vga_cursor(0,76); vga_putc('z',0x7,0);
}

// ============ ORTAK YARDIMCILAR ============

// Sagdan hizali sayi yaz (libgcc bolme ile)
void put_num(int r, int c, unsigned int val, int digits, int fg) {
    for (int i = digits - 1; i >= 0; i--) {
        vga_cursor(r, c + i);
        vga_putc('0' + (val % 10), fg, 0);
        val /= 10;
    }
}

// ============ SNAKE AYARLARI ============

int speed_lvl = 5;   // 1..9 (init'li global; crt0 .data kopyalar)
int g_delay   = 600000;

// Snake hiz ayar ekrani. CENTER ile baslar.
void snake_settings(void) {
    int prev_lvl = -1;
    clear_screen();
    draw_border();
    draw_text("SNAKE AYAR",    3, 14, 0xF);
    draw_text("U/D: hiz",     11, 13, 0x7);
    draw_text("C : basla",    13, 13, 0x7);
    while (1) {
        if (speed_lvl != prev_lvl) {
            draw_text("Hiz: ", 8, 14, 0xE);
            vga_cursor(8, 19); vga_putc('0' + speed_lvl, 0xA, 0);
            prev_lvl = speed_lvl;
        }
        unsigned int b = sw_delay_poll(500000);
        if ((b & BTN_U) && speed_lvl < 9) { speed_lvl++; sw_delay_poll(400000); }
        if ((b & BTN_D) && speed_lvl > 1) { speed_lvl--; sw_delay_poll(400000); }
        if (b & BTN_C) { sw_delay_poll(400000); g_delay = 1400000 - (speed_lvl << 17); return; }
    }
}

// Geriye uyumluluk: do_countdown icinde SW14 ile cagrilir
void show_settings(void) { snake_settings(); }

// ============ SNAKE GAME ============

static unsigned int lfsr = 1u;

unsigned int rng(void) {
    unsigned int bit = ((lfsr>>0)^(lfsr>>2)^(lfsr>>3)^(lfsr>>5)) & 1;
    lfsr = (lfsr >> 1) | (bit << 15);
    return lfsr;
}

#define MAX_LEN 100
int snake_x[MAX_LEN], snake_y[MAX_LEN];
int snake_len, dir, food_x, food_y, score, game_over;

void spawn_food(void) {
    unsigned int r = rng();
    food_x = 2 + (r & 0x1F) % 36;
    food_y = 2 + ((r >> 6) & 0x0F) % 18;
}

void show_score(int s) {
    vga_cursor(23, 9);
    int t = 0, temp = s;
    while (temp >= 10) { temp -= 10; t++; }
    vga_putc('0' + t, 0xF, 0);
    vga_putc('0' + temp, 0xF, 0);
}

void redraw_game_screen(void) {
    clear_screen();
    for (int x = 0; x < 40; x++) {
        vga_cursor(0, x);  vga_putc('#', 7, 0);
        vga_cursor(21, x); vga_putc('#', 7, 0);
    }
    for (int y = 0; y < 22; y++) {
        vga_cursor(y, 0);  vga_putc('#', 7, 0);
        vga_cursor(y, 39); vga_putc('#', 7, 0);
    }
    // Redraw snake
    for (int i = 0; i < snake_len; i++) {
        vga_cursor(snake_y[i], snake_x[i]);
        vga_putc('@', 0xA, 0);
    }
    // Redraw food & score
    vga_cursor(food_y, food_x); vga_putc('*', 0xC, 0);
    vga_cursor(23,2); vga_putc('S',0xF,0); vga_putc('C',0xF,0); vga_putc('O',0xF,0);
    vga_putc('R',0xF,0); vga_putc('E',0xF,0);
    show_score(score);
}

// Countdown before resuming. SW[14] held -> open settings mid-game.
void do_countdown(void) {
    for (int i = 3; i >= 1; i--) {
        vga_cursor(11, 19); vga_putc('0' + i, 0xF, 0);
        // Shorter countdown for smoother resume experience
        sw_delay_poll(3000000);
        if (SWITCH_REG & SW_SETTINGS) {
            show_settings();
            g_delay = 1400000 - (speed_lvl << 17);
            redraw_game_screen();
        }
    }
    vga_cursor(11, 19); vga_putc(' ', 0, 0);
}

// Returns 0 = replay, 1 = go to main menu
int game_over_screen(void) {
    draw_text("GAME OVER", 9, 14, 0xC);
    int sel = 0, prev = -1;
    while (1) {
        if (sel != prev) {
            draw_text("1.REPLAY", 12, 14, sel == 0 ? 0xA : 0x7);
            draw_text("2.MENU",   14, 14, sel == 1 ? 0xA : 0x7);
            prev = sel;
        }
        unsigned int b = sw_delay_poll(500000);
        if (b & BTN_U) sel = 0;
        if (b & BTN_D) sel = 1;
        if (b & BTN_C) { sw_delay_poll(300000); return sel; }
    }
}

void init_game(void) {
    // Seed RNG from cycle counter for randomness each game
    lfsr = CYCLE_REG ^ 0xACE1u;
    if (!lfsr) lfsr = 0xDEAD;

    clear_screen();
    snake_len = 5; dir = 1; score = 0; game_over = 0;
    for (int i = 0; i < snake_len; i++) { snake_x[i] = 15-i; snake_y[i] = 10; }
    spawn_food();
    for (int x = 0; x < 40; x++) {
        vga_cursor(0, x);  vga_putc('#', 7, 0);
        vga_cursor(21, x); vga_putc('#', 7, 0);
    }
    for (int y = 0; y < 22; y++) {
        vga_cursor(y, 0);  vga_putc('#', 7, 0);
        vga_cursor(y, 39); vga_putc('#', 7, 0);
    }
    vga_cursor(23,2); vga_putc('S',0xF,0); vga_putc('C',0xF,0); vga_putc('O',0xF,0);
    vga_putc('R',0xF,0); vga_putc('E',0xF,0);
    show_score(0);
    // Kontrol bilgisi
    draw_text("YON=git  C=DURAKLAT", 22, 2, 0x6);
}

// Returns 0=replay, 1=main menu
int play_snake() {
    init_game();
    int paused = 0;
    int pause_sel = 0; // 0: Continue, 1: Exit to menu

    while (1) {
        if (game_over) return game_over_screen();

        // Enter pause menu
        if (BUTTON_REG & BTN_C) {
            paused = 1;
            pause_sel = 0;
            while (BUTTON_REG & BTN_C) sw_delay_poll(50000);
        }

        if (paused) {
            // Pause menu (replaces old "PAUSED <speed>" text)
            draw_text("PAUSED",    22, 28, 0xF);
            draw_text("1.CONTINUE", 9, 12, pause_sel == 0 ? 0xA : 0x7);
            draw_text("2.EXIT",    11, 12, pause_sel == 1 ? 0xA : 0x7);

            unsigned int b = sw_delay_poll(400000);
            if ((b & BTN_U) && pause_sel > 0) { pause_sel--; sw_delay_poll(250000); }
            if ((b & BTN_D) && pause_sel < 1) { pause_sel++; sw_delay_poll(250000); }

            if (b & BTN_C) {
                sw_delay_poll(250000);
                if (pause_sel == 0) {
                    // Clear pause texts, then continue with short countdown
                    draw_text("       ",    22, 28, 0x0);
                    draw_text("          ", 9, 12, 0x0);
                    draw_text("      ",    11, 12, 0x0);
                    do_countdown();
                    paused = 0;
                } else {
                    // Exit game to main menu without reset
                    return 1;
                }
            }
            continue;
        }

        // Keep pause area clean during normal gameplay
        draw_text("       ", 22, 28, 0x0);

        unsigned int btns = sw_delay_poll(g_delay + 500000);

        int old_dir = dir;
        if      ((btns & BTN_U) && old_dir != 2) dir = 0;
        else if ((btns & BTN_R) && old_dir != 3) dir = 1;
        else if ((btns & BTN_D) && old_dir != 0) dir = 2;
        else if ((btns & BTN_L) && old_dir != 1) dir = 3;

        vga_cursor(snake_y[snake_len-1], snake_x[snake_len-1]); vga_putc(' ', 0, 0);
        for (int i = snake_len-1; i > 0; i--) {
            snake_x[i] = snake_x[i-1];
            snake_y[i] = snake_y[i-1];
        }
        if (dir==0) snake_y[0]--;
        if (dir==1) snake_x[0]++;
        if (dir==2) snake_y[0]++;
        if (dir==3) snake_x[0]--;

        if (snake_x[0]<=0 || snake_x[0]>=39 || snake_y[0]<=0 || snake_y[0]>=21)
            game_over = 1;
        for (int i = 1; i < snake_len; i++)
            if (snake_x[0]==snake_x[i] && snake_y[0]==snake_y[i]) game_over = 1;

        if (snake_x[0]==food_x && snake_y[0]==food_y) {
            score++;
            if (snake_len < MAX_LEN) snake_len++;
            spawn_food();
            show_score(score);
        }
        vga_cursor(food_y, food_x); vga_putc('*', 0xC, 0);
        vga_cursor(snake_y[0], snake_x[0]); vga_putc('@', 0xA, 0);
        LED_REG = score;
    }
}

// ============ MAYIN TARLASI (MINESWEEPER) ============
#define MS_MAX    16                 // en buyuk kenar
#define MS_CAP    (MS_MAX * MS_MAX)  // dizi kapasitesi
#define MS_R0     4                  // tahtanin ekran satir baslangici
#define MS_C0     4                  // tahtanin ekran sutun baslangici
#define SW_FLAG   (1 << 1)           // SW[1] ON = bayrak koy/kaldir
#define SW_EXIT   (1 << 2)           // SW[2] ON = menuye don

// Calisma anindaki tahta boyutu (ayar ekranindan secilir)
int ms_w = 9, ms_h = 9, ms_mines = 10, ms_size_idx = 0;

unsigned char ms_mine[MS_CAP];
unsigned char ms_open[MS_CAP];
unsigned char ms_flag[MS_CAP];
signed char   ms_adj[MS_CAP];
int ms_cx, ms_cy, ms_remaining, ms_flags;

// Rakam renkleri (siyah zemin uzerinde okunakli/parlak tonlar)
int ms_num_color(int n) {
    switch (n) {
        case 1:  return 0x9;  // acik mavi
        case 2:  return 0xA;  // acik yesil
        case 3:  return 0xC;  // acik kirmizi
        case 4:  return 0xD;  // mor
        case 5:  return 0xE;  // sari
        case 6:  return 0xB;  // camgobegi
        default: return 0xF;  // 7-8: beyaz
    }
}

// Tahta boyutu ayar ekrani (U/D ile sec, C ile basla)
void ms_settings(void) {
    static const int WS[3] = { 9, 12, 16 };
    static const int MN[3] = { 10, 20, 40 };
    int prev = -1;
    clear_screen();
    draw_border();
    draw_text("MAYIN AYAR", 3, 14, 0xF);
    draw_text("U/D: boyut", 13, 13, 0x7);
    draw_text("C  : basla", 15, 13, 0x7);
    while (1) {
        if (ms_size_idx != prev) {
            int w = WS[ms_size_idx];
            draw_text("Alan:", 8, 12, 0xE);
            put_num(8, 18, w, 2, 0xA);
            vga_cursor(8, 20); vga_putc('x', 0xA, 0);
            put_num(8, 21, w, 2, 0xA);
            draw_text("Mayin:", 10, 12, 0xE);
            put_num(10, 19, MN[ms_size_idx], 2, 0xC);
            prev = ms_size_idx;
        }
        unsigned int b = sw_delay_poll(500000);
        if ((b & BTN_U) && ms_size_idx < 2) { ms_size_idx++; sw_delay_poll(400000); }
        if ((b & BTN_D) && ms_size_idx > 0) { ms_size_idx--; sw_delay_poll(400000); }
        if (b & BTN_C) {
            sw_delay_poll(400000);
            ms_w = WS[ms_size_idx]; ms_h = WS[ms_size_idx]; ms_mines = MN[ms_size_idx];
            return;
        }
    }
}

void ms_wait_release(void) {
    while (BUTTON_REG & 0x1F) sw_delay_poll(20000);
}

void ms_reset(void) {
    int n = ms_w * ms_h;
    for (int i = 0; i < n; i++) {
        ms_mine[i] = 0; ms_open[i] = 0; ms_flag[i] = 0; ms_adj[i] = 0;
    }
    // Her oyunda farkli yerlere mayin (rng CYCLE_REG'den seed'li)
    int placed = 0;
    while (placed < ms_mines) {
        int p = rng() % n;
        if (!ms_mine[p]) { ms_mine[p] = 1; placed++; }
    }
    for (int y = 0; y < ms_h; y++) {
        for (int x = 0; x < ms_w; x++) {
            int i = y * ms_w + x;
            if (ms_mine[i]) continue;
            int c = 0;
            for (int dy = -1; dy <= 1; dy++) {
                for (int dx = -1; dx <= 1; dx++) {
                    int nx = x + dx, ny = y + dy;
                    if (nx < 0 || nx >= ms_w || ny < 0 || ny >= ms_h) continue;
                    if (ms_mine[ny * ms_w + nx]) c++;
                }
            }
            ms_adj[i] = c;
        }
    }
    ms_cx = 0; ms_cy = 0;
    ms_remaining = n - ms_mines;
    ms_flags = 0;
}

void ms_draw_cell(int x, int y) {
    int i = y * ms_w + x;
    char ch; int fg;
    int bg = (x == ms_cx && y == ms_cy) ? 0x4 : 0x0;  // imlec: kirmizi zemin
    if (ms_open[i]) {
        if (ms_mine[i])           { ch = 'X'; fg = 0xC; }
        else if (ms_adj[i] == 0)  { ch = ' '; fg = 0x7; }
        else                      { ch = '0' + ms_adj[i]; fg = ms_num_color(ms_adj[i]); }
    } else if (ms_flag[i])        { ch = 'P'; fg = 0xE; }   // P = bayrak
    else                          { ch = '.'; fg = 0x7; }
    vga_cursor(MS_R0 + y, MS_C0 + x * 2);
    vga_putc(ch, fg, bg);
}

void ms_draw_all(void) {
    for (int y = 0; y < ms_h; y++)
        for (int x = 0; x < ms_w; x++)
            ms_draw_cell(x, y);
}

// Ust bilgi: mayin sayisi, bayrak sayisi, kalan temiz alan (canli)
void ms_status(void) {
    draw_text("MAYIN:",  2, 1,  0xC); put_num(2, 7,  ms_mines,     2, 0xF);
    draw_text("BAYRAK:", 2, 11, 0xE); put_num(2, 18, ms_flags,     2, 0xF);
    draw_text("KALAN:",  2, 22, 0xA); put_num(2, 28, ms_remaining, 3, 0xF);
}

// Bos hucreleri acan iteratif flood-fill (hucre basina tek push)
void ms_reveal(int sx, int sy) {
    unsigned char st[MS_CAP];
    int sp = 0;
    int s0 = sy * ms_w + sx;
    if (ms_open[s0] || ms_flag[s0] || ms_mine[s0]) return;
    ms_open[s0] = 1; ms_remaining--; st[sp++] = s0;
    while (sp > 0) {
        int i = st[--sp];
        if (ms_adj[i] != 0) continue;
        int x = i % ms_w, y = i / ms_w;
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                int nx = x + dx, ny = y + dy;
                if (nx < 0 || nx >= ms_w || ny < 0 || ny >= ms_h) continue;
                int ni = ny * ms_w + nx;
                if (!ms_open[ni] && !ms_mine[ni] && !ms_flag[ni]) {
                    ms_open[ni] = 1; ms_remaining--; st[sp++] = ni;
                }
            }
        }
    }
}

// 0 = tekrar, 1 = ana menu
int ms_end_screen(int win) {
    draw_text(win ? "KAZANDIN!" : "PATLADIN! ", 22, 3, win ? 0xA : 0xC);
    int sel = 0, prev = -1;
    while (1) {
        if (sel != prev) {
            draw_text("1.TEKRAR", 22, 16, sel == 0 ? 0xA : 0x7);
            draw_text("2.MENU",   22, 27, sel == 1 ? 0xA : 0x7);
            prev = sel;
        }
        unsigned int b = sw_delay_poll(500000);
        if (b & (BTN_U | BTN_L)) sel = 0;
        if (b & (BTN_D | BTN_R)) sel = 1;
        if (b & BTN_C) { sw_delay_poll(300000); return sel; }
    }
}

void play_minesweeper(void) {
    ms_settings();                 // once alan boyutu sec
    do {
        lfsr = CYCLE_REG ^ 0x1234u;
        if (!lfsr) lfsr = 0xBEEF;

        clear_screen();
        draw_border();
        draw_text("MAYIN TARLASI", 1, 2, 0xF);
        draw_text("YON=gez  C=ac",       20, 2, 0x6);
        draw_text("SW1=bayrak SW2=cikis", 21, 2, 0x6);
        ms_reset();
        ms_status();
        ms_draw_all();

        int playing = 1, win = 0, quit = 0;
        while (playing) {
            if (SWITCH_REG & SW_EXIT) { quit = 1; break; }   // SW2 ile menuye

            unsigned int b = sw_delay_poll(300000);
            int ox = ms_cx, oy = ms_cy;
            if      ((b & BTN_U) && ms_cy > 0)        ms_cy--;
            else if ((b & BTN_D) && ms_cy < ms_h - 1) ms_cy++;
            else if ((b & BTN_L) && ms_cx > 0)        ms_cx--;
            else if ((b & BTN_R) && ms_cx < ms_w - 1) ms_cx++;
            if (ox != ms_cx || oy != ms_cy) {
                ms_draw_cell(ox, oy);
                ms_draw_cell(ms_cx, ms_cy);
                ms_wait_release();
            }

            if (b & BTN_C) {
                int i = ms_cy * ms_w + ms_cx;
                if (SWITCH_REG & SW_FLAG) {
                    if (!ms_open[i]) {
                        if (ms_flag[i]) { ms_flag[i] = 0; ms_flags--; }
                        else            { ms_flag[i] = 1; ms_flags++; }
                        ms_draw_cell(ms_cx, ms_cy);
                        ms_status();
                    }
                } else if (!ms_flag[i]) {
                    if (ms_mine[i]) {
                        int n = ms_w * ms_h;
                        for (int k = 0; k < n; k++) if (ms_mine[k]) ms_open[k] = 1;
                        ms_draw_all();
                        playing = 0; win = 0;
                    } else {
                        ms_reveal(ms_cx, ms_cy);
                        ms_draw_all();
                        ms_status();
                        if (ms_remaining == 0) { playing = 0; win = 1; }
                    }
                }
                ms_wait_release();
            }
            LED_REG = ms_remaining;
        }

        if (quit) return;                       // SW2 -> menuye
        if (ms_end_screen(win) == 1) return;    // secimle menuye
    } while (1);                                // tekrar oyna
}

// ============ MENU ============

void draw_menu(int selected) {
    int fg0 = (selected==0) ? 0xA : 0x7;
    int fg1 = (selected==1) ? 0xA : 0x7;
    int fg2 = (selected==2) ? 0xA : 0x7;
    draw_text(">", 8,  11, fg0); draw_text("1.SNAKE",          8,  13, fg0);
    draw_text(">", 11, 11, fg1); draw_text("2.MAYIN TARLASI", 11, 13, fg1);
    draw_text(">", 14, 11, fg2); draw_text("3.KAMERA",        14, 13, fg2);
}

// Kamera goruntusunu ac; herhangi bir butona basinca menuye don
void show_camera(void) {
    // Kamera bagli degilse goruntu gelmez; bilgi terminalde gorunur kalir
    draw_text("KAMERA - butona bas: don", 18, 8, 0xE);
    CAM_REG = 1;
    sw_delay_poll(400000);
    while (!(sw_delay_poll(400000) & 0x1F));
    CAM_REG = 0;
    sw_delay_poll(400000);
}

void draw_menu_static() {
    clear_screen();
    draw_border();
    draw_text("MAIN MENU",    3, 12, 0xF);
    draw_text("CENTER select",20, 12, 0xC);
    show_display_info();
}

// ============ MAIN ============

int main() {
    // Keep board LEDs off at boot (old 0xFFFF made LED2..LED12 look always-on)
    LED_REG = 0x0000;
    VGA_CTRL = 3;
    sw_delay_poll(2000000);
    clear_screen();

    int menu_selected = 0;
    int prev_selected = -1;

    draw_menu_static();
    draw_menu(menu_selected);

    while (1) {
        if (menu_selected != prev_selected) {
            draw_menu(menu_selected);
            prev_selected = menu_selected;
        }

        unsigned int b = sw_delay_poll(800000);

        if ((b & BTN_U) && menu_selected > 0) { menu_selected--; sw_delay_poll(500000); }
        if ((b & BTN_D) && menu_selected < 2) { menu_selected++; sw_delay_poll(500000); }

        if (b & BTN_C) {
            sw_delay_poll(500000);

            if (menu_selected == 0) {
                snake_settings();   // once hiz ayari
                // Snake: loop replay until user chooses "go to menu"
                int ret;
                do {
                    g_delay = 1400000 - (speed_lvl << 17);
                    ret = play_snake();
                } while (ret == 0);
            }
            else if (menu_selected == 1) play_minesweeper();
            else if (menu_selected == 2) show_camera();

            draw_menu_static();
            prev_selected = -1;
        }
    }

    return 0;
}
