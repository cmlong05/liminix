#!/usr/bin/env bash

# this shell script is run on the build system to min-copy-closure the
# system configuration onto the device and reboot/restart services as
# requested

die() {
    echo "$@"
    exit 1
}


PATH=@min_copy_closure@/bin:$PATH
ssh_command=${SSH_COMMAND-ssh}

reboot="reboot"
case "$1" in
    "--no-reboot")
	unset reboot
	shift
	;;
    "--fast")
	reboot="soft"
	shift
	;;
esac

target_host=$1
shift

test -n "$target_host" || \
    die "Usage: $0 [--no-reboot] [--fast] target-host"

toplevel=$(realpath @toplevel@)
test -e $toplevel/etc/nix-store-paths || die "missing etc/nix-store-paths, is this really a system configuration?"
echo installing from systemConfiguration $toplevel to host $target_host

$ssh_command $target_host uname -a || die "Can't ssh to $target_host"
min-copy-closure $target_host $toplevel
ts=$(date +%Y%m%dT%H%M%S)
configuration=$(realpath --relative-to / $toplevel)
$ssh_command $target_host "$toplevel/bin/install && { test ! -d /persist || dest=/persist; ln -s $configuration \${dest:-/}/${ts}.configuration; }" \
    || die "Failed to install $toplevel on $target_host"
case "$reboot" in
    reboot)
	$ssh_command $target_host "sync; source /etc/profile; reboot"
	;;
    soft)
	$ssh_command $target_host $toplevel/bin/restart-services
	;;
    *)
	;;
esac
