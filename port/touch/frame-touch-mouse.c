#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t stopping;
static int mouse_fd = -1;
static const int hold_ms = 650;

struct gesture {
    bool down, moved, held, cancelled;
    int x, y, start_x, start_y, max_x, max_y;
    long long started;
};

static void fail(const char *what) { perror(what); exit(1); }
static void stop(int sig) { (void)sig; stopping = 1; }
static long long now_ms(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t)) fail("clock_gettime");
    return t.tv_sec * 1000LL + t.tv_nsec / 1000000;
}

static void emit(int type, int code, int value) {
    struct input_event e = { .type = type, .code = code, .value = value };
    if (write(mouse_fd, &e, sizeof(e)) != sizeof(e)) fail("write virtual mouse");
}
static void click(int button) {
    emit(EV_KEY, button, 1); emit(EV_SYN, SYN_REPORT, 0);
    emit(EV_KEY, button, 0); emit(EV_SYN, SYN_REPORT, 0);
}

static int update(struct gesture *g, bool touching, int fingers, int x, int y,
                  long long when) {
    int button = 0;
    if (touching && !g->down) {
        g->start_x = x; g->start_y = y; g->started = when;
        g->moved = g->held = g->cancelled = false;
    }
    if (touching) {
        double dx = (x - g->start_x) * 1920.0 / g->max_x;
        double dy = (y - g->start_y) * 1080.0 / g->max_y;
        if (dx * dx + dy * dy > 18 * 18) g->moved = true;
        if (fingers > 1) g->cancelled = true;
        g->x = x; g->y = y;
        if (!g->moved && !g->held && !g->cancelled && when - g->started >= hold_ms) {
            button = BTN_RIGHT; g->held = true;
        }
    } else if (g->down && !g->moved && !g->held && !g->cancelled) {
        button = BTN_LEFT;
    }
    g->down = touching;
    return button;
}

#ifndef FRAME_TOUCH_TEST
int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: frame-touch-mouse /dev/input/eventN\n"); return 2; }
    int fd = open(argv[1], O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) fail("open touchscreen");
    char name[256] = {0};
    if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) < 0) fail("device name");
    if (strcmp(name, "silead_ts")) { fprintf(stderr, "Refusing non-Silead device: %s\n", name); return 1; }
    struct input_absinfo ax, ay;
    if (ioctl(fd, EVIOCGABS(ABS_X), &ax) || ioctl(fd, EVIOCGABS(ABS_Y), &ay)) fail("touch axes");
    if (ax.minimum != 0 || ay.minimum != 0 || ax.maximum < 1 || ay.maximum < 1) {
        fprintf(stderr, "Unsupported touch range\n"); return 1;
    }
    mouse_fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK | O_CLOEXEC);
    if (mouse_fd < 0) fail("open uinput");
    if (ioctl(mouse_fd, UI_SET_EVBIT, EV_KEY) || ioctl(mouse_fd, UI_SET_KEYBIT, BTN_LEFT)
        || ioctl(mouse_fd, UI_SET_KEYBIT, BTN_RIGHT) || ioctl(mouse_fd, UI_SET_EVBIT, EV_ABS)
        || ioctl(mouse_fd, UI_SET_ABSBIT, ABS_X) || ioctl(mouse_fd, UI_SET_ABSBIT, ABS_Y)
        || ioctl(mouse_fd, UI_SET_PROPBIT, INPUT_PROP_POINTER)) fail("virtual mouse capabilities");
    struct uinput_abs_setup abs = { .code = ABS_X, .absinfo = ax };
    abs.absinfo.resolution = 10;
    if (ioctl(mouse_fd, UI_ABS_SETUP, &abs)) fail("virtual X axis");
    abs.code = ABS_Y; abs.absinfo = ay; abs.absinfo.resolution = 10;
    if (ioctl(mouse_fd, UI_ABS_SETUP, &abs)) fail("virtual Y axis");
    struct uinput_setup setup = { .id = { .bustype = BUS_VIRTUAL, .vendor = 0x157, .product = 1 } };
    strcpy(setup.name, "FRAME157 touch mouse");
    if (ioctl(mouse_fd, UI_DEV_SETUP, &setup) || ioctl(mouse_fd, UI_DEV_CREATE)) fail("create mouse");
    signal(SIGINT, stop); signal(SIGTERM, stop);
    /* Do not deliver the user's first tap before the compositor has discovered the mouse. */
    usleep(500000);
    if (ioctl(fd, EVIOCGRAB, 1)) fail("grab touchscreen");
    fprintf(stderr, "Mouse touch active: tap=left, hold=right, slide=hover; stop restores native touch\n");
    struct gesture g = { .max_x = ax.maximum, .max_y = ay.maximum };
    bool touching = false;
    int x = 0, y = 0, slot = 0, slots[10] = {0};
    while (!stopping) {
        struct pollfd p = { .fd = fd, .events = POLLIN };
        int wait = g.down && !g.moved && !g.held && !g.cancelled
            ? (int)(hold_ms - (now_ms() - g.started)) : -1;
        if (wait < 0 && g.down && !g.moved && !g.held && !g.cancelled) wait = 0;
        int ready = poll(&p, 1, wait);
        if (ready < 0) { if (errno == EINTR) continue; fail("poll touchscreen"); }
        if (p.revents & (POLLERR | POLLHUP | POLLNVAL)) break;
        if (!ready) {
            int button = update(&g, touching, 1, x, y, now_ms());
            if (button) click(button);
            continue;
        }
        struct input_event e;
        while (read(fd, &e, sizeof(e)) == sizeof(e)) {
            if (e.type == EV_SYN && e.code == SYN_DROPPED) {
                fprintf(stderr, "Touch events dropped; restoring native input\n"); stopping = 1; break;
            }
            if (e.type == EV_KEY && e.code == BTN_TOUCH) touching = e.value;
            if (e.type == EV_ABS) {
                if (e.code == ABS_X) x = e.value;
                if (e.code == ABS_Y) y = e.value;
                if (e.code == ABS_MT_SLOT) slot = e.value;
                if (e.code == ABS_MT_TRACKING_ID && slot >= 0 && slot < 10) slots[slot] = e.value >= 0;
            }
            if (e.type == EV_SYN && e.code == SYN_REPORT) {
                int fingers = 0;
                for (int i = 0; i < 10; i++) fingers += slots[i];
                int button = update(&g, touching, fingers, x, y, now_ms());
                if (touching) {
                    emit(EV_ABS, ABS_X, x); emit(EV_ABS, ABS_Y, y); emit(EV_SYN, SYN_REPORT, 0);
                }
                if (button) click(button);
            }
        }
    }
    ioctl(fd, EVIOCGRAB, 0);
    ioctl(mouse_fd, UI_DEV_DESTROY);
    close(mouse_fd); close(fd);
    return 0;
}
#endif
