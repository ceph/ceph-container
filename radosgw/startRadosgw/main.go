// Wrapper for radosgw which
// starts and monitors Apache and radosgw
package main

import (
	"log"
	"os"
	"os/exec"
)

func main() {
	Apache := exec.Command("/usr/sbin/apache2", "-DFOREGROUND")
	Apache.Stdout = os.Stdout
	Apache.Stderr = os.Stderr

	RadosGW := exec.Command("/usr/bin/radosgw", "-d", "-c", "/etc/ceph/ceph.conf", "-n", "client.radosgw.gateway", "-k", "/var/lib/ceph/radosgw/"+os.Getenv("RGW_NAME")+"/keyring")
	RadosGW.Stdout = os.Stdout
	RadosGW.Stderr = os.Stderr

	// Run Apache first
	go func() {
		err := Apache.Run()
		log.Fatalln("Apache stopped:", err)
	}()

	// Run RadosGW
	err := RadosGW.Run()
	log.Fatalln("RadosGW stopped:", err)
}
