/* Copyright 2019 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Android Open Accessory (AOA) Switcher Utility
 *
 * This utility allows a Linux host to switch connected Android phones into AOA
 * mode (see https://source.android.com/devices/accessories/aoa for details).
 * It can optionally also register the AOA VID/PID with an existing kernel
 * driver (note that this only makes sense for kernel drivers that use only a
 * bulk-in and a bulk-out endpoint). When binding to a kernel driver, it will
 * automatically disable (deauthorize) the second interface (ADB debugging pipe)
 * on the AOA device (if present), since binding a kernel driver to that would
 * likely cause undesired effects.
 *
 * This program is intentionally not depending on libusb and instead accessing
 * the kernel's usbfs interface directly. libusb is a giant dependency that may
 * complicate deployment in embedded applications with limited space, and the
 * usbfs interface for control transfers is really simple to use anyway.
 */

#include <dirent.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <linux/usb/ch9.h>
#include <linux/usbdevice_fs.h>

#define SYSFS_USB_DEVICES	"/sys/bus/usb/devices"
#define SYSFS_USB_DRIVERS	"/sys/bus/usb/drivers"
#define USBFS_ROOT		"/dev/bus/usb"

#define AOA_GET_PROTOCOL	51
#define AOA_SET_STRING		52
#define AOA_START		53

#define AOA_STR_MANUFACTURER	0
#define AOA_STR_MODEL		1
#define AOA_STR_DESCRIPTION	2
#define AOA_STR_VERSION		3
#define AOA_STR_URI		4
#define AOA_STR_SERIAL		5

#define TIMEOUT_MS		5000
#define DELAY_MS		50

struct aoa_descriptors {
	const char *manufacturer;
	const char *model;
	const char *description;
	const char *version;
	const char *uri;
	const char *serial;
};

#define for_each_usbdev(_d) for (DIR *_dir = NULL; (_d = _feu_helper(&_dir)); )
static char *_feu_helper(DIR **dir)
{
	struct dirent *dirent;

	if (!*dir) {
		*dir = opendir(SYSFS_USB_DEVICES);
		if (!*dir)
			err(4, "Cannot open %s", SYSFS_USB_DEVICES);
	}

	errno = 0;
	while ((dirent = readdir(*dir))) {
		/* skip '.' and '..' */
		if (dirent->d_name[0] == '.')
			continue;
		/* only want devices, skip interfaces */
		if (strchr(dirent->d_name, ':'))
			continue;
		/* if we get this far we have one! */
		return dirent->d_name;
	}

	if (errno)
		err(5, "Couldn't read %s", SYSFS_USB_DEVICES);

	closedir(*dir);
	return NULL;
}

__attribute__((__format__(__scanf__, 3, 4)))
static int sysfs_scanf(const char *devpath, const char *node,
		       const char *format, ...)
{
	char path[128];
	char buffer[1024];

	if (snprintf(path, sizeof(path), "%s/%s/%s",
		     SYSFS_USB_DEVICES, devpath, node) < 0)
		err(13, "impossible!");

	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;

	ssize_t size = read(fd, &buffer, sizeof(buffer));
	if (size >= sizeof(buffer) - 1)
		errx(6, "sysfs file %s too big", path);
	buffer[size] = 0;

	va_list args;
	va_start(args, format);
	int ret = vsscanf(buffer, format, args);
	va_end(args);

	return ret;
}

static int write_file(const char *path, const char *value)
{
	int ret = -1;
	int fd = open(path, O_WRONLY | O_CLOEXEC);
	if (fd < 0)
		return ret;

	size_t len = strlen(value) + 1;
	if (write(fd, value, len) != len)
		goto out;

	ret = 0;
out:
	close(fd);
	return ret;
}

static char *find_dev_by_vid_pid(const char *vidpid)
{
	uint16_t vid, pid;
	if (sscanf(vidpid, "%hx:%hx", &vid, &pid) != 2) {
		warnx("Not a VID:PID in '0123:abcd' format: %s", vidpid);
		return NULL;
	}

	char *devpath;
	for_each_usbdev(devpath) {
		uint16_t fvid, fpid;
		if (sysfs_scanf(devpath, "idVendor", "%hx\n", &fvid) != 1 ||
		    sysfs_scanf(devpath, "idProduct", "%hx\n", &fpid) != 1) {
			warnx("Cannot parse VID/PID for %s", devpath);
			continue;
		}

		if (fvid == vid || fpid == pid)
			return strdup(devpath);
	}

	return NULL;
}

static int aoa_get_protocol(int fd)
{
	uint16_t aoa_protocol = 0;
	struct usbdevfs_ctrltransfer xfer = {
		.bRequestType = USB_DIR_IN | USB_TYPE_VENDOR | USB_RECIP_DEVICE,
		.bRequest = AOA_GET_PROTOCOL,
		.wValue = 0,
		.wIndex = 0,
		.wLength = sizeof(aoa_protocol),
		.timeout = TIMEOUT_MS,
		.data = &aoa_protocol,
	};

	if (ioctl(fd, USBDEVFS_CONTROL, &xfer) == sizeof(aoa_protocol))
		return aoa_protocol;

	/* EPROTO == not an AOA device */
	if (errno != EPROTO)
		warn("USB error during GET_PROTOCOL");

	return -1;
}

static int aoa_set_string(int fd, int type, const char *value)
{
	if (!value)
		return 0;

	size_t len = strlen(value) + 1;
	if (len >= 1 << (sizeof(uint16_t) * 8))
		errx(7, "AOA descriptor too long: %s", value);

	struct usbdevfs_ctrltransfer xfer = {
		.bRequestType = USB_DIR_OUT | USB_TYPE_VENDOR |
				USB_RECIP_DEVICE,
		.bRequest = AOA_SET_STRING,
		.wValue = 0,
		.wIndex = type,
		.wLength = len,
		.timeout = TIMEOUT_MS,
		.data = (void *)value,
	};

	if (ioctl(fd, USBDEVFS_CONTROL, &xfer) == len)
		return 0;

	warn("USB error during SET_STRING(%d) = '%s'", type, value);
	return -1;
}

static int aoa_start(int fd)
{
	struct usbdevfs_ctrltransfer xfer = {
		.bRequestType = USB_DIR_OUT | USB_TYPE_VENDOR |
				USB_RECIP_DEVICE,
		.bRequest = AOA_START,
		.wValue = 0,
		.wIndex = 0,
		.wLength = 0,
		.timeout = TIMEOUT_MS,
		.data = NULL,
	};

	if (ioctl(fd, USBDEVFS_CONTROL, &xfer) == 0)
		return 0;

	warn("USB error during START");
	return -1;
}

static int try_switch_aoa(const char *devpath, struct aoa_descriptors *desc)
{
	uint8_t busnum, devnum;
	if (sysfs_scanf(devpath, "busnum", "%hhu\n", &busnum) != 1 ||
	    sysfs_scanf(devpath, "devnum", "%hhu\n", &devnum) != 1) {
		warnx("Cannot parse busnum/devnum for %s", devpath);
		return -1;
	}

	char path[128];
	if (snprintf(path, sizeof(path), "%s/%03u/%03u",
		     USBFS_ROOT, busnum, devnum) < 0)
		err(8, "impossible!");

	int fd = open(path, O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		warn("Cannot open %s", path);
		return -1;
	}

	if (aoa_get_protocol(fd) <= 0)
		goto fail;

	if (aoa_set_string(fd, AOA_STR_MANUFACTURER, desc->manufacturer) < 0 ||
	    aoa_set_string(fd, AOA_STR_MODEL, desc->model) < 0 ||
	    aoa_set_string(fd, AOA_STR_DESCRIPTION, desc->description) < 0 ||
	    aoa_set_string(fd, AOA_STR_VERSION, desc->version) < 0 ||
	    aoa_set_string(fd, AOA_STR_URI, desc->uri) < 0 ||
	    aoa_set_string(fd, AOA_STR_SERIAL, desc->serial) < 0)
		goto fail;

	if (aoa_start(fd) < 0)
		goto fail;

	puts(devpath);
	close(fd);
	return 0;

fail:
	close(fd);
	return -1;
}

static int disable_adb_if(const char *devpath)
{
	/*
	 * Right after try_switch_aoa(), the device drops off the bus and has to
	 * reenumerate with the well-known AOA VID/PID. Give it some time.
	 */
	uint16_t pid = 0;
	for (int tries = TIMEOUT_MS / DELAY_MS; tries > 0; tries--) {
		if (sysfs_scanf(devpath, "idProduct", "%hx\n", &pid) == 1) {
			/* 2d00 means there's no ADB interface. */
			if (pid == 0x2d00)
				return 0;
			if (pid == 0x2d01)
				break;
		}
		usleep(DELAY_MS * 1000);
	}

	if (pid != 0x2d01) {
		warnx("%s didn't come back up after AOA switch!\n", devpath);
		return -1;
	}

	char path[128];
	if (snprintf(path, sizeof(path), "%s/%s:1.1/authorized",
		     SYSFS_USB_DEVICES, devpath) < 0)
		err(9, "impossible!");

	/* Wait again since this file is created a tiny bit later. */
	for (int tries = TIMEOUT_MS / DELAY_MS; tries > 0; tries--) {
		if (access(path, F_OK) == 0) {
			if (write_file(path, "0\n") < 0)
				err(10, "Cannot write %s", path);
			return 0;
		}
		usleep(DELAY_MS * 1000);
	}

	errx(14, "%s is ADB-enabled, but cannot find %s", devpath, path);
}

static void register_with_driver(const char *driver)
{
	char path[128];
	if (snprintf(path, sizeof(path), "%s/%s/new_id",
		     SYSFS_USB_DRIVERS, driver) < 0)
		err(11, "impossible!");

	/*
	 * Unless we have multiple AOA devices attached we'll only need one of
	 * these, but it's easier to add both than to figure out the right one.
	 */
	if (write_file(path, "18d1 2d00\n") < 0 ||
	    write_file(path, "18d1 2d01\n") < 0)
		err(12, "Cannot write %s", path);
}

static const struct option long_options[] = {
	{"all", 0, NULL, 'a'},
	{"bind", 1, NULL, 'b'},
	{"description", 1, NULL, 'D'},
	{"driver", 1, NULL, 'd'},
	{"help", 0, NULL, 'h'},
	{"manufacturer", 1, NULL, 'F'},
	{"model", 1, NULL, 'M'},
	{"serial", 1, NULL, 'S'},
	{"uri", 1, NULL, 'U'},
	{"version", 1, NULL, 'V'},
	{NULL, 0, NULL, 0},
};

static void usage(void)
{
	errx(1,	"usage: aoa_switch -a [-D|F|M|S|U|V value]\n"
		"       aoa_switch -b <vid:pid> [-D|F|M|S|U|V <value>]\n"
		"\n"
		"Need to supply exactly one mode-defining option:\n"
		"       -a | --all                  Try to switch all attached devices into AOA mode\n"
		"       -b | --bind <VID:PID>       Try to switch one device with specified VID/PID (in 0123:abcd format) into AOA mode\n"
		"\n"
		"Can supply any number of descriptor options (undefined descriptors are not transmitted):\n"
		"       -F | --manufacturer <value> Set AOA manufacturer tag\n"
		"       -M | --model <value>        Set AOA model tag\n"
		"       -D | --description <value>  Set AOA description tag\n"
		"       -V | --version <value>      Set AOA version tag\n"
		"       -U | --uri <value>          Set AOA URI tag\n"
		"       -S | --serial <value>       Set AOA serial tag\n"
		"\n"
		"Additional options:\n"
		"       -d | --driver <driver name> Register AOA VID/PID with kernel driver after switching\n"
		"\n"
		"Will output a list of devices (one per line, in sysfs device path notation) that were switched to AOA mode, if any.\n");
}

int main(int argc, char *argv[])
{
	int opt, optidx;
	bool do_all = 0;
	const char *bind = NULL;
	const char *driver = NULL;
	struct aoa_descriptors desc = {};

	while ((opt = getopt_long(argc, argv, "ab:D:d:hF:M:S:U:V:?",
				  long_options, &optidx)) != -1) {
		switch (opt) {
		case 'a':
			do_all = true;
			break;
		case 'b':
			bind = optarg;
			break;
		case 'D':
			desc.description = optarg;
			break;
		case 'd':
			driver = optarg;
			break;
		case 'F':
			desc.manufacturer = optarg;
			break;
		case 'M':
			desc.model = optarg;
			break;
		case 'S':
			desc.serial = optarg;
			break;
		case 'U':
			desc.uri = optarg;
			break;
		case 'V':
			desc.version = optarg;
			break;
		default:
			warnx("Unrecognized option %c", opt);
			__attribute__((__fallthrough__));
		case 'h':
		case '?':
			usage();
		}
	}

	if (bind) {
		char *devpath;

		/* Give it some time to show up in case we're run at boot. */
		for (int tries = TIMEOUT_MS / DELAY_MS; tries > 0; tries--) {
			devpath = find_dev_by_vid_pid(bind);
			if (devpath)
				break;
			usleep(DELAY_MS * 1000);
		}
		if (!devpath)
			errx(2, "Cannot find USB device %s", bind);

		if (try_switch_aoa(devpath, &desc) != 0 ||
		    (driver && disable_adb_if(devpath) != 0))
			errx(3, "Failed to switch %s into AOA mode", bind);
		free(devpath);
	} else if (do_all) {
		int count = 0;
		char *devpath;
		for_each_usbdev(devpath) {
			if (try_switch_aoa(devpath, &desc) == 0 &&
			    (driver && disable_adb_if(devpath) == 0))
				count++;
		}
		if (!count)
			errx(128, "No AOA-compatible devices found");
	} else {
		usage();
	}

	if (driver)
		register_with_driver(driver);

	return 0;
}
