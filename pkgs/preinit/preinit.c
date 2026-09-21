#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>

#include <asm/setup.h>		/* for COMMAND_LINE_SIZE */

#include "opts.h"

#define ERR(x) write(2, x, strlen(x))
#define AVER(c) do { if(c < 0) { ERR("failed: "  #c ": error=0x" ); pr_u32(errno); ERR("\n"); } } while(0)

char * pr_u32(int32_t input);

#define LOAD_ORDER "/lib/modules/load-order"
#define MODULE_PATH "/lib/modules/"

/* Load the modules the image was built with, in the order the build
 * computed for them (pkgs/liminix-tools/modules writes load-order with
 * dependencies first). This is what lets a fullSystem image carry
 * loadable modules at all: a kmodloader *service* cannot, because it
 * depends on kernel.modulesupport and the fullSystem rootdir is embedded
 * in that very kernel derivation - a cycle. preinit is built before the
 * kernel and embeds nothing, so it can carry the same module tree.
 *
 * Absent load-order means a kernel with no such modules, which is the
 * common case, so this prints nothing then. */
static void load_modules(void)
{
    int orders = open(LOAD_ORDER, O_RDONLY);
    if(orders<0) return;

    write(1, "loading modules\n", 16);
    char path[256];
    char name[192];
    int n = 0;
    char c;
    ssize_t got;

    while((got = read(orders, &c, 1)) > 0) {
	if(c != '\n') {
	    if(n < (int)sizeof(name) - 1) name[n++] = c;
	    continue;
	}
	name[n] = '\0';
	n = 0;
	if(name[0] == '\0') continue;

	if(strlen(name) + sizeof(MODULE_PATH) > sizeof(path)) {
	    ERR("module path too long: ");
	    ERR(name);
	    ERR("\n");
	    continue;
	}
	strcpy(path, MODULE_PATH);
	strcat(path, name);

	int fd = open(path, O_RDONLY);
	if(fd<0) {
	    ERR("failed: open(");
	    ERR(path);
	    ERR(")\n");
	    continue;
	}
	if(syscall(SYS_finit_module, fd, "", 0) < 0) {
	    ERR("failed: finit_module(");
	    ERR(path);
	    ERR("): error=0x");
	    pr_u32(errno);
	    ERR("\n");
	}
	close(fd);
    }
    close(orders);
}

static void die() {
    /* if init exits, it causes a kernel panic. On the Turris
     * Omnia (and maybe other hardware, I don't know), the kernel
     * panics _before_ any of the messages from AVER are printed,
     * which makes it really hard to tell what went wrong.  So
     * let's wait a little here to give the console a chance to
     * catch up.
     *
     * Yes, I know that file descriptor IO is supposedly
     * non-buffered. Empirical observation suggests that there
     * must be a buffer of some kind somewhere though.
     */

    sleep(10);
    exit(1);
}

static int fork_exec(char * command, char *args[])
{
    int fork_pid = fork();
    AVER(fork_pid);
    if(fork_pid > 0)
	return wait(NULL);
    else
	return execve(command, args, NULL);
}

char banner[]  = "Running pre-init...\n";
char buf[COMMAND_LINE_SIZE];

int main(int argc, char *argv[], char *envp[])
{
    struct root_opts opts = {
	.device = NULL,
	.fstype = NULL,
	.mount_opts = NULL
    };

    write(1, banner, strlen(banner));

    /* /proc is always needed (we read /proc/cmdline below). /dev is
     * NOT mounted here: s6-linux-init mounts a devtmpfs on /dev
     * itself when it takes over, and a second mount would fail with
     * EBUSY. Only the device (rootfs-mounting) branch needs it. */
    AVER(mount("none", "/proc", "proc", 0, NULL));

    int cmdline = open("/proc/cmdline", O_RDONLY, 0);

    if(cmdline>=0) {
	int len = read(cmdline, buf, sizeof buf - 1);
	buf[len]='\0';
	while(buf[len-1]=='\n') {
	    buf[len-1]='\0';
	    len--;
	}
	write(1, "cmdline: \"", 10);
	write(1, buf, len);
	write(1, "\"\n", 2);
    } else {
	ERR("failed: open(\"/proc/cmdline\")\n");
	die();
    }
    parseopts(buf, &opts);

    load_modules();

    if(opts.device) {
	if(!opts.fstype) opts.fstype = "jffs2"; /* backward compatibility */
	AVER(mount("none", "/dev", "devtmpfs", 0, NULL));
	write(1, "rootdevice ", 11);
	write(1, opts.device, strlen(opts.device));
	write(1, " (", 2);
	write(1, opts.fstype, strlen(opts.fstype));
	if(opts.mount_opts) {
	    write(1, ", opts=", 7);
	    write(1, opts.mount_opts, strlen(opts.mount_opts));
	}
	write(1, ")\n", 2);
	AVER(mount(opts.device, "/target/persist", opts.fstype, 0, opts.mount_opts));
	AVER(mount("/target/persist/nix", "/target/nix",
		   "bind", MS_BIND, NULL));

	char *exec_args[] = { "activate",  "/target", NULL };
	AVER(fork_exec("/target/persist/activate", exec_args));
	AVER(chdir("/target"));
	AVER(mount("/target", "/", "bind", MS_BIND | MS_REC, NULL));
	AVER(chroot("."));

	argv[0] = "init";
	argv[1] = NULL;
	AVER(execve("/persist/init", argv, envp));
    } else {
	/* No root device on the command line: the whole system is
	 * embedded in this initramfs (boot.initramfs.fullSystem).
	 * Populate the root filesystem with filesystem.contents via
	 * activate, then hand over to s6 init (installed at
	 * /init.s6 by the fullinitramfs builder). */
	write(1, "full-system initramfs: activating\n", 34);
	char *exec_args[] = { "activate",  "/", NULL };
	AVER(fork_exec("/activate", exec_args));
	argv[0] = "init";
	argv[1] = NULL;
	AVER(execve("/init.s6", argv, envp));
    }
    die();
}
