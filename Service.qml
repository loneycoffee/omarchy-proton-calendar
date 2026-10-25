import QtQuick
import Quickshell
import Quickshell.Io

// The events, mounted once for the shell.
//
// Omarchy builds a bar per monitor; the calendars, their events and the
// reminders live here so every bar shows the same thing and a reminder pops
// up once. bin/pcal does the work: `sync` fetches each calendar's share link
// and expands its events into a cache, `events` reads that cache back.
Item {
  id: root
  width: 0
  height: 0
  visible: false

  // Host injection.
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string ctl: Qt.resolvedUrl("bin/pcal").toString().replace(/^file:\/\//, "")
  // Bundled, as a path: icon-theme names vary between themes, and one the
  // notification popup cannot find shows up as a checkerboard.
  readonly property string icon: Qt.resolvedUrl("icons/calendar.svg").toString().replace(/^file:\/\//, "")

  property var events: []
  property var calendars: []
  property var errors: []
  property double syncedAt: 0
  property bool syncing: false
  property bool loaded: false
  property string lastError: ""

  // Set by the bar widget from its settings; 0 turns reminders off.
  property int reminderMinutes: 10
  property int syncMinutes: 15

  property var _reminded: ({})

  function sync() {
    if (syncProc.running) return
    root.syncing = true
    syncProc.running = true
  }

  function reload() {
    if (!eventsProc.running) eventsProc.running = true
  }

  function addCalendar(name, url) {
    root.lastError = ""
    actionProc.command = [root.ctl, "add", name, url]
    actionProc.running = true
  }

  function removeCalendar(name) {
    root.lastError = ""
    actionProc.command = [root.ctl, "remove", name]
    actionProc.running = true
  }

  // Events that touch the day [dayStart, dayStart + 24h), in start order.
  function eventsOn(dayStart) {
    var dayEnd = dayStart + 86400000
    return root.events.filter(function(e) { return e.start < dayEnd && e.end > dayStart })
  }

  function remind() {
    if (root.reminderMinutes <= 0) return
    var now = Date.now()
    var lead = root.reminderMinutes * 60000
    var seen = root._reminded
    for (var i = 0; i < root.events.length; i++) {
      var e = root.events[i]
      if (e.start > now + lead) break
      if (e.allDay || e.start < now - 60000 || seen[e.key]) continue
      seen[e.key] = true
      var mins = Math.max(0, Math.round((e.start - now) / 60000))
      var when = mins === 0 ? "Now" : "In " + mins + " min"
      var body = when + " · " + Qt.formatTime(new Date(e.start), "HH:mm") + (e.location ? "\n" + e.location : "")
      Quickshell.execDetached(["notify-send", "-a", "Proton Calendar", "-i", root.icon, e.title, body])
    }
    root._reminded = seen
  }

  Process {
    id: syncProc
    command: [root.ctl, "sync"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.syncing = false
        root.reload()
      }
    }
  }

  Process {
    id: eventsProc
    command: [root.ctl, "events"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          root.events = data.events || []
          root.calendars = data.calendars || []
          root.errors = data.errors || []
          root.syncedAt = data.syncedAt || 0
        } catch (e) {
          console.warn("proton-calendar: unreadable event cache")
        }
        root.loaded = true
        root.remind()
      }
    }
  }

  Process {
    id: actionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "") root.lastError = msg.replace(/^pcal:\s*/, "")
      }
    }
    onRunningChanged: if (!running) root.sync()
  }

  Timer {
    interval: Math.max(5, root.syncMinutes) * 60000
    repeat: true
    running: true
    onTriggered: root.sync()
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.remind()
  }

  Component.onCompleted: {
    // Show what was cached right away, then fetch.
    root.reload()
    root.sync()
  }
}
