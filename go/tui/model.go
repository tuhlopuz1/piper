package tui

// model.go — bubbletea Model for the full TUI.
//
// Layout:
//
//  ┌─ claudemess  Alice  [tab]… ──────────────────────────────┐
//  │ Peers              │ Chat: Dev Team [E2E]                 │
//  │ ──────────────     │ [10:01] Bob: hey team                │
//  │ > * Global Chat    │ [10:02] You: hi!                     │
//  │   ● Bob (2)        │ ─────────────────────────────────── │
//  │   ○ Charlie        │ > type here...                      │
//  │   ─ Groups ─       │                                     │
//  │   # Dev Team       │                                     │
//  └─ id: a1b2c3d4… ────┴─────────────────────────────────────┘
//
// Navigation:
//  tab          – switch focus between peers and chat panels
//  ↑/↓          – move cursor (peers panel) or scroll (chat panel)
//  enter        – open chat (peers) / send message (chat)
//  esc          – return to Global Chat
//  ctrl+g       – create a new group (prompts for name)
//  ctrl+p       – invite a peer to the current group
//  ctrl+l       – leave the current group
//  ctrl+c/q     – quit

import (
	"fmt"
	"sort"
	"strings"

	"github.com/catsi/piper/core"
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ─── Focus & input mode ──────────────────────────────────────────────────────

type focus int

const (
	focusChat focus = iota
	focusPeers
)

type inputMode int

const (
	modeNormal      inputMode = iota
	modeCreateGroup           // typing group name
	modeInvitePeer            // selecting a peer to invite to current group
	modeSendFile              // typing file path to send
)

// ─── Chat / panel item types ─────────────────────────────────────────────────

type chatStore struct {
	lines  []string
	unread int
}

// panelItemKind distinguishes the types of rows in the peers/groups panel.
type panelItemKind int

const (
	itemGlobal panelItemKind = iota
	itemPeer
	itemSeparator
	itemGroup
)

type panelItem struct {
	kind   panelItemKind
	id     string // "" for global/separator; peerID for peer; "group:<gid>" for group
	name   string
	state  core.PeerState // only for itemPeer
	unread int
}

type nodeEventMsg core.Event

// ─── Model ───────────────────────────────────────────────────────────────────

type Model struct {
	node   *core.Node
	width  int
	height int
	focus  focus

	// Chat state
	activeChatID string // "" = global, peerID = personal, "group:<gid>" = group
	chats        map[string]*chatStore

	// Panel cursor
	peerCursor int

	// Input mode
	mode         inputMode
	groupInput   textarea.Model // group name entry (modeCreateGroup)
	fileInput    textarea.Model // file path entry (modeSendFile)
	inviteCursor int            // peer selection cursor (modeInvitePeer)

	// Widgets
	viewport viewport.Model
	input    textarea.Model
	ready    bool
}

// ─── Constructor / Init ──────────────────────────────────────────────────────

func New(node *core.Node) Model {
	inp := textarea.New()
	inp.Placeholder = "Type a message…"
	inp.Focus()
	inp.SetHeight(3)
	inp.CharLimit = 2000
	inp.ShowLineNumbers = false

	gi := textarea.New()
	gi.Placeholder = "Group name…"
	gi.SetHeight(1)
	gi.CharLimit = 64
	gi.ShowLineNumbers = false

	fi := textarea.New()
	fi.Placeholder = "File path…"
	fi.SetHeight(1)
	fi.CharLimit = 512
	fi.ShowLineNumbers = false

	return Model{
		node:       node,
		focus:      focusChat,
		input:      inp,
		groupInput: gi,
		fileInput:  fi,
		chats:      map[string]*chatStore{"": {}},
	}
}

func (m Model) Init() tea.Cmd {
	return tea.Batch(textarea.Blink, listenForEvents(m.node))
}

func listenForEvents(n *core.Node) tea.Cmd {
	return func() tea.Msg {
		e := <-n.Events()
		return nodeEventMsg(e)
	}
}

// ─── Update ──────────────────────────────────────────────────────────────────

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m = m.resize()

	case nodeEventMsg:
		e := core.Event(msg)
		if e.Msg != nil {
			m = m.appendMessage(*e.Msg)
		}
		if e.Peer != nil {
			m = m.handlePeerEvent(*e.Peer)
		}
		if e.Group != nil {
			m = m.handleGroupEvent(*e.Group)
		}
		if e.Transfer != nil {
			m = m.handleTransferEvent(*e.Transfer)
		}
		cmds = append(cmds, listenForEvents(m.node))

	case tea.KeyMsg:
		// Dispatch to the active input mode handler.
		switch m.mode {
		case modeCreateGroup:
			m, cmds = m.updateCreateGroup(msg, cmds)
		case modeInvitePeer:
			m, cmds = m.updateInvitePeer(msg, cmds)
		case modeSendFile:
			m, cmds = m.updateSendFile(msg, cmds)
		default:
			m, cmds = m.updateNormal(msg, cmds)
		}

	default:
		if m.ready {
			var vpCmd tea.Cmd
			m.viewport, vpCmd = m.viewport.Update(msg)
			cmds = append(cmds, vpCmd)
		}
	}

	return m, tea.Batch(cmds...)
}

// ─── Normal mode key handling ────────────────────────────────────────────────

func (m Model) updateNormal(msg tea.KeyMsg, cmds []tea.Cmd) (Model, []tea.Cmd) {
	switch msg.String() {

	case "ctrl+c", "ctrl+q":
		return m, append(cmds, tea.Quit)

	case "tab":
		m = m.toggleFocus()

	case "enter":
		if m.focus == focusChat {
			text := strings.TrimSpace(m.input.Value())
			if text != "" {
				m.sendForActiveChat(text)
				m.input.Reset()
			}
		} else {
			items := m.buildPanelItems()
			if m.peerCursor >= 0 && m.peerCursor < len(items) {
				it := items[m.peerCursor]
				if it.kind != itemSeparator {
					m = m.switchChat(it.id)
					m.focus = focusChat
					m.input.Focus()
				}
			}
		}

	case "up":
		if m.focus == focusPeers {
			m.peerCursor = m.skipSeparatorUp(m.peerCursor - 1)
		} else {
			var cmd tea.Cmd
			m.viewport, cmd = m.viewport.Update(msg)
			cmds = append(cmds, cmd)
		}

	case "down":
		if m.focus == focusPeers {
			items := m.buildPanelItems()
			m.peerCursor = m.skipSeparatorDown(m.peerCursor+1, len(items))
		} else {
			var cmd tea.Cmd
			m.viewport, cmd = m.viewport.Update(msg)
			cmds = append(cmds, cmd)
		}

	case "esc":
		if m.activeChatID != "" {
			m = m.switchChat("")
			m.peerCursor = 0
		}

	case "ctrl+g":
		m.mode = modeCreateGroup
		m.groupInput.Reset()
		m.groupInput.Focus()
		m.input.Blur()

	case "ctrl+p":
		// Enter invite mode if we're viewing a group chat, OR if the panel
		// cursor is currently on a group item (auto-switch to that group).
		targetGroupChat := ""
		if isGroupChat(m.activeChatID) {
			targetGroupChat = m.activeChatID
		} else if m.focus == focusPeers {
			items := m.buildPanelItems()
			if m.peerCursor >= 0 && m.peerCursor < len(items) && items[m.peerCursor].kind == itemGroup {
				targetGroupChat = items[m.peerCursor].id
				m = m.switchChat(targetGroupChat)
			}
		}
		if targetGroupChat != "" {
			m.mode = modeInvitePeer
			m.inviteCursor = 0
			m.input.Blur()
		}

	case "ctrl+l":
		if isGroupChat(m.activeChatID) {
			gid := groupIDFromChat(m.activeChatID)
			m.node.LeaveGroup(gid)
			m = m.switchChat("")
			m.peerCursor = 0
		}

	case "ctrl+f":
		// Allow file send in direct peer chats and group chats (not global).
		if m.activeChatID != "" {
			m.mode = modeSendFile
			m.fileInput.Reset()
			m.fileInput.Focus()
			m.input.Blur()
		}

	default:
		if m.focus == focusChat {
			var cmd tea.Cmd
			m.input, cmd = m.input.Update(msg)
			cmds = append(cmds, cmd)
		}
	}
	return m, cmds
}

// ─── Create-group mode ───────────────────────────────────────────────────────

func (m Model) updateCreateGroup(msg tea.KeyMsg, cmds []tea.Cmd) (Model, []tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.mode = modeNormal
		m.input.Focus()
	case "enter":
		name := strings.TrimSpace(m.groupInput.Value())
		if name != "" {
			g := m.node.CreateGroup(name)
			chatID := groupChatID(g.ID)
			if m.chats[chatID] == nil {
				m.chats[chatID] = &chatStore{}
			}
			m = m.switchChat(chatID)
		}
		m.mode = modeNormal
		m.input.Focus()
	default:
		var cmd tea.Cmd
		m.groupInput, cmd = m.groupInput.Update(msg)
		cmds = append(cmds, cmd)
	}
	return m, cmds
}

// ─── Invite-peer mode ────────────────────────────────────────────────────────

func (m Model) updateInvitePeer(msg tea.KeyMsg, cmds []tea.Cmd) (Model, []tea.Cmd) {
	candidates := m.inviteCandidates()
	switch msg.String() {
	case "esc":
		m.mode = modeNormal
		m.input.Focus()
	case "up":
		if m.inviteCursor > 0 {
			m.inviteCursor--
		}
	case "down":
		if m.inviteCursor < len(candidates)-1 {
			m.inviteCursor++
		}
	case "enter":
		if m.inviteCursor >= 0 && m.inviteCursor < len(candidates) {
			gid := groupIDFromChat(m.activeChatID)
			m.node.InviteToGroup(gid, candidates[m.inviteCursor].ID)
		}
		m.mode = modeNormal
		m.input.Focus()
	}
	return m, cmds
}

// inviteCandidates returns connected peers not already in the current group.
func (m Model) inviteCandidates() []*core.PeerInfo {
	if !isGroupChat(m.activeChatID) {
		return nil
	}
	gid := groupIDFromChat(m.activeChatID)
	g := m.node.GroupByID(gid)
	if g == nil {
		return nil
	}
	var out []*core.PeerInfo
	for _, p := range m.node.Peers() {
		if p.State == core.PeerConnected && !g.Members[p.ID] {
			out = append(out, p)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].DisplayName < out[j].DisplayName })
	return out
}

// ─── Send-file mode ──────────────────────────────────────────────────────────

func (m Model) updateSendFile(msg tea.KeyMsg, cmds []tea.Cmd) (Model, []tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.mode = modeNormal
		m.input.Focus()
	case "enter":
		path := strings.TrimSpace(m.fileInput.Value())
		if path != "" && m.activeChatID != "" {
			if isGroupChat(m.activeChatID) {
				gid := groupIDFromChat(m.activeChatID)
				sent, err := m.node.SendFileToGroup(gid, path)
				if err != nil {
					notice := systemMsgStyle.Render(fmt.Sprintf("  File error: %s", err))
					m = m.addNoticeToChat(m.activeChatID, notice)
				} else if sent > 0 {
					notice := systemMsgStyle.Render(
						fmt.Sprintf("  Sending file to %d group member(s)", sent))
					m = m.addNoticeToChat(m.activeChatID, notice)
				}
			} else {
				// Direct file transfer.
				if err := m.node.SendFile(m.activeChatID, path); err != nil {
					notice := systemMsgStyle.Render(fmt.Sprintf("  File send error: %s", err))
					m = m.addNoticeToChat(m.activeChatID, notice)
				}
			}
		}
		m.mode = modeNormal
		m.input.Focus()
	default:
		var cmd tea.Cmd
		m.fileInput, cmd = m.fileInput.Update(msg)
		cmds = append(cmds, cmd)
	}
	return m, cmds
}

// ─── Transfer event handling ─────────────────────────────────────────────────

func (m Model) handleTransferEvent(ev core.TransferEvent) Model {
	t := ev.Transfer
	// Route transfer notices: group transfers → group chat, direct → peer chat.
	chatID := t.PeerID
	if t.GroupID != "" {
		chatID = groupChatID(t.GroupID)
	}

	var notice string
	switch ev.Kind {
	case core.TransferOffered:
		dir := "Sending"
		if !t.Sending {
			dir = "Receiving"
		}
		notice = systemMsgStyle.Render(
			fmt.Sprintf("  %s %s (%s)", dir, t.FileName, formatBytes(t.FileSize)))

	case core.TransferStarted:
		notice = systemMsgStyle.Render(
			fmt.Sprintf("  Transfer of %s started", t.FileName))

	case core.TransferProgress:
		// Only emit progress notices at 25% intervals to avoid spam.
		if t.FileSize > 0 {
			pct := int(t.Progress * 100 / t.FileSize)
			// Emit at 25, 50, 75 — skip others.
			if pct == 25 || pct == 50 || pct == 75 {
				prevPct := int((t.Progress - core.ChunkSize) * 100 / t.FileSize)
				if prevPct < pct {
					notice = systemMsgStyle.Render(
						fmt.Sprintf("  %s: %d%%", t.FileName, pct))
				}
			}
		}

	case core.TransferCompleted:
		if t.Sending {
			notice = systemMsgStyle.Render(
				fmt.Sprintf("  File %s sent (%s)", t.FileName, formatBytes(t.FileSize)))
		} else {
			notice = systemMsgStyle.Render(
				fmt.Sprintf("  File %s received (%s)", t.FileName, formatBytes(t.FileSize)))
		}

	case core.TransferFailed:
		notice = systemMsgStyle.Render(
			fmt.Sprintf("  File transfer failed: %s", t.Err))
	}

	if notice != "" {
		m = m.addNoticeToChat(chatID, notice)
	}
	return m
}

func formatBytes(b int64) string {
	const (
		kb = 1024
		mb = 1024 * kb
		gb = 1024 * mb
	)
	switch {
	case b >= gb:
		return fmt.Sprintf("%.1f GB", float64(b)/float64(gb))
	case b >= mb:
		return fmt.Sprintf("%.1f MB", float64(b)/float64(mb))
	case b >= kb:
		return fmt.Sprintf("%.1f KB", float64(b)/float64(kb))
	default:
		return fmt.Sprintf("%d B", b)
	}
}

// ─── View ────────────────────────────────────────────────────────────────────

func (m Model) View() string {
	if !m.ready || m.width == 0 {
		return "  Initialising…"
	}

	peersW, chatW := m.panelWidths()

	chatTitle, encTag := m.chatTitleAndTag()

	shortcuts := "[tab] panels  [enter] send/open  [esc] global  [ctrl+g] group  [ctrl+f] file"
	header := headerStyle.Width(m.width).Render(
		fmt.Sprintf(" piper  %s  %s", m.node.Name(), shortcuts),
	)
	body := lipgloss.JoinHorizontal(lipgloss.Top,
		m.renderPanel(peersW),
		m.renderChat(chatW, chatTitle, encTag),
	)
	status := statusStyle.Width(m.width).Render(
		fmt.Sprintf(" id: %s…  peers: %d  groups: %d",
			m.node.ID()[:8], len(m.node.Peers()), len(m.node.Groups())),
	)

	return lipgloss.JoinVertical(lipgloss.Left, header, body, status)
}

func (m Model) chatTitleAndTag() (title, tag string) {
	if m.activeChatID == "" {
		return "Global Chat", ""
	}
	if isGroupChat(m.activeChatID) {
		gid := groupIDFromChat(m.activeChatID)
		if g := m.node.GroupByID(gid); g != nil {
			return g.Name, systemMsgStyle.Render(" [E2E]")
		}
		return "Group", ""
	}
	if peer := m.node.PeerByID(m.activeChatID); peer != nil {
		return peer.DisplayName, systemMsgStyle.Render(" [E2E]")
	}
	return "Chat", ""
}

func (m Model) renderPanel(w int) string {
	style := panelStyle
	if m.focus == focusPeers {
		style = activePanel
	}
	innerW := clamp(w-4, 0, w)
	items := m.buildPanelItems()

	var rows []string
	rows = append(rows, senderStyle.Render("Peers"))
	rows = append(rows, strings.Repeat("─", innerW))

	for i, item := range items {
		cursor := "  "
		if i == m.peerCursor && m.focus == focusPeers {
			cursor = "> "
		}
		active := " "
		if item.id == m.activeChatID {
			active = myMsgStyle.Render("*")
		}

		var nameStr string
		switch item.kind {
		case itemGlobal:
			nameStr = senderStyle.Render("Global Chat")
		case itemPeer:
			if item.state == core.PeerConnected {
				nameStr = peerOnlineStyle.Render("● " + item.name)
			} else {
				nameStr = peerOfflineStyle.Render("○ " + item.name)
			}
		case itemSeparator:
			rows = append(rows, timeStyle.Render("  ─ Groups ─"))
			continue
		case itemGroup:
			nameStr = senderStyle.Render("# " + item.name)
		}

		unreadStr := ""
		if item.unread > 0 {
			unreadStr = timeStyle.Render(fmt.Sprintf(" (%d)", item.unread))
		}
		rows = append(rows, cursor+active+" "+nameStr+unreadStr)
	}

	return style.Width(w).Height(m.bodyHeight()).Render(strings.Join(rows, "\n"))
}

func (m Model) renderChat(w int, title, encTag string) string {
	style := panelStyle
	if m.focus == focusChat {
		style = activePanel
	}

	// Full-screen invite selection mode.
	if m.mode == modeInvitePeer {
		return m.renderInviteScreen(w, style)
	}

	chatHeader := senderStyle.Render("Chat: "+title) + encTag
	sep := strings.Repeat("─", clamp(w-4, 0, w))

	var inputView string
	switch m.mode {
	case modeCreateGroup:
		inputView = inputPromptStyle.Render("Group name: ") + m.groupInput.View()
	case modeSendFile:
		inputView = inputPromptStyle.Render("File path: ") + m.fileInput.View()
	default:
		inputView = inputPromptStyle.Render("> ") + m.input.View()
	}

	content := lipgloss.JoinVertical(lipgloss.Left,
		chatHeader,
		m.viewport.View(),
		sep,
		inputView,
	)
	return style.Width(w).Height(m.bodyHeight()).Render(content)
}

// ─── Invite selection screen ─────────────────────────────────────────────────

func (m Model) renderInviteScreen(w int, style lipgloss.Style) string {
	innerW := clamp(w-4, 0, w)

	// Header with group name.
	groupName := "Group"
	if isGroupChat(m.activeChatID) {
		gid := groupIDFromChat(m.activeChatID)
		if g := m.node.GroupByID(gid); g != nil {
			groupName = g.Name
		}
	}

	var rows []string
	rows = append(rows, senderStyle.Render(fmt.Sprintf("Invite to: %s", groupName)))
	rows = append(rows, strings.Repeat("─", innerW))
	rows = append(rows, "")

	candidates := m.inviteCandidates()
	if len(candidates) == 0 {
		rows = append(rows, systemMsgStyle.Render("  No connected peers available to invite."))
		rows = append(rows, "")
		rows = append(rows, timeStyle.Render("  Press Esc to go back."))
	} else {
		rows = append(rows, timeStyle.Render("  Select a peer to invite:"))
		rows = append(rows, "")
		for i, p := range candidates {
			cursor := "    "
			if i == m.inviteCursor {
				cursor = "  " + myMsgStyle.Render("> ")
			}
			rows = append(rows, cursor+peerOnlineStyle.Render("● "+p.DisplayName))
		}
		rows = append(rows, "")
		rows = append(rows, strings.Repeat("─", innerW))
		rows = append(rows, timeStyle.Render("  ↑↓ select   Enter confirm   Esc cancel"))
	}

	return style.Width(w).Height(m.bodyHeight()).Render(strings.Join(rows, "\n"))
}

// ─── Panel items builder ─────────────────────────────────────────────────────

func (m Model) buildPanelItems() []panelItem {
	globalUnread := 0
	if cs := m.chats[""]; cs != nil {
		globalUnread = cs.unread
	}
	items := []panelItem{{kind: itemGlobal, id: "", name: "Global Chat", unread: globalUnread}}

	// Peers (connected first, then offline, alphabetical).
	peers := m.node.Peers()
	sort.Slice(peers, func(i, j int) bool {
		if peers[i].State != peers[j].State {
			return peers[i].State == core.PeerConnected
		}
		return peers[i].DisplayName < peers[j].DisplayName
	})
	for _, p := range peers {
		unread := 0
		if cs := m.chats[p.ID]; cs != nil {
			unread = cs.unread
		}
		items = append(items, panelItem{
			kind:   itemPeer,
			id:     p.ID,
			name:   p.DisplayName,
			state:  p.State,
			unread: unread,
		})
	}

	// Groups.
	groups := m.node.Groups()
	if len(groups) > 0 {
		items = append(items, panelItem{kind: itemSeparator})
		sort.Slice(groups, func(i, j int) bool { return groups[i].Name < groups[j].Name })
		for _, g := range groups {
			chatID := groupChatID(g.ID)
			unread := 0
			if cs := m.chats[chatID]; cs != nil {
				unread = cs.unread
			}
			items = append(items, panelItem{kind: itemGroup, id: chatID, name: g.Name, unread: unread})
		}
	}
	return items
}

// ─── State helpers ───────────────────────────────────────────────────────────

func (m Model) toggleFocus() Model {
	if m.focus == focusChat {
		m.focus = focusPeers
		m.input.Blur()
	} else {
		m.focus = focusChat
		m.input.Focus()
	}
	return m
}

func (m Model) switchChat(id string) Model {
	m.activeChatID = id
	if m.chats[id] == nil {
		m.chats[id] = &chatStore{}
	}
	cs := m.chats[id]
	cs.unread = 0
	m.viewport.SetContent(strings.Join(cs.lines, "\n"))
	m.viewport.GotoBottom()
	return m
}

func (m *Model) sendForActiveChat(text string) {
	if isGroupChat(m.activeChatID) {
		gid := groupIDFromChat(m.activeChatID)
		m.node.SendGroup(text, gid)
	} else {
		m.node.Send(text, m.activeChatID)
	}
}

func (m Model) appendMessage(msg core.Message) Model {
	chatID := chatIDForMsg(msg, m.node.ID())

	ts := timeStyle.Render(msg.Timestamp.Format("15:04"))
	var line string
	switch msg.Type {
	case core.MsgTypeText, core.MsgTypeDirect, core.MsgTypeGroupText:
		var nameS string
		if msg.PeerID == m.node.ID() {
			nameS = myMsgStyle.Render("You")
		} else {
			nameS = senderStyle.Render(msg.Name)
		}
		line = fmt.Sprintf("%s %s: %s", ts, nameS, theirMsgStyle.Render(msg.Content))
	default:
		return m
	}

	cs := m.chats[chatID]
	if cs == nil {
		cs = &chatStore{}
		m.chats[chatID] = cs
	}
	cs.lines = append(cs.lines, line)

	if chatID == m.activeChatID {
		m.viewport.SetContent(strings.Join(cs.lines, "\n"))
		m.viewport.GotoBottom()
	} else {
		cs.unread++
	}
	return m
}

func (m Model) handlePeerEvent(ev core.PeerEvent) Model {
	var notice string
	switch ev.Kind {
	case core.PeerJoined:
		notice = systemMsgStyle.Render(
			fmt.Sprintf("  %s joined  (%s)", ev.Peer.DisplayName, ev.Peer.ID[:8]))
		if m.chats[ev.Peer.ID] == nil {
			m.chats[ev.Peer.ID] = &chatStore{}
		}
	case core.PeerLeft:
		notice = systemMsgStyle.Render(fmt.Sprintf("  %s left", ev.Peer.DisplayName))
	}
	if notice != "" {
		m = m.addNoticeToChat("", notice)
	}
	return m
}

func (m Model) handleGroupEvent(ev core.GroupEvent) Model {
	chatID := groupChatID(ev.Group.ID)
	if m.chats[chatID] == nil {
		m.chats[chatID] = &chatStore{}
	}

	var notice string
	switch ev.Kind {
	case core.GroupCreated:
		notice = systemMsgStyle.Render(fmt.Sprintf("  Group %q created", ev.Group.Name))
	case core.GroupMemberJoined:
		name := ev.PeerName
		if name == "" {
			name = ev.PeerID[:8]
		}
		notice = systemMsgStyle.Render(fmt.Sprintf("  %s joined the group", name))
	case core.GroupMemberLeft:
		name := ev.PeerName
		if name == "" {
			name = ev.PeerID[:8]
		}
		notice = systemMsgStyle.Render(fmt.Sprintf("  %s left the group", name))
	case core.GroupDeleted:
		notice = systemMsgStyle.Render(fmt.Sprintf("  Group %q deleted", ev.Group.Name))
	}

	if notice != "" {
		m = m.addNoticeToChat(chatID, notice)
	}
	return m
}

func (m Model) addNoticeToChat(chatID, notice string) Model {
	cs := m.chats[chatID]
	if cs == nil {
		cs = &chatStore{}
		m.chats[chatID] = cs
	}
	cs.lines = append(cs.lines, notice)
	if chatID == m.activeChatID {
		m.viewport.SetContent(strings.Join(cs.lines, "\n"))
		m.viewport.GotoBottom()
	} else {
		cs.unread++
	}
	return m
}

// chatIDForMsg returns the key in m.chats where msg should be displayed.
func chatIDForMsg(msg core.Message, myID string) string {
	// Group messages go to the group chat.
	if msg.GroupID != "" {
		return groupChatID(msg.GroupID)
	}
	// Global broadcast.
	if msg.To == "" {
		return ""
	}
	// Direct: sent by me → recipient's chat; received → sender's chat.
	if msg.PeerID == myID {
		return msg.To
	}
	return msg.PeerID
}

// ─── Cursor helpers ──────────────────────────────────────────────────────────

func (m Model) skipSeparatorUp(target int) int {
	if target < 0 {
		return 0
	}
	items := m.buildPanelItems()
	if target < len(items) && items[target].kind == itemSeparator {
		target--
	}
	if target < 0 {
		return 0
	}
	return target
}

func (m Model) skipSeparatorDown(target, total int) int {
	if target >= total {
		return total - 1
	}
	items := m.buildPanelItems()
	if target < len(items) && items[target].kind == itemSeparator {
		target++
	}
	if target >= total {
		return total - 1
	}
	return target
}

// ─── Layout helpers ──────────────────────────────────────────────────────────

func (m Model) resize() Model {
	_, chatW := m.panelWidths()
	vpW := clamp(chatW-4, 1, chatW)
	vpH := clamp(m.bodyHeight()-2-1-1-m.input.Height(), 1, m.bodyHeight())

	if !m.ready {
		m.viewport = viewport.New(vpW, vpH)
		m.input.SetWidth(vpW)
		m.groupInput.SetWidth(vpW)
		m.fileInput.SetWidth(vpW)
		m.ready = true
	} else {
		m.viewport.Width = vpW
		m.viewport.Height = vpH
		m.input.SetWidth(vpW)
		m.groupInput.SetWidth(vpW)
		m.fileInput.SetWidth(vpW)
	}

	if cs := m.chats[m.activeChatID]; cs != nil {
		m.viewport.SetContent(strings.Join(cs.lines, "\n"))
		m.viewport.GotoBottom()
	}
	return m
}

func (m Model) panelWidths() (peersW, chatW int) {
	total := m.width
	if total < 40 {
		total = 40
	}
	peersW = 24
	chatW = total - peersW
	return
}

func (m Model) bodyHeight() int {
	h := m.height - 4
	if h < 8 {
		h = 8
	}
	return h
}

// ─── Group chat ID helpers ───────────────────────────────────────────────────

const groupChatPrefix = "group:"

func groupChatID(groupID string) string    { return groupChatPrefix + groupID }
func groupIDFromChat(chatID string) string { return strings.TrimPrefix(chatID, groupChatPrefix) }
func isGroupChat(chatID string) bool       { return strings.HasPrefix(chatID, groupChatPrefix) }

func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
