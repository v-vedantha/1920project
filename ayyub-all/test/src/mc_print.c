#include "util.h"


volatile int done = 0;
int main(int argc, char *argv[]) {
	int core = getCoreId();

    if( core == 0 ) {
        putchar('0');
		while(done == 0);
		putchar('\n');
    } else if(core == 1) {
        putchar('1');
		done = 1;
		while(1);
    }

    return 0;
}

