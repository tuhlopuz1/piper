package router

import (
	"container/heap"
)

const (
	RouteHysteresis  = 0.25
	StickyLossThresh = float32(0.15)
	EMARTTAlpha      = 0.2
)

type Route struct {
	Destination uint32
	Hops        []uint32 // [hop1, hop2, ..., dst]
	Score       float64
}

// EdgeWeight computes the Dijkstra edge cost.
// loss is quadratic: 5% → 25, 15% → 225.
func EdgeWeight(rttMs float64, lossRatio float32, linkType string) float64 {
	penalty := map[string]float64{"tcp": 0, "wifidirect": 10, "ble": 200}
	p := penalty[linkType]
	l := float64(lossRatio)
	return rttMs + l*l*10000 + p
}

// ShouldSwitch returns true if candidate is ≥25% better than current.
func ShouldSwitch(current, candidate *Route) bool {
	if current == nil {
		return true
	}
	return candidate.Score < current.Score*(1-RouteHysteresis)
}

type node struct {
	id   uint32
	dist float64
	path []uint32
}
type minHeap []node

func (h minHeap) Len() int            { return len(h) }
func (h minHeap) Less(i, j int) bool  { return h[i].dist < h[j].dist }
func (h minHeap) Swap(i, j int)       { h[i], h[j] = h[j], h[i] }
func (h *minHeap) Push(x any)         { *h = append(*h, x.(node)) }
func (h *minHeap) Pop() any           { old := *h; n := old[len(old)-1]; *h = old[:len(old)-1]; return n }

// Dijkstra computes the best source route from src to dst.
// localLinks: direct links from the local node (src), keyed by neighbor hashID.
func Dijkstra(src, dst uint32, pt *PeerTable, localLinks map[uint32]LinkEntry) *Route {
	dist := map[uint32]float64{src: 0}
	prev := map[uint32]uint32{}

	h := &minHeap{{id: src, dist: 0}}
	heap.Init(h)

	neighbors := func(id uint32) []LinkEntry {
		if id == src { // local outgoing links
			out := make([]LinkEntry, 0, len(localLinks))
			for _, e := range localLinks {
				out = append(out, e)
			}
			return out
		}
		p := pt.GetByHash(id)
		if p == nil {
			return nil
		}
		return p.Links
	}

	for h.Len() > 0 {
		cur := heap.Pop(h).(node)
		if cur.id == dst {
			// Reconstruct path
			path := []uint32{}
			for n := dst; n != src; n = prev[n] {
				path = append([]uint32{n}, path...)
			}
			return &Route{Destination: dst, Hops: path, Score: cur.dist}
		}

		for _, e := range neighbors(cur.id) {
			w := EdgeWeight(e.RTTms, e.LossRatio, "tcp")
			nd := cur.dist + w
			if best, ok := dist[e.PeerHashID]; !ok || nd < best {
				dist[e.PeerHashID] = nd
				prev[e.PeerHashID] = cur.id
				heap.Push(h, node{id: e.PeerHashID, dist: nd})
			}
		}
	}
	return nil
}

// UpdateEMA updates RTT using exponential moving average (alpha=0.2).
func UpdateEMA(old, current float64) float64 {
	return old*(1-EMARTTAlpha) + current*EMARTTAlpha
}

func UpdateLossEMA(old, current float32) float32 {
	return old*(1-EMARTTAlpha) + current*EMARTTAlpha
}

func IsAboveStickyThreshold(lossRatio float32) bool {
	return lossRatio > StickyLossThresh
}
