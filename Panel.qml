import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The calendar popup: Omarchy's month grid with ISO week numbers, and under
// it your Proton Calendar events.
//
//   Hero        today, centered; clicking it comes back to today
//   Year rail   how much of the year is gone
//   Month grid  a dot under each day with events, in its calendars' colors;
//               click a day to see it below
//   Agenda      the chosen day's events, then what is coming up this week
//   Calendars   which ones are synced, when, and a form to add one
//
// Chevrons, the scroll wheel and h/l step months, j/k years, t comes back to
// today, s syncs. Clicking an event opens Proton Calendar.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against, and the service holding the events.
Panel {
  id: root
  moduleName: "proton-calendar"
  ipcTarget: "proton-calendar"
  manageIpc: false

  property var anchorItem: null
  property var svc: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen, and the day whose events are listed.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()
  property string selectedKey: todayKey

  // Local noon, so a first of the month with no midnight (Havana, April 2012)
  // still names its own month; UTC would name the previous one west of Greenwich.
  readonly property date viewDate: new Date(viewYear, viewMonth, 1, 12)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()
  readonly property bool viewingToday: viewingCurrentMonth && selectedKey === todayKey

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  // ---- Events.
  readonly property var events: root.svc ? root.svc.events : []
  readonly property var calendars: root.svc ? root.svc.calendars : []
  readonly property bool hasCalendars: root.calendars.length > 0
  readonly property string openUrl: String(setting("openUrl", "https://calendar.proton.me"))
  property bool adding: false

  // Day key -> distinct calendar colors with an event that day, for the dots.
  // Walks only the six weeks on screen.
  readonly property var dotsByDay: {
    var out = {}
    if (root.weeks.length === 0) return out
    var first = root.weeks[0].days[0]
    var gridStart = new Date(first.year, first.month, first.day).getTime()
    var gridEnd = gridStart + 42 * 86400000
    for (var i = 0; i < root.events.length; i++) {
      var e = root.events[i]
      if (e.start >= gridEnd) break
      if (e.end <= gridStart) continue
      // An all-day event ends at midnight of the day after; step back a tick
      // so it does not dot that day too.
      var d = new Date(Math.max(e.start, gridStart))
      d.setHours(0, 0, 0, 0)
      var last = Math.min(e.end - 1, gridEnd - 1)
      while (d.getTime() <= last) {
        var key = Model.keyForDate(d)
        var dots = out[key] || []
        if (dots.indexOf(e.color) === -1 && dots.length < 3) dots.push(e.color)
        out[key] = dots
        d.setDate(d.getDate() + 1)
      }
    }
    return out
  }

  readonly property date selectedDate: {
    var parts = root.selectedKey.split("-")
    return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12)
  }
  readonly property var selectedEvents: {
    if (!root.svc) return []
    var start = new Date(root.selectedDate)
    start.setHours(0, 0, 0, 0)
    return root.svc.eventsOn(start.getTime())
  }
  // After today's list: the rest of the week, without repeating today.
  readonly property var upcomingEvents: {
    if (!root.svc || !root.viewingToday) return []
    var tomorrow = new Date(root.today)
    tomorrow.setHours(24, 0, 0, 0)
    return root.svc.upcoming(tomorrow.getTime(), 7, 8)
  }

  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.adding = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
    if (root.svc) root.svc.reload()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
    root.selectedKey = root.todayKey
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
    // Keep a day of the month on screen selected: the same date, or the
    // first if this month is too short, or today when stepping back home.
    if (root.viewingCurrentMonth) {
      root.selectedKey = root.todayKey
    } else {
      var day = Math.min(root.selectedDate.getDate(), new Date(next.year, next.month + 1, 0).getDate())
      root.selectedKey = Model.dateKey(next.year, next.month, day)
    }
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  function selectDay(cell) {
    if (!cell.inMonth) {
      root.viewYear = cell.year
      root.viewMonth = cell.month
    }
    root.selectedKey = cell.key
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  function dayHeading(date) {
    if (Model.keyForDate(date) === root.todayKey) return "TODAY"
    var tomorrow = new Date(root.today)
    tomorrow.setDate(tomorrow.getDate() + 1)
    if (Model.keyForDate(date) === Model.keyForDate(tomorrow)) return "TOMORROW"
    return Qt.formatDate(date, "dddd d MMMM").toUpperCase()
  }

  function timeLabel(e, dayStartMs) {
    if (e.allDay) return "All day"
    var start = new Date(e.start)
    var end = new Date(e.end)
    // A timed event running over midnight: say where this day's part starts or ends.
    var from = e.start < dayStartMs ? "…" : Qt.formatTime(start, "HH:mm")
    var to = e.end > dayStartMs + 86400000 ? "…" : Qt.formatTime(end, "HH:mm")
    return e.end === e.start ? from : from + " – " + to
  }

  function syncedLabel() {
    if (!root.svc) return ""
    if (root.svc.syncing) return "Syncing…"
    if (!root.svc.syncedAt) return "Not synced yet"
    var mins = Math.round((Date.now() - root.svc.syncedAt) / 60000)
    if (mins < 1) return "Synced just now"
    if (mins < 60) return "Synced " + mins + " min ago"
    return "Synced at " + Qt.formatTime(new Date(root.svc.syncedAt), "HH:mm")
  }

  function openCalendar() {
    if (root.openUrl === "") return
    Quickshell.execDetached(["xdg-open", root.openUrl])
    root.close()
  }

  function startAdding() {
    root.adding = true
    Qt.callLater(function() {
      nameField.text = ""
      urlField.text = ""
      nameField.forceActiveFocus()
    })
  }

  function cancelAdding() {
    root.adding = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function commitAdding() {
    var name = nameField.text.trim()
    var url = urlField.text.trim()
    if (name === "" || url === "") return
    if (root.svc) root.svc.addCalendar(name, url)
    root.cancelAdding()
  }

  // Shared by both fields: Tab hops to the other one, Enter adds, Escape drops.
  function handleAddKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelAdding()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitAdding()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingToday
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.adding
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
        else if ((t === "s" || t === "S") && root.svc) root.svc.sync()
        else if (t === "o" || t === "O") root.openCalendar()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          // Never narrower than the grid. The popup width is capped to what
          // the screen allows, and a fixed seven-column grid would otherwise
          // lose its last days off the edge instead of scrolling.
          width: Math.max(calendarScroll.width, gridColumn.width)
          spacing: Style.space(8)

          // ---- Hero: today, centered. Once the view has stepped away
          //      it is also the way home.
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                // Baseline-aligned, not center-aligned: "July 26" carries a
                // descender, so centering the two boxes leaves the icon
                // sitting visibly low against the digits.
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Commons.Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 48
              }

              Text {
                id: heroDate
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.today, "MMMM d")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Commons.Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 52
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingToday
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Year progress, doubling as the rule under the hero.
          Item {
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              Text {
                id: yearLabel
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: yearPercent
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.yearDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Commons.Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ---- Month grid: week numbers down a gutter on the left, then
          //      the seven day columns. Always six rows, so the popup is
          //      exactly as tall in February as it is in August.
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                // Horizontal wheels and touchpad side-scrolls report y === 0;
                // without this they would every one read as "next month".
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                // The week-number heading doubles as the week-start toggle.
                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Commons.Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    textFormat: Text.PlainText
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    textFormat: Text.PlainText
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.week
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      id: cell
                      required property var modelData
                      readonly property bool selected: modelData.key === root.selectedKey
                      readonly property var dots: root.dotsByDay[modelData.key] || []

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius
                      // Today is outlined; the chosen day, when it is not
                      // today, gets a quiet fill.
                      color: cell.selected && !modelData.today
                        ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                        : (cellMouse.containsMouse ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06) : "transparent")
                      border.width: modelData.today ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Commons.Color.accent)

                      Text {
                        textFormat: Text.PlainText
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: cell.dots.length > 0 ? -Style.space(3) : 0
                        text: modelData.day
                        color: modelData.inMonth
                          ? (modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                          : Qt.darker(root.contentForeground, 2.2)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: modelData.today || cell.selected
                      }

                      Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Style.space(4)
                        spacing: Style.space(3)
                        opacity: modelData.inMonth ? 1 : 0.4

                        Repeater {
                          model: cell.dots

                          Rectangle {
                            required property var modelData
                            width: Style.space(4)
                            height: width
                            radius: width / 2
                            color: modelData
                          }
                        }
                      }

                      MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectDay(cell.modelData)
                      }
                    }
                  }
                }
              }
            }

            // Hairline down the week-number gutter, drawn only beside the
            // day rows so it does not cut through the header band.
            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // ---- Month stepping, spanning the grid it drives.
          Item {
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                id: monthLabel
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(130)
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              PanelActionButton {
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }

          // ---- Agenda: the chosen day, then the week ahead.
          Item {
            width: parent.width
            height: agenda.implicitHeight
            visible: root.hasCalendars

            Column {
              id: agenda
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              spacing: Style.space(6)

              PanelSeparator { width: parent.width; foreground: root.contentForeground }

              PanelSectionHeader {
                topPadding: Style.space(4)
                text: root.dayHeading(root.selectedDate)
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              Text {
                visible: root.selectedEvents.length === 0
                textFormat: Text.PlainText
                text: "Nothing planned"
                color: Qt.darker(root.contentForeground, 1.9)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              Repeater {
                model: root.selectedEvents

                EventRow {
                  required property var modelData
                  event: modelData
                  timeText: {
                    var s = new Date(root.selectedDate)
                    s.setHours(0, 0, 0, 0)
                    return root.timeLabel(modelData, s.getTime())
                  }
                }
              }

              PanelSectionHeader {
                visible: root.upcomingEvents.length > 0
                topPadding: Style.space(8)
                text: "COMING UP"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              Repeater {
                model: root.upcomingEvents

                EventRow {
                  required property var modelData
                  event: modelData
                  timeText: Qt.formatDate(new Date(modelData.start), "ddd d") + "  "
                    + (modelData.allDay ? "All day" : Qt.formatTime(new Date(modelData.start), "HH:mm"))
                }
              }
            }
          }

          // ---- Calendars: what is synced, and adding one.
          Item {
            width: parent.width
            height: calendarsBlock.implicitHeight

            Column {
              id: calendarsBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              spacing: Style.space(8)

              PanelSeparator { width: parent.width; foreground: root.contentForeground }

              Text {
                visible: !root.hasCalendars && !root.adding
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: "Add a Proton calendar to see its events here. In Proton Calendar on the web: Settings → Calendars → pick a calendar → Share with anyone → Create link (full view), then paste the link below."
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              // The calendars, each with its color; × forgets one.
              Flow {
                visible: root.hasCalendars
                width: parent.width
                spacing: Style.space(12)

                Repeater {
                  model: root.calendars

                  Row {
                    id: calChip
                    required property var modelData
                    spacing: Style.space(6)

                    Rectangle {
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(8)
                      height: width
                      radius: width / 2
                      color: calChip.modelData.color
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: calChip.modelData.name
                      color: Qt.darker(root.contentForeground, 1.3)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    PanelActionButton {
                      anchors.verticalCenter: parent.verticalCenter
                      opacity: chipHover.hovered ? 1 : 0.25
                      iconText: "󰅖"
                      fontSize: Style.font.caption
                      size: Style.space(18)
                      tooltipText: "Remove " + calChip.modelData.name
                      foreground: root.contentForeground
                      fontFamily: root.contentFontFamily
                      onClicked: if (root.svc) root.svc.removeCalendar(calChip.modelData.name)
                    }

                    HoverHandler { id: chipHover }
                  }
                }
              }

              Repeater {
                model: root.svc ? root.svc.errors : []

                Text {
                  required property var modelData
                  width: calendarsBlock.width
                  textFormat: Text.PlainText
                  wrapMode: Text.Wrap
                  text: modelData.calendar + ": " + modelData.error
                  color: Commons.Color.urgent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                visible: !!root.svc && root.svc.lastError !== ""
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: root.svc ? root.svc.lastError : ""
                color: Commons.Color.urgent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              Column {
                visible: root.adding
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: nameField
                  width: parent.width
                  placeholderText: "Name (Personal, Work…)"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  Keys.onPressed: function(event) { root.handleAddKey(event, urlField) }
                }

                TextField {
                  id: urlField
                  width: parent.width
                  placeholderText: "https://calendar.proton.me/api/calendar/v1/url/…"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  Keys.onPressed: function(event) { root.handleAddKey(event, nameField) }
                }
              }

              Item {
                width: parent.width
                height: Math.max(syncLabel.implicitHeight, actions.implicitHeight)

                Text {
                  id: syncLabel
                  visible: root.hasCalendars
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.opened ? root.syncedLabel() : ""
                  color: Qt.darker(root.contentForeground, 1.9)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                Row {
                  id: actions
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  LinkButton {
                    visible: root.adding
                    text: "Cancel"
                    onClicked: root.cancelAdding()
                  }

                  LinkButton {
                    text: root.adding ? "Add" : "Add calendar"
                    iconText: root.adding ? "" : "󰐕"
                    onClicked: root.adding ? root.commitAdding() : root.startAdding()
                  }

                  LinkButton {
                    visible: root.hasCalendars && !root.adding
                    text: "Sync"
                    iconText: "󰑐"
                    enabled: !!root.svc && !root.svc.syncing
                    onClicked: root.svc.sync()
                  }

                  LinkButton {
                    visible: !root.adding && root.openUrl !== ""
                    text: "Open"
                    iconText: "󰏌"
                    tooltipText: "Open Proton Calendar"
                    onClicked: root.openCalendar()
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // A small text button for secondary actions.
  component LinkButton: Button {
    foreground: Qt.darker(root.contentForeground, 1.3)
    fontFamily: root.contentFontFamily
    fontSize: Style.font.caption
    iconSize: Style.font.caption
    verticalPadding: Style.spacing.xxs
    horizontalPadding: Style.spacing.sm
  }

  // One event: its calendar's color, the time, the title and where.
  component EventRow: Rectangle {
    id: row
    property var event: ({})
    property string timeText: ""
    readonly property bool past: row.event.end <= Date.now()

    width: parent ? parent.width : 0
    height: rowBody.implicitHeight + Style.space(10)
    radius: Math.min(Style.cornerRadius, Style.space(6))
    color: rowMouse.containsMouse ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06) : "transparent"
    opacity: row.past ? 0.5 : 1

    Rectangle {
      id: swatch
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(5)
      width: Style.space(3)
      radius: width / 2
      color: row.event.color || Commons.Color.accent
    }

    Row {
      id: rowBody
      anchors.left: swatch.right
      anchors.leftMargin: Style.space(10)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(12)

      Text {
        id: timeCol
        width: Style.space(110)
        textFormat: Text.PlainText
        text: row.timeText
        color: Qt.darker(root.contentForeground, 1.4)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Column {
        width: rowBody.width - timeCol.width - rowBody.spacing
        spacing: Style.space(1)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.event.title || ""
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          text: row.event.location || ""
          color: Qt.darker(root.contentForeground, 1.7)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: root.openUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.openCalendar()
    }
  }
}
