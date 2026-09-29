import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Second time zone label for the bar, meant to sit beside the stock clock:
// the stock widget owns local time and its calendar, this one owns the
// other zone — US Central by default, any IANA zone by configuration.
//
// Left click — a trackpad tap too, same button — opens the searchable zone
// menu (same picker as `omarchy menu timezone`, minus its sudo: this
// renames only this widget, never the system); right click walks the
// format ring; middle click copies both clocks. Each choice is written
// back to shell.json, so what the bar shows is what the config keeps.
BarWidget {
  id: root
  moduleName: "kshitij.dual-clock"

  readonly property string configuredTimezone: String(setting("timezone", "America/Chicago"))
  readonly property string configuredFormat: String(setting("format", "HH:mm"))
  readonly property string verticalFormat: String(setting("verticalFormat", "HH\nmm"))
  readonly property string configuredLabel: String(setting("label", ""))

  // A hand-edited zone that is not a zone never reaches the TZ variable;
  // the label falls back to the default rather than to nothing.
  readonly property string timezone: Model.isValidTimezone(configuredTimezone)
    ? configuredTimezone
    : "America/Chicago"

  readonly property string activeFormat: vertical ? verticalFormat : configuredFormat

  property date displayDate: clock.date
  // Minutes east of UTC from the last `date` reading; null until it lands,
  // which is also the widget's only honest state before it knows the zone.
  property var zoneOffset: null
  property string zoneAbbrev: ""
  property bool zonePending: false

  readonly property string zoneTime: zoneOffset === null
    ? ""
    : Qt.formatDateTime(Model.shiftedDate(displayDate, zoneOffset), activeFormat)
  // A configured label wins over the database's abbreviation, for anyone
  // who wants a stable "CST" that does not become "CDT" in April.
  readonly property string suffix: configuredLabel !== "" ? configuredLabel : zoneAbbrev

  // Vertical: the suffix gets its own stacked line, so "08 CDT" can't clip
  // to "08 CD" in the 28px slot (the time itself is already stacked by
  // activeFormat's verticalFormat, "HH\nmm"). Horizontal: the suffix rides
  // on the last line, "08:54 CDT".
  readonly property var displayLines: {
    var lines = zoneTime === "" ? [] : zoneTime.split("\n")
    if (suffix === "") return lines
    if (vertical) return lines.concat([suffix])
    if (lines.length === 0) return [suffix]
    lines[lines.length - 1] = lines[lines.length - 1] + " " + suffix
    return lines
  }
  readonly property string displayText: displayLines.join("\n")
  // Vertical display is abbreviated (no weekday, no colon), so hover spells
  // out the configured full time, the zone abbreviation and the zone id.
  readonly property string hoverText: {
    if (!vertical || suffix === "") return root.timezone
    var t = zoneOffset === null
      ? ""
      : Qt.formatDateTime(Model.shiftedDate(displayDate, zoneOffset), configuredFormat)
    if (t === "") return root.timezone
    return t + " " + suffix + " · " + root.timezone
  }

  // Re-run the lookup whenever the zone changes; a reading still in
  // flight is answered by the completion hook rather than dropped.
  function refreshZone() {
    if (!zoneProc || zoneProc.running) {
      zonePending = true
      return
    }
    zonePending = false
    zoneProc.command = ["env", "TZ=" + timezone, "date", "+%z %Z"]
    zoneProc.running = true
  }

  function refresh() {
    displayDate = new Date()
    refreshZone()
  }

  // Persist through the same inline path the stock clock uses: applied
  // locally first so the label moves on the click itself, then confirmed
  // when the shell.json write comes back through the bar.
  function persist(key, value) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    entry[key] = value

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function cycleFormat() {
    var values = Model.ring(configuredFormat, Model.FORMAT_PRESETS)
    var next = Model.nextInRing(values, configuredFormat)
    if (next === "" || next === configuredFormat) return
    persist("format", next)
  }

  function cycleTimezone() {
    var values = Model.ring(timezone, Model.TIMEZONE_PRESETS)
    var next = Model.nextInRing(values, timezone)
    if (next === "" || next === timezone) return
    persist("timezone", next)
    // settings re-reads above synchronously, so timezone is already next;
    // refreshZone() runs from its change handler too, this just narrows the
    // window when the property happened not to change identity.
    refreshZone()
  }

  function copyTimes() {
    var local = Qt.formatDateTime(displayDate, "HH:mm")
    // displayText may span lines in vertical mode; clipboard wants one line.
    var flat = displayText.split("\n").join(" ")
    var payload = flat === "" ? local : local + " · " + flat
    Quickshell.execDetached(["omarchy-clipboard-paste-text", "--copy-only", payload])
    Quickshell.execDetached(["omarchy-notification-send", "Times Copied", payload])
  }

  // Full IANA list through the stock menu, written into this widget's own
  // setting on return. A dismissed menu yields no line and changes nothing;
  // the picked zone is validated before it ever reaches shell.json.
  function pickTimezone() {
    if (pickZoneProc.running) return
    pickZoneProc.running = true
  }

  onTimezoneChanged: if (zoneProc) refreshZone()

  Component.onCompleted: refreshZone()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.displayDate = date
  }

  Process {
    id: zoneProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split(/\s+/)
        var offset = Model.parseOffset(parts[0])
        // A failed or unparseable run leaves the last good reading in
        // place instead of blanking a clock that was right a moment ago.
        if (offset === null) return
        root.zoneOffset = offset
        root.zoneAbbrev = Model.cleanAbbrev(parts[1])
      }
    }
    onRunningChanged: {
      if (!running && root.zonePending) root.refreshZone()
    }
  }

  Process {
    id: pickZoneProc
    // `bash -l` for the PATH/session env GUI processes otherwise lack, so
    // the menu script and timedatectl resolve the same as from a terminal.
    command: ["bash", "-lc", "timedatectl list-timezones | omarchy-menu-select 'Dual Clock zone' -- --width 520 --maxheight 520"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var zone = String(text || "").trim()
        if (zone === "" || !Model.isValidTimezone(zone)) return
        // settings re-reads synchronously, so onTimezoneChanged above
        // re-asks `date` for the new offset in the same event loop turn.
        root.persist("timezone", zone)
      }
    }
  }

  // The offset only moves at a DST transition, but re-asking costs one
  // `date` and needs no transition table: worst case the label is correct
  // one minute late in April and October.
  Timer {
    interval: 600000
    repeat: true
    running: true
    onTriggered: root.refreshZone()
  }

  visible: displayText !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? root.displayLines.length > 0 : text !== ""
    fixedHeight: root.vertical ? root.displayLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.hoverText
    onPressed: function(b) {
      if (b === Qt.LeftButton) root.pickTimezone()
      else if (b === Qt.RightButton) root.cycleFormat()
      else if (b === Qt.MiddleButton) root.copyTimes()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.displayLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3 ? button.fontSize * 0.9 : button.fontSize
          color: button.foreground
        }
      }
    }
  }

  IpcHandler {
    target: "kshitij.dual-clock"

    function refresh(): void { root.broadcast("refresh") }
    function cycleFormat(): void { root.cycleFormat() }
    function cycleTimezone(): void { root.cycleTimezone() }
    function pickTimezone(): void { root.pickTimezone() }
    function copy(): void { root.copyTimes() }
  }
}
