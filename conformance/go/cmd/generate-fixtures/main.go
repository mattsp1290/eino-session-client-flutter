package main

import (
	"encoding/json"
	"flag"
	"log"
	"os"

	"github.com/mattsp1290/eino-session-client-flutter/conformance/internal/fixture"
)

func main() {
	output := flag.String("output", "../fixtures", "fixture output directory")
	flag.Parse()
	if err := os.MkdirAll(*output, 0o755); err != nil {
		log.Fatal(err)
	}
	hashes, err := fixture.Generate(*output)
	if err != nil {
		log.Fatal(err)
	}
	manifest := map[string]any{
		"generator":  "go-ag-ui-sse",
		"seed":       20260910,
		"eino_agent": "v0.3.4-0.20260908141855-99a87b8cb1ac",
		"eino_agui":  "v0.1.1",
		"ag_ui_go":   "v0.0.0-20260624151131-d2049debabd9",
		"framing":    "SSE emitted by the pinned Go SDK; generated timestamp fields are normalized to 1700000000000 after capture",
		"sha256":     hashes,
	}
	data, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		log.Fatal(err)
	}
	data = append(data, '\n')
	if err := os.WriteFile(*output+"/manifest.json", data, 0o644); err != nil {
		log.Fatal(err)
	}
}
