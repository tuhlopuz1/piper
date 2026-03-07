package transport

import "encoding/binary"

const (
	MeshHeaderMaxLen = 64
	HopsOffset       = 11 // bytes before hops[] in header

	TypeData     = byte(0x00)
	TypeGossip   = byte(0x10)
	TypeProbe    = byte(0x30)
	TypeProbeAck = byte(0x40)
)

// EncodeDataPacket writes a mesh DATA packet into buf starting at buf[0].
// Returns total packet length (header + payload).
// buf must be at least MeshHeaderMaxLen + len(payload) bytes.
func EncodeDataPacket(buf []byte, src, dst uint32, hops []uint32, payload []byte) int {
	hdrLen := HopsOffset + len(hops)*4 + 2 // +2 for payload_len field

	h := buf[:hdrLen]
	h[0] = TypeData
	h[1] = 0 // current_hop_idx
	h[2] = byte(len(hops))
	binary.BigEndian.PutUint32(h[3:], src)
	binary.BigEndian.PutUint32(h[7:], dst)
	for i, hop := range hops {
		binary.BigEndian.PutUint32(h[HopsOffset+i*4:], hop)
	}
	plenOff := HopsOffset + len(hops)*4
	binary.BigEndian.PutUint16(h[plenOff:], uint16(len(payload)))

	copy(buf[hdrLen:], payload)
	return hdrLen + len(payload)
}

func ReadSrcHash(pkt []byte) uint32  { return binary.BigEndian.Uint32(pkt[3:]) }
func ReadDstHash(pkt []byte) uint32  { return binary.BigEndian.Uint32(pkt[7:]) }
func CurrentHopIdx(pkt []byte) byte  { return pkt[1] }
func HopCount(pkt []byte) byte       { return pkt[2] }
func IncrementHopIdx(pkt []byte)     { pkt[1]++ }

func NextHopHash(pkt []byte) uint32 {
	idx := int(pkt[1])
	return binary.BigEndian.Uint32(pkt[HopsOffset+(idx+1)*4:])
}

func ExtractPayload(pkt []byte) []byte {
	hopCount := int(pkt[2])
	plenOff := HopsOffset + hopCount*4
	plen := binary.BigEndian.Uint16(pkt[plenOff:])
	return pkt[plenOff+2 : plenOff+2+int(plen)]
}
