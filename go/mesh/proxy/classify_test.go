package proxy_test

import (
	"testing"

	"github.com/catsi/piper/mesh/proxy"
)

func TestClassifySTUN(t *testing.T) {
	for _, b := range []byte{0x00, 0x01, 0x02, 0x03} {
		if proxy.Classify([]byte{b}) != proxy.PktSTUN {
			t.Fatalf("byte 0x%02x should be STUN", b)
		}
	}
}

func TestClassifyDTLS(t *testing.T) {
	for _, b := range []byte{20, 40, 63} {
		if proxy.Classify([]byte{b}) != proxy.PktDTLS {
			t.Fatalf("byte %d should be DTLS", b)
		}
	}
}

func TestClassifySRTP(t *testing.T) {
	for _, b := range []byte{128, 150, 191} {
		if proxy.Classify([]byte{b}) != proxy.PktSRTP {
			t.Fatalf("byte %d should be SRTP", b)
		}
	}
}

func TestClassifyUnknown(t *testing.T) {
	if proxy.Classify([]byte{}) != proxy.PktUnknown {
		t.Fatal("empty should be unknown")
	}
	if proxy.Classify([]byte{64}) != proxy.PktUnknown {
		t.Fatal("64 should be unknown")
	}
}
