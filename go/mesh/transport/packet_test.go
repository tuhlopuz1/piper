package transport_test

import (
	"testing"

	"github.com/catsi/piper/mesh/transport"
)

func TestEncodeDecodeDataPacket(t *testing.T) {
	src := uint32(0xAABBCCDD)
	dst := uint32(0x11223344)
	hops := []uint32{0xDEADBEEF, 0xCAFEBABE}
	payload := []byte("hello mesh")

	buf := make([]byte, transport.MeshHeaderMaxLen+len(payload)+128)
	n := transport.EncodeDataPacket(buf, src, dst, hops, payload)

	pkt := buf[:n]
	if pkt[1] != 0 {
		t.Fatalf("current_hop_idx want 0 got %d", pkt[1])
	}
	if int(pkt[2]) != len(hops) {
		t.Fatalf("hop_count want %d got %d", len(hops), pkt[2])
	}

	gotSrc := transport.ReadSrcHash(pkt)
	if gotSrc != src {
		t.Fatalf("src want %x got %x", src, gotSrc)
	}

	gotDst := transport.ReadDstHash(pkt)
	if gotDst != dst {
		t.Fatalf("dst want %x got %x", dst, gotDst)
	}

	gotPayload := transport.ExtractPayload(pkt)
	if string(gotPayload) != "hello mesh" {
		t.Fatalf("payload want 'hello mesh' got %q", gotPayload)
	}
}

func TestForwardIncrementHopIdx(t *testing.T) {
	buf := make([]byte, 256)
	hops := []uint32{0xAAAA, 0xBBBB, 0xCCCC}
	n := transport.EncodeDataPacket(buf, 0x1, 0x3, hops, []byte("data"))
	pkt := buf[:n]

	if pkt[1] != 0 {
		t.Fatal("initial hop idx must be 0")
	}
	transport.IncrementHopIdx(pkt)
	if pkt[1] != 1 {
		t.Fatal("after increment hop idx must be 1")
	}
}

func TestNextHopHash(t *testing.T) {
	buf := make([]byte, 256)
	hops := []uint32{0xAAAA, 0xBBBB, 0xCCCC}
	n := transport.EncodeDataPacket(buf, 0x1, 0x3, hops, []byte("x"))
	pkt := buf[:n]

	got := transport.NextHopHash(pkt)
	if got != hops[1] {
		t.Fatalf("want %x got %x", hops[1], got)
	}
}
