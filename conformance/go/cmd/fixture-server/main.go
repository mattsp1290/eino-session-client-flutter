package main

import (
	"context"
	"flag"
	"log"
	"net"
	"net/http"
	"os"

	"github.com/mattsp1290/eino-session-client-flutter/conformance/internal/fixture"
)

func main() {
	address := flag.String("addr", "127.0.0.1:8080", "loopback listen address")
	readyFile := flag.String("ready-file", "", "optional file receiving the bound address")
	database := flag.String("db", "fixture.db", "SQLite fixture database path")
	flag.Parse()
	server, err := fixture.NewRuntimeServer(context.Background(), *database)
	if err != nil {
		log.Fatal(err)
	}
	defer func() {
		if err := server.Close(); err != nil {
			log.Printf("close fixture server: %v", err)
		}
	}()
	listener, err := net.Listen("tcp", *address)
	if err != nil {
		log.Fatal(err)
	}
	if *readyFile != "" {
		if err := os.WriteFile(*readyFile, []byte(listener.Addr().String()), 0o600); err != nil {
			log.Fatal(err)
		}
	}
	log.Printf("fixture server listening on %s", listener.Addr())
	if err := http.Serve(listener, server); err != nil {
		log.Fatal(err)
	}
}
