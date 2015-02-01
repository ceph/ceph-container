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
	Image  string
	Pool   string
	FSType string
	Target string
)

func init() {
	flag.StringVar(&Image, "image", "image0", "RBD Image to mount")
	flag.StringVar(&Pool, "pool", "rbd", "RBD Pool in which Image resides")
	flag.StringVar(&FSType, "fstype", "xfs", "Filesystem type")
	flag.StringVar(&Target, "target", "/mnt/rbd", "Mountpoint / target")
}

func main() {
	flag.Parse()

	// Mount the RBD
	err := syscall.Mount("/dev/rbd/"+Pool+"/"+Image, Target, FSType, 0, "")
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
