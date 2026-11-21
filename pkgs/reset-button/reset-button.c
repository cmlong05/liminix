// reset-button: reboot when the reset key is held down.
//
// The JDCloud RE-CS-02 reset key is GPIO 56 on the pinctrl (TLMM) chip,
// active-low: the line reads 0 while the key is pressed. The program
// polls the line and, once it has been low for hold-seconds without a
// break, syncs the filesystems and reboots immediately (reboot(2),
// the same as `reboot -f`).
//
// Usage: reset-button [gpio] [hold-seconds]
// Defaults: gpio 56, hold 5 seconds.

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/gpio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/ioctl.h>
#include <sys/reboot.h>
#include <time.h>
#include <unistd.h>

static int open_chip(void)
{
	int fallback = -1;
	for (int i = 0; i < 8; i++) {
		char path[32];
		snprintf(path, sizeof path, "/dev/gpiochip%d", i);
		int fd = open(path, O_RDONLY);
		if (fd < 0)
			continue;
		if (fallback < 0)
			fallback = fd;
		struct gpiochip_info info;
		if (ioctl(fd, GPIO_GET_CHIPINFO_IOCTL, &info) == 0 &&
		    (strcasestr(info.label, "pinctrl") ||
		     strcasestr(info.label, "tlmm"))) {
			printf("reset-button: using %s (label \"%s\")\n", path,
			       info.label);
			fflush(stdout);
			if (fd != fallback)
				close(fallback);
			return fd;
		}
		if (fd != fallback)
			close(fd);
	}
	return fallback;
}

static int request_line(int chip_fd, unsigned int offset)
{
	struct gpio_v2_line_request req;
	memset(&req, 0, sizeof req);
	req.offsets[0] = offset;
	req.num_lines = 1;
	req.config.flags =
	    GPIO_V2_LINE_FLAG_INPUT | GPIO_V2_LINE_FLAG_BIAS_PULL_UP;
	snprintf(req.consumer, sizeof req.consumer, "reset-button");
	if (ioctl(chip_fd, GPIO_V2_GET_LINE_IOCTL, &req) < 0)
		return -1;
	return req.fd;
}

static int read_line(int line_fd)
{
	struct gpio_v2_line_values vals;
	memset(&vals, 0, sizeof vals);
	vals.mask = 1;
	if (ioctl(line_fd, GPIO_V2_LINE_GET_VALUES_IOCTL, &vals) < 0)
		return -1;
	return (vals.bits & 1) ? 1 : 0;
}

static long long now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int main(int argc, char **argv)
{
	unsigned int gpio = 56;
	int hold_seconds = 5;
	if (argc > 1)
		gpio = (unsigned int)strtoul(argv[1], NULL, 0);
	if (argc > 2)
		hold_seconds = atoi(argv[2]);

	for (;;) {
		int chip = open_chip();
		if (chip < 0) {
			fprintf(stderr, "reset-button: no gpiochip found, retrying\n");
			sleep(5);
			continue;
		}
		int line = request_line(chip, gpio);
		if (line < 0) {
			fprintf(stderr, "reset-button: cannot request GPIO %u: %s\n",
				gpio, strerror(errno));
			close(chip);
			sleep(5);
			continue;
		}
		printf("reset-button: watching GPIO %u, hold %d seconds to reboot\n",
		       gpio, hold_seconds);
		fflush(stdout);

		long long pressed_since = 0;
		for (;;) {
			int v = read_line(line);
			if (v < 0) {
				fprintf(stderr, "reset-button: read failed: %s\n",
					strerror(errno));
				break;
			}
			long long now = now_ms();
			if (v == 0) {
				if (!pressed_since)
					pressed_since = now;
				else if (now - pressed_since >=
					 (long long)hold_seconds * 1000) {
					printf("reset-button: held %d seconds, rebooting\n",
					       hold_seconds);
					fflush(stdout);
					sync();
					reboot(RB_AUTOBOOT);
					_exit(1);
				}
			} else {
				pressed_since = 0;
			}
			usleep(100 * 1000);
		}
		close(line);
		close(chip);
		sleep(1);
	}
	return 0;
}
