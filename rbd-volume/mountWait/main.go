// mountWait mounts a given RBD image, waits for a STOP signal,
// then unmounts the image and exits.
package main

/*
#include <sched.h>
#include <stdio.h>
#include <fcntl.h>

__attribute__((constructor)) void enter_namespace(void) {
   setns(open("/host/proc/1/ns/mnt", O_RDONLY, 0644), 0);
}
*/
import "C"

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"strings"	
	"syscall"
)

var (
	RBDDev   string
	FSType string
	Target string
	MountOpts string
)

func init() {
	flag.StringVar(&RBDDev, "rbddev", "", "RBD dev to mount")
	flag.StringVar(&FSType, "fstype", "", "Filesystem type")
	flag.StringVar(&Target, "target", "", "Mountpoint / target")
	flag.StringVar(&MountOpts, "o", "", "options to use when mounting an image")
}

func calcFlags(opts string) uintptr {
	var flags uintptr = 0

	for _, o := range strings.Split(opts, ",") {
		switch o {
			default:
				log.Fatalf("Failed to mount: %s: option not supported\n", o)
			case "atime":
				flags |= 0
			case "async":
				flags |= 0
			case "dev":
				flags |= 0					
			case "diratime":
				flags |= 0
			case "dirsync":
				flags |= syscall.MS_DIRSYNC
			case "exec":
				flags |= 0
			case "mand":
				flags |= syscall.MS_MANDLOCK						
			case "noatime":
				flags |= syscall.MS_NOATIME	
			case "nodev":
				flags |= syscall.MS_NODEV
			case "nodiratime":
				flags |= syscall.MS_NODIRATIME													
			case "noexec":
				flags |= syscall.MS_NOEXEC
			case "nomand":
				flags |= 0
			case "norelatime":
				flags |= 0
			case "nostrictatime":
				flags |= 0					
			case "nosuid":
				flags |= syscall.MS_NOSUID					
			case "relatime":
				flags |= syscall.MS_RELATIME
			case "remount":
				flags |= syscall.MS_REMOUNT
			case "ro":
				flags |= syscall.MS_RDONLY
			case "rw":
				flags |= 0					
			case "strictatime":
				flags |= syscall.MS_STRICTATIME
			case "suid":
				flags |= syscall.MS_NODEV
			case "sync":
				flags |= syscall.MS_SYNCHRONOUS						
		}
	}

	return flags
}

func main() {
	flag.Parse()

	var syscall_flags uintptr = 0

	if len(MountOpts) > 0 {
		syscall_flags = calcFlags(MountOpts) 
	} else if os.Getenv("RBD_OPTS") != "" {
		syscall_flags = calcFlags(os.Getenv("RBD_OPTS"))
	}

	if RBDDev == "" {
		RBDDev = os.Getenv("RBD_DEV")
	}

	if Target == "" {
		Target = os.Getenv("RBD_TARGET")
	}

	if FSType == "" {
		FSType = os.Getenv("RBD_FS")
	}

	// Mount the RBD
	err := syscall.Mount(RBDDev, Target, FSType, syscall_flags, "")
	if err != nil {
		log.Fatalf("Failed to mount: %s\n", err.Error())
	}

	// Set up signal listener channel
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, os.Kill)

	// Wait for signal
	<-c

	// Unmount the RBD
	err = syscall.Unmount(Target, 1) // Flag = 1: Force unmounting
	if err != nil {
		log.Fatalf("Failed to cleanly unmount RBD: %s\n", err.Error())
	}
}
