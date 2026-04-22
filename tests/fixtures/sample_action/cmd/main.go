// Command sample_action is a minimal fixture used by the go-docker-action-ci-action
// CI workflow to exercise the Go test + Docker build + local-registry push prelude.
package main

import (
	"fmt"
	"os"
)

func main() {
	msg := greet(os.Getenv("INPUT_NAME"))
	fmt.Println(msg)
}

func greet(name string) string {
	if name == "" {
		name = "world"
	}
	return fmt.Sprintf("hello, %s", name)
}
