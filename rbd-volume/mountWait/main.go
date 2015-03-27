// mountWait mounts a given RBD image, waits for a STOP signal,
// then unmounts the image and exits.
package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"
)

var (
	RBDDev   string
	FSType string
	Target string
	Readonly bool
)

func init() {
	flag.StringVar(&RBDDev, "rbddev", "rbd", "RBD dev to mount")
	flag.StringVar(&FSType, "fstype", "xfs", "Filesystem type")
	flag.StringVar(&Target, "target", "/mnt/rbd", "Mountpoint / target")
	flag.BoolVar(&Readonly, "r", false, "Mount the file system read-only")
}

func main() {
	flag.Parse()

	var syscall_flags uintptr = 0

	if Readonly {
		syscall_flags |= syscall.MS_RDONLY
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
