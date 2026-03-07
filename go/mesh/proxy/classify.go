package proxy

type PktClass uint8

const (
	PktSTUN    PktClass = iota
	PktDTLS
	PktSRTP
	PktUnknown
)

func Classify(b []byte) PktClass {
	if len(b) == 0 {
		return PktUnknown
	}
	switch {
	case b[0] <= 0x03:
		return PktSTUN
	case b[0] >= 20 && b[0] <= 63:
		return PktDTLS
	case b[0] >= 128 && b[0] <= 191:
		return PktSRTP
	default:
		return PktUnknown
	}
}
