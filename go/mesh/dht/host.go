//go:build !android

package dht

import (
	"context"
	"fmt"

	"github.com/catsi/piper/mesh/identity"
	"github.com/catsi/piper/mesh/router"
	libp2p "github.com/libp2p/go-libp2p"
	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	kaddht "github.com/libp2p/go-libp2p-kad-dht"
	"github.com/multiformats/go-multiaddr"
)

func newHost(keys identity.Keys, port int) (host.Host, error) {
	privKey, err := libp2pcrypto.UnmarshalEd25519PrivateKey(keys.Ed25519Priv)
	if err != nil {
		return nil, fmt.Errorf("dht: unmarshal ed25519: %w", err)
	}
	return libp2p.New(
		libp2p.Identity(privKey),
		libp2p.ListenAddrStrings(fmt.Sprintf("/ip4/0.0.0.0/tcp/%d", port)),
	)
}

func newKadDHT(ctx context.Context, h host.Host) (*kaddht.IpfsDHT, error) {
	return kaddht.New(ctx, h,
		kaddht.Mode(kaddht.ModeServer),
		kaddht.ProtocolPrefix("/piper"),
		kaddht.NamespacedValidator("piper", PiperValidator{}),
		kaddht.DisableAutoRefresh(),
	)
}

func bootstrapPeers(peers []router.MeshPeer, dhtPortOffset int) []peer.AddrInfo {
	var infos []peer.AddrInfo
	for _, p := range peers {
		if len(p.IdentityEd25519Pub) == 0 {
			continue
		}
		pubKey, err := libp2pcrypto.UnmarshalEd25519PublicKey(p.IdentityEd25519Pub)
		if err != nil {
			continue
		}
		peerID, err := peer.IDFromPublicKey(pubKey)
		if err != nil {
			continue
		}
		var maddrs []multiaddr.Multiaddr
		for _, addr := range p.Addrs {
			if addr.Type != "tcp" || addr.IP == "" {
				continue
			}
			ma, err := multiaddr.NewMultiaddr(
				fmt.Sprintf("/ip4/%s/tcp/%d", addr.IP, addr.Port+dhtPortOffset),
			)
			if err == nil {
				maddrs = append(maddrs, ma)
			}
		}
		if len(maddrs) > 0 {
			infos = append(infos, peer.AddrInfo{ID: peerID, Addrs: maddrs})
		}
	}
	return infos
}
