package fixture

import (
	"bytes"
	"testing"
)

func TestFixturesAreEncodedAndPrivate(t *testing.T) {
	for name, generate := range map[string]func() ([]byte, error){
		"generic": Generic,
		"watch":   Watch,
		"resync":  Resync,
		"privacy": Privacy,
	} {
		t.Run(name, func(t *testing.T) {
			data, err := generate()
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Contains(data, []byte("data:")) {
				t.Fatal("fixture is not SSE framed")
			}
			if bytes.Contains(data, []byte(PrivacyCanary)) {
				t.Fatal("privacy canary escaped")
			}
		})
	}
}
