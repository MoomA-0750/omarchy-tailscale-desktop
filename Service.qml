import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool running: false
  property bool needsLogin: false

  // Optimistic off state so the UI reacts the instant you click, rather than
  // waiting for the next status refresh. _desired is -1 while we just follow
  // the real state, or 0/1 while a toggle is still catching up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  property bool refreshing: false
  property string backendState: "Unknown"
  // statusText answers the IPC status() call, so it stays English.
  property string statusText: "Checking…"  // i18n: ignore
  property string selfName: ""
  property string selfDnsName: ""
  property string selfIp: ""
  property string selfUserId: ""
  property bool fileSharing: false
  property string authUrl: ""
  property var peers: []
  property var exitNodes: []
  property var tailnetExitNodes: []
  property var mullvadExitNodes: []
  property var mullvadRegions: []
  property var accounts: []
  property string selectedAccountId: ""
  property string selectedAccountLabel: ""
  property string switchingAccountId: ""
  property string settingExitNodeId: ""
  property bool accountsAccessDenied: false
  // Set when a `tailscale set`/`up`/`down` was refused because this user is
  // not the daemon's operator; the panel then offers the one-time fix.
  property bool operatorNeeded: false
  property string selfIpv6: ""
  property string selfOs: ""
  property string selfKeyExpiry: ""
  property string selfLogin: ""
  property string version: ""
  property string latestVersion: ""
  property var prefs: ({ ok: false })
  property string pendingPref: ""
  property string suggestedExitNode: ""
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property bool busy: whichProcess.running || statusProcess.running || mullvadExitNodesProcess.running || accountsProcess.running || actionProcess.running || loginProcess.running || switchProcess.running || operatorProcess.running || exitNodeProcess.running || prefSetProcess.running
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")

  property string _statusOutput: ""
  property string _statusError: ""
  property string _accountsOutput: ""
  property string _accountsError: ""
  property string _mullvadExitNodesOutput: ""
  property string _mullvadExitNodesError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _loginOutput: ""
  property string _loginError: ""
  property bool _loginInProgress: false
  property bool _loginUrlOpened: false
  property string _preLoginAuthUrl: ""
  property double _lastAccountsRefreshMs: 0
  property string _switchOutput: ""
  property string _switchError: ""
  property string _exitNodeOutput: ""
  property string _exitNodeError: ""
  property string _operatorOutput: ""
  property string _operatorError: ""
  // Change signatures for the big arrays. A 4k-machine tailnet makes every
  // status poll rebuild thousands of delegate rows if the arrays are
  // reassigned unconditionally, so only publish an array whose content
  // actually changed.
  property string _peersSig: "[]"
  property string _tailnetExitNodesSig: "[]"
  property string _exitNodesSig: "[]"
  property string _mullvadRegionsSig: "[]"

  // The full status JSON is ~4.6MB on a 4k-machine tailnet, and the bar icon
  // only needs Self/BackendState. Poll light (--peers=false) while the panel
  // is closed; the panel binds peersWanted and forces a full fetch on open.
  property bool peersWanted: false
  property bool _statusFullPeers: false
  property bool _pendingFullPeers: false
  // False until a full peer fetch has answered, so the panel can tell
  // "still loading" apart from "this tailnet has no machines".
  property bool peersLoaded: false

  function publishPeers(next) {
    var sig = JSON.stringify(next)
    if (sig === _peersSig) return
    _peersSig = sig
    peers = next
  }

  function publishTailnetExitNodes(next) {
    var sig = JSON.stringify(next)
    if (sig === _tailnetExitNodesSig) return
    _tailnetExitNodesSig = sig
    tailnetExitNodes = next
  }

  function syncExitNodes() {
    var next = running ? tailnetExitNodes.concat(mullvadRegions) : []
    var sig = JSON.stringify(next)
    if (sig === _exitNodesSig) return
    _exitNodesSig = sig
    exitNodes = next
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function filterIPv4(ips) {
    return Model.filterIPv4(ips)
  }

  function cleanDnsName(name) {
    return Model.cleanDnsName(name)
  }

  function shortDnsName(name) {
    return Model.shortDnsName(name)
  }

  function displayHostName(hostName, dnsName) {
    return Model.displayHostName(hostName, dnsName, I18n.t)
  }

  function osIcon(os) {
    return Model.osIcon(os)
  }

  function accountLabel(account) {
    return Model.accountLabel(account, I18n.t)
  }

  function copyToClipboard(value, label) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
  }

  function copyPeerIp(peer) {
    if (!peer) return
    var ips = filterIPv4(peer.TailscaleIPs || [])
    copyToClipboard(ips.length > 0 ? ips[0] : "", displayHostName(peer.HostName, peer.DNSName) + " IP")
  }

  function copyPeerName(peer) {
    if (!peer) return
    copyToClipboard(displayHostName(peer.HostName, peer.DNSName), displayHostName(peer.HostName, peer.DNSName) + " name")
  }

  function copyPeerDnsName(peer) {
    if (!peer) return
    copyToClipboard(cleanDnsName(peer.DNSName), displayHostName(peer.HostName, peer.DNSName) + " DNS name")
  }

  function peerAddress(peer) {
    if (!peer) return ""
    if (peer.DNSName) return cleanDnsName(peer.DNSName)
    if (peer.HostName) return String(peer.HostName)
    var ips = filterIPv4(peer.TailscaleIPs || [])
    return ips.length > 0 ? ips[0] : ""
  }

  function canSendFiles(peer) {
    if (!fileSharing || !running || !peer) return false
    return Model.isTaildropTarget(peer, selfUserId)
  }

  function sendFile(peer) {
    if (!canSendFiles(peer)) return
    var target = peerAddress(peer)
    if (target === "") return
    Quickshell.execDetached(["omarchy-tailscale-send", target])
  }

  function refresh(forceAccounts, fullPeers) {
    if (installed) {
      refreshStatusAndAccounts(forceAccounts === true, fullPeers === true)
      return
    }
    if (!whichProcess.running) {
      refreshing = true
      whichProcess.command = ["which", "tailscale"]
      whichProcess.running = true
    }
  }

  function refreshStatusAndAccounts(forceAccounts, fullPeers) {
    if (!installed) return
    var launched = false
    if (!statusProcess.running) {
      _statusOutput = ""
      _statusError = ""
      refreshing = true
      _statusFullPeers = fullPeers === true || peersWanted || _pendingFullPeers
      if (_statusFullPeers) _pendingFullPeers = false
      statusProcess.command = _statusFullPeers
        ? ["tailscale", "status", "--json"]
        : ["tailscale", "status", "--json", "--peers=false"]
      statusProcess.running = true
      launched = true
    } else if ((fullPeers === true || peersWanted) && !_statusFullPeers) {
      // A full-peer request arrived while a light poll is in flight; remember
      // it so the panel is not left stale until the next periodic refresh.
      _pendingFullPeers = true
    }
    if (!mullvadExitNodesProcess.running) {
      _mullvadExitNodesOutput = ""
      _mullvadExitNodesError = ""
      mullvadExitNodesProcess.command = ["tailscale", "exit-node", "list"]
      mullvadExitNodesProcess.running = true
      launched = true
    }
    var now = Date.now()
    var shouldRefreshAccounts = forceAccounts === true || accounts.length === 0 || now - _lastAccountsRefreshMs > 60000
    if (shouldRefreshAccounts && !accountsProcess.running) {
      _accountsOutput = ""
      _accountsError = ""
      _lastAccountsRefreshMs = now
      accountsProcess.command = ["tailscale", "switch", "--list", "--json"]
      accountsProcess.running = true
      launched = true
    }
    // Arm on the launch that needs watching and leave it alone after that.
    // Restarting it every refresh pushes the deadline out ahead of a hung
    // process forever once the refresh interval is shorter than the timeout,
    // and refreshIntervalSec goes down to five seconds.
    if (!prefsProcess.running) {
      prefsProcess.command = ["tailscale", "debug", "prefs"]
      prefsProcess.running = true
      launched = true
    }
    if (launched && !pollWatchdog.running) pollWatchdog.start()
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function resetUnavailable(message) {
    running = false
    needsLogin = false
    _desired = -1
    backendState = "Unavailable"
    statusText = message
    selfName = ""
    selfDnsName = ""
    selfIp = ""
    selfUserId = ""
    fileSharing = false
    authUrl = ""
    publishPeers([])
    publishTailnetExitNodes([])
    peersLoaded = false
    syncExitNodes()
    mullvadExitNodes = []
    mullvadRegions = []
    _mullvadRegionsSig = "[]"
    accounts = []
    selectedAccountId = ""
    selectedAccountLabel = ""
    switchingAccountId = ""
    settingExitNodeId = ""
    accountsAccessDenied = false
  }

  function parseStatus(raw) {
    var parsed = Model.parseStatus(raw, I18n.t)
    if (!parsed.ok) {
      resetUnavailable(parsed.message || "Status error")
      lastError = I18n.t("tailscale.statusParseFailed")
      console.warn("tailscale", parsed.error || "Failed to parse tailscale status")
      return
    }
    if (parsed.unavailable) {
      resetUnavailable(parsed.message || "Disconnected")
      return
    }

    backendState = parsed.backendState
    running = parsed.running
    // Reality caught up to the pending toggle — stop overriding.
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    needsLogin = parsed.needsLogin
    authUrl = parsed.authUrl
    if (needsLogin && _loginInProgress && !_loginUrlOpened && authUrl !== "" && authUrl !== _preLoginAuthUrl) openAuthUrlFrom(authUrl, false)
    selfName = parsed.selfName
    selfDnsName = parsed.selfDnsName
    selfIp = parsed.selfIp
    selfUserId = parsed.selfUserId
    selfIpv6 = parsed.selfIpv6
    selfOs = parsed.selfOs
    selfKeyExpiry = parsed.selfKeyExpiry
    selfLogin = parsed.selfLogin
    version = parsed.version
    latestVersion = parsed.latestVersion
    fileSharing = parsed.fileSharing
    // A light poll carries no peer data — keep the last full machine list
    // while running, and only clear it when tailscale actually went down.
    if (_statusFullPeers) {
      publishPeers(parsed.running ? parsed.peers : [])
      publishTailnetExitNodes(parsed.running ? parsed.exitNodes : [])
      // A stopped tailnet publishes no peers, so a later light poll finding it
      // running again must not read as "fetched, and this tailnet is empty".
      peersLoaded = parsed.running
    } else if (!parsed.running) {
      publishPeers([])
      publishTailnetExitNodes([])
      peersLoaded = false
    }
    syncExitNodes()

    if (needsLogin) statusText = "Needs login"
    else if (running) {
      statusText = "Connected"
      _loginInProgress = false
      _loginUrlOpened = false
      _preLoginAuthUrl = ""
      loginTimeoutTimer.stop()
    } else if (backendState === "Stopped") {
      statusText = "Disconnected"
    } else {
      statusText = backendState
    }
    lastError = ""
  }

  function parseAccounts(raw) {
    var parsed = Model.parseAccounts(raw, I18n.t)
    accounts = parsed.accounts
    selectedAccountId = parsed.selectedAccountId
    selectedAccountLabel = parsed.selectedAccountLabel
    accountsAccessDenied = false
  }

  function parseMullvadExitNodes(raw) {
    // The raw node list is small and nothing hot binds to it, so publish it
    // unconditionally; only the derived regions need the churn guard.
    mullvadExitNodes = Model.parseExitNodeList(raw)
    var nextRegions = Model.mullvadRegionOptions(mullvadExitNodes)
    var sig = JSON.stringify(nextRegions)
    if (sig !== _mullvadRegionsSig) {
      _mullvadRegionsSig = sig
      mullvadRegions = nextRegions
    }
    syncExitNodes()
  }

  function toggleTailscale() {
    if (!installed) return
    if (active) down()
    else loginOrUp()
  }

  function down() {
    // No progress status here — the greyed icon and hero line already convey
    // the optimistic off; only surface a message if the command fails.
    _desired = 0
    runAction(["tailscale", "down"])
  }

  function loginOrUp() {
    if (!installed || loginProcess.running) return
    _desired = -1
    var plan = Model.loginPlan(needsLogin, authUrl)
    if (plan.authUrl !== "") {
      _loginUrlOpened = false
      openAuthUrlFrom(plan.authUrl, true)
      return
    }
    _loginOutput = ""
    _loginError = ""
    if (needsLogin) actionStatus = I18n.t("tailscale.startingLogin")
    else _desired = 1
    _loginInProgress = needsLogin
    _loginUrlOpened = false
    _preLoginAuthUrl = authUrl
    loginProcess.command = plan.command
    loginProcess.running = true
    if (needsLogin) loginTimeoutTimer.restart()
  }

  function switchAccount(id) {
    var accountId = String(id || "")
    if (!installed || accountId === "" || accountId === selectedAccountId || switchProcess.running) return
    _switchOutput = ""
    _switchError = ""
    switchingAccountId = accountId
    switchProcess.command = ["tailscale", "switch", accountId]
    switchProcess.running = true
  }

  function exitNodeTarget(peer) {
    if (!peer) return ""
    if (peer.Mullvad === true) {
      var mullvadIps = filterIPv4(peer.TailscaleIPs || [])
      if (mullvadIps.length > 0) return mullvadIps[0]
    }
    return peerAddress(peer)
  }

  function setExitNode(peer) {
    if (!installed || !running || !peer || exitNodeProcess.running) return
    var active = peer.ExitNode === true
    var target
    // "None" and "Recommended" are the two fixed rows the desktop clients
    // put above the machine list.
    if (peer.NoExitNode === true) target = ""
    else if (peer.AutoExitNode === true) target = active ? "" : "auto:any"
    else target = active ? "" : exitNodeTarget(peer)
    if (!active && target === "" && peer.NoExitNode !== true) return
    _exitNodeOutput = ""
    _exitNodeError = ""
    settingExitNodeId = String(peer.id || "")
    exitNodeProcess.command = ["tailscale", "set", "--exit-node=" + target]
    exitNodeProcess.running = true
  }

  function authorizeTailscaleOperator() {
    if (!installed || operatorProcess.running || userName === "") return
    _operatorOutput = ""
    _operatorError = ""
    actionStatus = I18n.t("tailscale.authorizingOperator")
    operatorProcess.command = ["pkexec", "tailscale", "set", "--operator=" + userName]
    operatorProcess.running = true
  }

  // One `tailscale set --<flag>=<value>`. The switch flips at once from the
  // optimistic prefs copy; the next prefs poll puts the real value back.
  function setPref(key, flag, value) {
    if (!installed || prefSetProcess.running) return
    var next = {}
    for (var k in prefs) next[k] = prefs[k]
    next[key] = value
    prefs = next
    pendingPref = key
    prefSetProcess.command = ["tailscale", "set", "--" + flag + "=" + (value ? "true" : "false")]
    prefSetProcess.running = true
  }

  function suggestExitNode() {
    if (!installed || !running || suggestProcess.running) return
    suggestProcess.running = true
  }

  // Adding an account is a fresh `tailscale login`, which prints an auth URL
  // the existing login path already knows how to open in the browser.
  function addAccount() {
    if (!installed || loginProcess.running) return
    _desired = -1
    _loginOutput = ""
    _loginError = ""
    _loginInProgress = true
    _loginUrlOpened = false
    _preLoginAuthUrl = authUrl
    actionStatus = I18n.t("tailscale.startingLogin")
    loginProcess.command = ["tailscale", "login"]
    loginProcess.running = true
    loginTimeoutTimer.restart()
  }

  function logout() {
    if (!installed) return
    runAction(["tailscale", "logout"])
  }

  function openAdminConsole() {
    Quickshell.execDetached(["omarchy-launch-browser", "https://login.tailscale.com/admin/machines"])
  }

  function openDownloads() {
    Quickshell.execDetached(["omarchy-launch-browser", "https://tailscale.com/download"])
  }

  property string bugReportStatus: ""
  function bugReport() {
    if (!installed || bugReportProcess.running) return
    bugReportStatus = "running"
    bugReportProcess.running = true
  }

  function noteAccessDenied(text) {
    if (/access denied/i.test(String(text || ""))) operatorNeeded = true
  }

  function runAction(command, label) {
    if (actionProcess.running) return
    _actionOutput = ""
    _actionError = ""
    actionStatus = label || ""
    actionProcess.command = command
    actionProcess.running = true
  }

  function openAuthUrlFrom(text, allowFallback) {
    if (_loginUrlOpened) return true
    var match = String(text || "").match(/https?:\/\/\S+/)
    var url = match && match[0] ? match[0] : (allowFallback === true ? authUrl : "")
    if (url !== "") {
      // Turning on ended up needing browser auth — stop pretending we're up.
      _desired = -1
      _loginUrlOpened = true
      _loginInProgress = false
      loginTimeoutTimer.stop()
      Quickshell.execDetached(["omarchy-launch-browser", url])
      return true
    }
    return false
  }

  function handleLoginOutput(data, isError) {
    var text = String(data || "")
    if (isError) _loginError += text + "\n"
    else _loginOutput += text + "\n"
    if (_loginInProgress && !_loginUrlOpened) openAuthUrlFrom(text, false)
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    // After a fresh boot the startup poll usually lands before tailscaled has
    // connected, which left the icon stale until the next periodic refresh.
    // Poll quickly until the service shows up, or give up after ~30 seconds.
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      ticks += 1
      if (root.running || ticks >= 15) startupRamp.running = false
      else root.refresh()
    }
  }

  Timer {
    id: delayedRefresh
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    // Every poll is skipped while its own process is still running, so one that
    // never exits — tailscale can hang on a network that is coming and going —
    // silently stops the panel refreshing at all, and it stays stopped. Reap
    // anything still running well inside the refresh interval so the next tick
    // starts clean.
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      if (statusProcess.running) statusProcess.running = false
      if (mullvadExitNodesProcess.running) mullvadExitNodesProcess.running = false
      if (accountsProcess.running) accountsProcess.running = false
      if (prefsProcess.running) prefsProcess.running = false
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: loginTimeoutTimer
    interval: 10000
    repeat: false
    onTriggered: {
      if (!root._loginInProgress || root._loginUrlOpened) return
      if (!root.openAuthUrlFrom(root.authUrl, true)) {
        root._loginInProgress = false
        root.actionStatus = I18n.t("tailscale.loginLinkUnavailable")
      }
    }
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refreshStatusAndAccounts()
      else {
        root.refreshing = false
        root.resetUnavailable("Not installed")
      }
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.parseStatus(stdout)
      else {
        root.resetUnavailable("Disconnected")
        root.lastError = stderr.trim()
      }
      if (root._pendingFullPeers) {
        root._pendingFullPeers = false
        root.refreshStatusAndAccounts(false, true)
      }
    }
  }

  Process {
    id: accountsProcess
    running: false
    command: []
    stdout: StdioCollector { id: accountsStdout; waitForEnd: true; onStreamFinished: root._accountsOutput = text }
    stderr: StdioCollector { id: accountsStderr; waitForEnd: true; onStreamFinished: root._accountsError = text }
    onExited: function(exitCode) {
      var stdout = String(accountsStdout.text || root._accountsOutput || "")
      var stderr = String(accountsStderr.text || root._accountsError || "")
      if (exitCode === 0) root.parseAccounts(stdout)
      else {
        root.parseAccounts("")
        if (/profiles access denied/i.test(stderr) || /profiles access denied/i.test(stdout)) {
          root.accountsAccessDenied = true
          root.lastError = I18n.t("tailscale.authorizeToShowConnections")
        } else {
          root.lastError = elideStatus(stderr || stdout || I18n.t("tailscale.listConnectionsFailed"))
        }
      }
    }
  }

  Process {
    id: mullvadExitNodesProcess
    running: false
    command: []
    stdout: StdioCollector { id: mullvadExitNodesStdout; waitForEnd: true; onStreamFinished: root._mullvadExitNodesOutput = text }
    stderr: StdioCollector { id: mullvadExitNodesStderr; waitForEnd: true; onStreamFinished: root._mullvadExitNodesError = text }
    onExited: function(exitCode) {
      var stdout = String(mullvadExitNodesStdout.text || root._mullvadExitNodesOutput || "")
      if (exitCode === 0) root.parseMullvadExitNodes(stdout)
      else root.parseMullvadExitNodes("")
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || root._actionOutput || "")
      var stderr = String(actionStderr.text || root._actionError || "")
      if (exitCode !== 0) {
        root._desired = -1
        root.noteAccessDenied(stderr + stdout)
        root.lastError = elideStatus(stderr || stdout || I18n.t("tailscale.commandFailed"))
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: loginProcess
    running: false
    command: []
    stdout: SplitParser { onRead: function(data) { root.handleLoginOutput(data, false) } }
    stderr: SplitParser { onRead: function(data) { root.handleLoginOutput(data, true) } }
    onExited: function(exitCode) {
      var combined = String(root._loginOutput || "") + "\n" + String(root._loginError || "")
      var opened = root.openAuthUrlFrom(combined, true)
      if (exitCode !== 0 && !opened) {
        root._desired = -1
        root._loginInProgress = false
        root.lastError = elideStatus(combined || I18n.t("tailscale.upFailed"))
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else if (!opened) {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: switchProcess
    running: false
    command: []
    stdout: StdioCollector { id: switchStdout; waitForEnd: true; onStreamFinished: root._switchOutput = text }
    stderr: StdioCollector { id: switchStderr; waitForEnd: true; onStreamFinished: root._switchError = text }
    onExited: function(exitCode) {
      var stdout = String(switchStdout.text || root._switchOutput || "")
      var stderr = String(switchStderr.text || root._switchError || "")
      if (exitCode !== 0) {
        root.noteAccessDenied(stderr + stdout)
        root.lastError = elideStatus(stderr || stdout || I18n.t("tailscale.switchFailed"))
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
        root._lastAccountsRefreshMs = 0
      }
      root.switchingAccountId = ""
      delayedRefresh.restart()
    }
  }

  Process {
    id: exitNodeProcess
    running: false
    command: []
    stdout: StdioCollector { id: exitNodeStdout; waitForEnd: true; onStreamFinished: root._exitNodeOutput = text }
    stderr: StdioCollector { id: exitNodeStderr; waitForEnd: true; onStreamFinished: root._exitNodeError = text }
    onExited: function(exitCode) {
      var stdout = String(exitNodeStdout.text || root._exitNodeOutput || "")
      var stderr = String(exitNodeStderr.text || root._exitNodeError || "")
      if (exitCode !== 0) {
        root.noteAccessDenied(stderr + stdout)
        root.lastError = elideStatus(stderr || stdout || I18n.t("tailscale.exitNodeFailed"))
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      root.settingExitNodeId = ""
      delayedRefresh.restart()
    }
  }

  Process {
    id: operatorProcess
    running: false
    command: []
    stdout: StdioCollector { id: operatorStdout; waitForEnd: true; onStreamFinished: root._operatorOutput = text }
    stderr: StdioCollector { id: operatorStderr; waitForEnd: true; onStreamFinished: root._operatorError = text }
    onExited: function(exitCode) {
      var stdout = String(operatorStdout.text || root._operatorOutput || "")
      var stderr = String(operatorStderr.text || root._operatorError || "")
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || I18n.t("tailscale.authorizationFailed"))
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.accountsAccessDenied = false
        root.operatorNeeded = false
        root.lastError = ""
        root.actionStatus = I18n.t("tailscale.operatorAuthorized")
        actionStatusTimer.restart()
        root._lastAccountsRefreshMs = 0
      }
      delayedRefresh.restart()
    }
  }
  Process {
    id: prefsProcess
    running: false
    command: []
    stdout: StdioCollector { id: prefsStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var parsed = Model.parsePrefs(String(prefsStdout.text || ""))
      if (!parsed.ok) return
      // An operator shows up in the prefs as soon as it is set, from here or
      // from a terminal, so the offer to set one can go away by itself.
      if (parsed.operator !== "" && parsed.operator === root.userName) {
        root.operatorNeeded = false
        root.accountsAccessDenied = false
      }
      if (root.pendingPref === "") root.prefs = parsed
    }
  }

  Process {
    id: prefSetProcess
    running: false
    command: []
    stdout: StdioCollector { id: prefSetStdout; waitForEnd: true }
    stderr: StdioCollector { id: prefSetStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var out = String(prefSetStderr.text || "") + String(prefSetStdout.text || "")
      root.pendingPref = ""
      if (exitCode !== 0) {
        root.noteAccessDenied(out)
        root.lastError = elideStatus(out || I18n.t("tailscale.commandFailed"))
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: suggestProcess
    running: false
    command: ["tailscale", "exit-node", "suggest"]
    stdout: StdioCollector { id: suggestStdout; waitForEnd: true }
    onExited: function(exitCode) {
      root.suggestedExitNode = exitCode === 0 ? Model.parseSuggestion(String(suggestStdout.text || "")) : ""
    }
  }

  // `tailscale bugreport` prints a short identifier to give Tailscale
  // support, as the desktop clients' "Bug report" item does; it goes to the
  // clipboard.
  Process {
    id: bugReportProcess
    running: false
    command: ["tailscale", "bugreport"]
    stdout: StdioCollector { id: bugReportStdout; waitForEnd: true }
    stderr: StdioCollector { id: bugReportStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var id = String(bugReportStdout.text || "").trim().substring(0, 200)
      if (exitCode === 0 && /^BUG-[A-Za-z0-9-]+$/.test(id)) {
        root.copyToClipboard(id)
        root.bugReportStatus = id
      } else {
        root.bugReportStatus = "failed"
        root.lastError = elideStatus(String(bugReportStderr.text || "") || I18n.t("tailscale.commandFailed"))
      }
    }
  }
}
