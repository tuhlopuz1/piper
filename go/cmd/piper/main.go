package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/catsi/piper/core"
	"github.com/catsi/piper/tui"
	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	var name string
	flag.StringVar(&name, "name", defaultName(), "Display name shown to other peers")
	flag.Parse()

	if name == "" {
		fmt.Fprintln(os.Stderr, "name must not be empty")
		os.Exit(1)
	}

	// Redirect stdlib log to a file so it doesn't corrupt the TUI.
	logFile, err := os.OpenFile("piper.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err == nil {
		log.SetOutput(logFile)
		defer logFile.Close()
	}

	node := core.NewNode(name)
	if err := node.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "failed to start node: %v\n", err)
		os.Exit(1)
	}
	defer node.Stop()

	m := tui.New(node)
	p := tea.NewProgram(m,
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(),
	)
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "TUI error: %v\n", err)
		os.Exit(1)
	}
}

func defaultName() string {
	if h, err := os.Hostname(); err == nil {
		return filepath.Base(h)
	}
	return "peer"
}
