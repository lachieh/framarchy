#define FRAME_TOUCH_TEST
#include "frame-touch-mouse.c"
#include <assert.h>
int main(void) {
 struct gesture g={.max_x=1920,.max_y=1080};
 assert(update(&g,1,1,500,300,0)==0);
 assert(update(&g,0,0,500,300,100)==BTN_LEFT);
 assert(update(&g,1,1,500,300,200)==0);
 assert(update(&g,1,1,501,301,850)==BTN_RIGHT);
 assert(update(&g,1,1,501,301,900)==0);
 assert(update(&g,0,0,501,301,950)==0);
 assert(update(&g,1,1,500,300,1000)==0);
 assert(update(&g,1,1,550,300,1050)==0);
 assert(update(&g,1,1,500,300,1700)==0);
 assert(update(&g,0,0,500,300,1750)==0);
 assert(update(&g,1,1,500,300,2000)==0);
 assert(update(&g,1,2,500,300,2100)==0);
 assert(update(&g,1,1,500,300,2700)==0);
 assert(update(&g,0,0,500,300,2800)==0);
 puts("PASS: tap, hold, no duplicate click, slide and return, multi-touch cancellation");
}
