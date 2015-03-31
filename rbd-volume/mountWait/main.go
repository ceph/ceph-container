// mountWait mounts a given RBD image, waits for a STOP signal,
// then unmounts the image and exits.
package main

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
	flag.StringVar(&RBDDev, "rbddev", "rbd", "RBD dev to mount")
	flag.StringVar(&FSType, "fstype", "xfs", "Filesystem type")
	flag.StringVar(&Target, "target", "/mnt/rbd", "Mountpoint / target")
	flag.StringVar(&MountOpts, "o", "", "options to use when mounting an image")
}

func main() {
	flag.Parse()

	var syscall_flags uintptr = 0

	if len(MountOpts) > 0 {
		for _, o := range strings.Split(MountOpts, ",") {
			switch o {
				default:
					log.Fatalf("Failed to mount: -o %s: option not supported\n", o)
				case "atime":
					syscall_flags |= 0
				case "async":
					syscall_flags |= 0
				case "dev":
					syscall_flags |= 0					
				case "diratime":
					syscall_flags |= 0
				case "dirsync":
					syscall_flags |= syscall.MS_DIRSYNC
				case "exec":
					syscall_flags |= 0
				case "mand":
					syscall_flags |= syscall.MS_MANDLOCK						
				case "noatime":
					syscall_flags |= syscall.MS_NOATIME	
				case "nodev":
					syscall_flags |= syscall.MS_NODEV
				case "nodiratime":
					syscall_flags |= syscall.MS_NODIRATIME													
				case "noexec":
					syscall_flags |= syscall.MS_NOEXEC
				case "nomand":
					syscall_flags |= 0
				case "norelatime":
					syscall_flags |= 0
				case "nostrictatime":
					syscall_flags |= 0					
				case "nosuid":
					syscall_flags |= syscall.MS_NOSUID					
				case "relatime":
					syscall_flags |= syscall.MS_RELATIME
				case "remount":
					syscall_flags |= syscall.MS_REMOUNT
				case "ro":
					syscall_flags |= syscall.MS_RDONLY
				case "rw":
					syscall_flags |= 0					
				case "strictatime":
					syscall_flags |= syscall.MS_STRICTATIME
				case "suid":
					syscall_flags |= syscall.MS_NODEV
				case "sync":
					syscall_flags |= syscall.MS_SYNCHRONOUS						
			}
		}
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
