package core

// MeshNode is a node in the topology graph exposed to UI/FFI.
type MeshNode struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	IsSelf        bool   `json:"is_self,omitempty"`
	IsConnected   bool   `json:"is_connected,omitempty"`
	IsRelay       bool   `json:"is_relay,omitempty"`
	RelayPeerID   string `json:"relay_peer_id,omitempty"`
	RelayPeerName string `json:"relay_peer_name,omitempty"`
	Hops          int    `json:"hops,omitempty"`
}

// MeshEdge is a directed edge in the topology graph.
type MeshEdge struct {
	From     string `json:"from"`
	To       string `json:"to"`
	Kind     string `json:"kind"` // "direct" or "relay"
	Hops     int    `json:"hops,omitempty"`
	NextHop  string `json:"next_hop,omitempty"`
	IsActive bool   `json:"is_active,omitempty"`
}

// MeshTopology is a serializable graph snapshot.
type MeshTopology struct {
	LocalID string     `json:"local_id"`
	Nodes   []MeshNode `json:"nodes"`
	Edges   []MeshEdge `json:"edges"`
}

// TopologySnapshot returns the local view of mesh topology.
func (n *Node) TopologySnapshot() MeshTopology {
	peers := n.Peers()
	nodes := make([]MeshNode, 0, len(peers)+1)
	edges := make([]MeshEdge, 0, len(peers)*2)

	nodes = append(nodes, MeshNode{
		ID:          n.id,
		Name:        n.name,
		IsSelf:      true,
		IsConnected: true,
	})

	relayNameByID := map[string]string{}
	for _, p := range peers {
		relayNameByID[p.ID] = p.DisplayName
	}

	for _, p := range peers {
		node := MeshNode{
			ID:          p.ID,
			Name:        p.DisplayName,
			IsConnected: p.State == PeerConnected,
			IsRelay:     p.IsRelay,
			RelayPeerID: p.RelayVia,
			Hops:        p.RelayHops,
		}
		if p.RelayVia != "" {
			node.RelayPeerName = relayNameByID[p.RelayVia]
		}
		nodes = append(nodes, node)

		if p.State == PeerConnected && !p.IsRelay {
			edges = append(edges, MeshEdge{
				From:     n.id,
				To:       p.ID,
				Kind:     "direct",
				Hops:     1,
				NextHop:  p.ID,
				IsActive: true,
			})
			continue
		}
		if p.RelayVia != "" {
			edges = append(edges, MeshEdge{
				From:     n.id,
				To:       p.ID,
				Kind:     "relay",
				Hops:     p.RelayHops,
				NextHop:  p.RelayVia,
				IsActive: p.State == PeerConnected,
			})
		}
	}

	return MeshTopology{
		LocalID: n.id,
		Nodes:   nodes,
		Edges:   edges,
	}
}
