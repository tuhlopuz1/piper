package ipc

import (
	"encoding/json"
	"net/http"
)

func registerAPI(mux *http.ServeMux, s Sender) {
	// GET /api/status — returns daemon info (id, name, ip, port)
	mux.HandleFunc("GET /api/status", func(w http.ResponseWriter, r *http.Request) {
		jsonOK(w, s.GetStatus())
	})

	// GET /api/peers — returns list of connected peers
	mux.HandleFunc("GET /api/peers", func(w http.ResponseWriter, r *http.Request) {
		jsonOK(w, s.GetPeers())
	})

	// POST /api/message/send — send a text message to a peer
	// Body: {"to": "peer_id", "text": "..."}
	mux.HandleFunc("POST /api/message/send", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			To   string `json:"to"`
			Text string `json:"text"`
		}
		if !decodeBody(w, r, &req) {
			return
		}
		if err := s.SendText(req.To, req.Text); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		jsonOK(w, okResp())
	})

	// POST /api/call/signal — relay WebRTC signaling to a peer
	// Body: {"to": "peer_id", "sdp_type": "offer|answer", "sdp": "...", "candidate": "..."}
	mux.HandleFunc("POST /api/call/signal", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			To        string `json:"to"`
			SDPType   string `json:"sdp_type"`
			SDP       string `json:"sdp"`
			Candidate string `json:"candidate"`
		}
		if !decodeBody(w, r, &req) {
			return
		}
		if err := s.SendCallSignal(req.To, req.SDPType, req.SDP, req.Candidate); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		jsonOK(w, okResp())
	})

	// POST /api/call/end — tell a peer the call has ended
	// Body: {"to": "peer_id"}
	mux.HandleFunc("POST /api/call/end", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			To string `json:"to"`
		}
		if !decodeBody(w, r, &req) {
			return
		}
		_ = s.EndCall(req.To)
		jsonOK(w, okResp())
	})

	// POST /api/profile/set — update our display name / avatar colour
	// Body: {"name": "Alex", "avatar_color": "#8b5cf6"}
	mux.HandleFunc("POST /api/profile/set", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Name        string `json:"name"`
			AvatarColor string `json:"avatar_color"`
		}
		if !decodeBody(w, r, &req) {
			return
		}
		s.SetProfile(req.Name, req.AvatarColor)
		jsonOK(w, okResp())
	})
}

// ── helpers ───────────────────────────────────────────────────────────────────

func jsonOK(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

func decodeBody(w http.ResponseWriter, r *http.Request, dst any) bool {
	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return false
	}
	return true
}

func okResp() map[string]string { return map[string]string{"ok": "1"} }
