package tui

import "github.com/charmbracelet/lipgloss"

var (
	// Layout colours
	colorPrimary   = lipgloss.Color("#7C3AED") // violet
	colorAccent    = lipgloss.Color("#10B981") // emerald
	colorMuted     = lipgloss.Color("#6B7280") // grey
	colorFg        = lipgloss.Color("#F3F4F6")
	colorBg        = lipgloss.Color("#111827")
	colorBorder    = lipgloss.Color("#374151")
	colorHighlight = lipgloss.Color("#1F2937")

	// Borders
	borderStyle = lipgloss.RoundedBorder()

	// Panels
	panelStyle = lipgloss.NewStyle().
			Border(borderStyle).
			BorderForeground(colorBorder).
			Padding(0, 1)

	activePanel = lipgloss.NewStyle().
			Border(borderStyle).
			BorderForeground(colorPrimary).
			Padding(0, 1)

	// Header
	headerStyle = lipgloss.NewStyle().
			Foreground(colorPrimary).
			Bold(true).
			Padding(0, 1)

	// Status bar
	statusStyle = lipgloss.NewStyle().
			Foreground(colorMuted).
			Padding(0, 1)

	// Messages
	myMsgStyle = lipgloss.NewStyle().
			Foreground(colorAccent).
			Bold(true)

	theirMsgStyle = lipgloss.NewStyle().
			Foreground(colorFg)

	senderStyle = lipgloss.NewStyle().
			Foreground(colorPrimary).
			Bold(true)

	timeStyle = lipgloss.NewStyle().
			Foreground(colorMuted)

	systemMsgStyle = lipgloss.NewStyle().
			Foreground(colorMuted).
			Italic(true)

	// Peer list
	peerOnlineStyle = lipgloss.NewStyle().
			Foreground(colorAccent)

	peerOfflineStyle = lipgloss.NewStyle().
			Foreground(colorMuted)

	// Input
	inputPromptStyle = lipgloss.NewStyle().
				Foreground(colorPrimary).
				Bold(true)
)
