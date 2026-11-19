import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "t3mon.pointer"
  ipcTarget: "t3mon.pointer"

  property var state: Model.emptyState()
  property string tab: "mouse"
  property string target: "all"
  property var moreOpen: ({})

  property var rows: []
  property string rowsSig: ""
  property real wheelAccumulator: 0
  property bool persistQueued: false
  property bool liveQueued: false
  property bool dragging: false

  property string focusId: "tab"
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool keyboardNav: false

  readonly property string activeTab: root.tab === "touchpad" && !root.state.hasTouchpad ? "mouse" : root.tab
  readonly property var targets: Model.focusTargets(root.rows)
  readonly property string applyPath: {
    var url = String(Qt.resolvedUrl("apply.py"))
    if (url.indexOf("file://") === 0) url = url.slice(7)
    try { return decodeURIComponent(url) } catch (e) { return url }
  }
  readonly property string glyph: root.activeTab === "touchpad" ? "󰟸" : (root.activeTab === "cursor" ? "󰆽" : "󰍽")
  readonly property color muted: Qt.darker(root.bar.foreground, 1.4)
  property var palette: ({})
  readonly property color tint: root.tintFor(root.activeTab)
  readonly property color caution: root.paletteColor("yellow", Color.accent)
  readonly property color danger: root.paletteColor("red", Color.urgent)
  readonly property real controlWidth: Math.round(panelColumn.width * 0.56)

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  FileView {
    id: themeColors
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    onLoaded: root.palette = Model.parsePalette(text())
  }

  Connections {
    target: Color
    function onAccentChanged() { themeColors.reload() }
  }

  function paletteColor(name, fallback) {
    var value = root.palette[name]
    return value ? value : fallback
  }

  readonly property var tints: Model.pickTints(root.palette, String(Color.accent), String(Color.background))

  function tintFor(tab) {
    if (tab === "touchpad" || tab === "cursor") return root.tints[tab]
    return root.tints.mouse
  }

  function soft(c, a) {
    return Qt.rgba(c.r, c.g, c.b, a)
  }

  function rebuildRows() {
    if (root.dragging) return
    var next = Model.layout(root.activeTab, root.target, root.state, root.moreOpen)
    var sig = JSON.stringify(next)
    if (sig === root.rowsSig) return
    root.rowsSig = sig
    root.rows = next
  }

  onStateChanged: rebuildRows()
  onActiveTabChanged: rebuildRows()
  onTargetChanged: rebuildRows()
  onMoreOpenChanged: rebuildRows()
  onDraggingChanged: rebuildRows()

  function value(id) {
    if (id === "tab") return root.activeTab
    if (id === "m.target") return root.target
    return Model.uiValue(root.state, root.target, id)
  }

  function optionList(id) {
    if (id === "m.target") {
      var list = [{ value: "all", label: strings.t("target.all") }]
      root.state.connectedMice.forEach(function(name) { list.push({ value: name, label: name }) })
      return list
    }
    if (id === "c.theme") {
      return root.state.themes.map(function(name) {
        return { value: name, label: name === "default" ? strings.t("theme.default") : name }
      })
    }
    return []
  }

  function tr(key, arg) {
    var s = strings.t(key || "")
    return s.indexOf("%1") >= 0 ? s.arg(arg === undefined ? "" : arg) : s
  }

  function translated(options) {
    return (options || []).map(function(o) { return { value: o.value, label: strings.t(o.labelKey) } })
  }

  function sliderLabel(id, v) {
    var t = Model.sliderText(id, v, Commons.I18n.formatNumber)
    return root.tr(t.key, t.arg)
  }

  function heroMeta() {
    var s = root.state
    if (root.activeTab === "cursor") {
      return [root.sliderLabel("c.size", s.cursor.size),
              (s.cursor.theme === "default" ? strings.t("theme.default") : s.cursor.theme)].join(" · ").toUpperCase()
    }
    var prefix = root.activeTab === "touchpad" ? "t" : "m"
    var name = root.activeTab === "touchpad" ? strings.t("tab.touchpad")
      : (root.target === "all" ? strings.t("target.all") : root.target)
    var parts = [name]
    var speedId = Model.speedId(root.activeTab, root.target, s)
    if (speedId) {
      parts.push(strings.t("accel." + Model.rawValue(s, root.target, prefix + ".accel")))
      parts.push(root.sliderLabel(speedId, root.value(speedId)))
    }
    return parts.join(" · ").toUpperCase()
  }

  function applyParsed(parsed) {
    if (!parsed.ok || root.dragging) return
    root.state = parsed
    if (root.target !== "all" && !(root.target in parsed.mice)) root.target = "all"
  }

  function refresh() {
    if (getProc.running) return
    getProc.command = ["python3", root.applyPath, "get"]
    getProc.running = true
  }

  function queueApply(mode) {
    if (mode === "live") root.liveQueued = true
    else root.persistQueued = true
    if (!setProc.running) flushApply()
  }

  function flushApply() {
    if (!root.persistQueued && !root.liveQueued) return
    var mode = root.persistQueued ? "apply" : "live"
    root.persistQueued = false
    root.liveQueued = false
    setProc.command = ["python3", root.applyPath, mode, Model.statePayload(root.state)]
    setProc.running = true
  }

  function setValue(id, v, mode) {
    if (id === "tab") { root.tab = v; return }
    if (id === "m.target") { root.target = v; return }
    root.dragging = mode === "live"
    root.state = Model.withValue(root.state, root.target, id, v)
    queueApply(mode || "apply")
  }

  function toggleValue(id) {
    setValue(id, !root.value(id))
  }

  function toggleMore(id) {
    var tab = id.replace("more.", "")
    var row = root.rows.filter(function(r) { return r.id === id })[0]
    var next = {}
    for (var k in root.moreOpen) next[k] = root.moreOpen[k]
    next[tab] = !(row && row.open)
    root.moreOpen = next
  }

  function runAction(id) {
    if (id === "c.zoom.reset") setValue("c.zoom", 1)
  }

  function focusTarget() {
    var idx = Model.findTarget(root.targets, root.focusId)
    return idx >= 0 ? root.targets[idx] : null
  }

  function focusOn(id, index) {
    root.keyboardNav = false
    root.cursorActive = true
    root.focusId = id
    root.selectedIndex = index
  }

  function choiceOptions(id) {
    for (var i = 0; i < root.rows.length; i++) if (root.rows[i].id === id) return root.rows[i].options || []
    return []
  }

  function moveCursor(delta) {
    root.keyboardNav = true
    var idx = Model.findTarget(root.targets, root.focusId)
    var next = idx < 0 ? 0 : Math.max(0, Math.min(root.targets.length - 1, idx + (delta > 0 ? 1 : -1)))
    var t = root.targets[next]
    if (!t) return
    root.focusId = t.id
    if (t.kind === "choice") {
      var values = root.choiceOptions(t.id).map(function(o) { return String(o.value) })
      root.selectedIndex = Math.max(0, values.indexOf(String(root.value(t.id))))
    } else {
      root.selectedIndex = 0
    }
  }

  function moveCursorH(delta) {
    root.keyboardNav = true
    var t = focusTarget()
    if (!t) return
    if (t.kind === "slider") {
      setValue(t.id, Number(root.value(t.id)) + delta * Model.sliderSpec(t.id).step)
    } else if (t.kind === "choice") {
      root.selectedIndex = Math.max(0, Math.min(t.count - 1, root.selectedIndex + delta))
    } else if (t.kind === "dropdown") {
      setValue(t.id, Model.nextOption(root.optionList(t.id), root.value(t.id), delta))
    }
  }

  function activateCursor() {
    var t = focusTarget()
    if (!t) return
    if (t.kind === "toggle") toggleValue(t.id)
    else if (t.kind === "more") toggleMore(t.id)
    else if (t.kind === "action") runAction(t.id)
    else if (t.kind === "choice") {
      var options = root.choiceOptions(t.id)
      if (root.selectedIndex >= 0 && root.selectedIndex < options.length) setValue(t.id, options[root.selectedIndex].value)
    } else if (t.kind === "dropdown") {
      setValue(t.id, Model.nextOption(root.optionList(t.id), root.value(t.id), 1))
    }
  }

  function hasCursor(id, index) {
    return root.cursorActive && root.focusId === id && (index === undefined || root.selectedIndex === index)
  }

  function overflowing() {
    return panelColumn.implicitHeight > scrollArea.height + 1
  }

  function resetScroll() {
    var flick = scrollArea.contentItem
    if (flick && flick.contentY !== undefined) flick.contentY = 0
  }

  function ensureCursorVisible(item) {
    if (!item || !scrollArea || !root.keyboardNav) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    if (!root.overflowing()) { flick.contentY = 0; return }
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var margin = 6
    if (pt.y < flick.contentY + margin) flick.contentY = Math.max(0, pt.y - margin)
    else if (pt.y + item.height > flick.contentY + flick.height - margin)
      flick.contentY = pt.y + item.height + margin - flick.height
  }

  function showSpeedOsd(id) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({ icon: root.glyph, value: root.value(id) }))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: { rebuildRows(); refresh() }

  onOpenedChanged: {
    if (!opened) return
    refresh()
    themeColors.reload()
    root.moreOpen = ({})
    root.focusId = "tab"
    root.selectedIndex = 0
    root.cursorActive = false
    root.keyboardNav = false
    root.resetScroll()
  }

  onTargetsChanged: if (Model.findTarget(root.targets, root.focusId) < 0) { root.focusId = "tab"; root.selectedIndex = 0 }

  Process {
    id: getProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyParsed(Model.parseState(text))
    }
  }

  Process {
    id: setProc
    onRunningChanged: if (!running) root.flushApply()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍽"
    tooltipText: strings.t("title")
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      var id = Model.speedId(root.activeTab === "cursor" ? "mouse" : root.activeTab, root.target, root.state)
      if (!id) return
      root.setValue(id, root.value(id) + wheel.steps * 5)
      root.showSpeedOsd(id)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(Math.ceil(panelColumn.implicitHeight) + Style.space(4), Style.space(1000))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: root.overflowing() ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        onHeightChanged: if (!root.overflowing()) root.resetScroll()
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: root.overflowing()
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(6)

          PanelHero {
            width: parent.width
            title: strings.t("title")
            iconSize: Style.font.title
            meta: root.heroMeta()
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconComponent: heroIcon
          }

          Repeater {
            model: root.rows

            Loader {
              required property var modelData
              width: panelColumn.width
              property var row: modelData
              sourceComponent: {
                switch (modelData.type) {
                case "tabs": return tabsRow
                case "section": return sectionRow
                case "slider": return sliderRow
                case "choice": return choiceRow
                case "switch": return switchRow
                case "dropdown": return dropdownRow
                case "more": return moreRow
                case "warning": return warningRow
                case "note": return noteRow
                }
                return null
              }
            }
          }
        }
      }
    }
  }

  Component {
    id: heroIcon
    Text {
      textFormat: Text.PlainText
      text: root.glyph
      color: root.tint
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.title
    }
  }

  Component {
    id: tabsRow
    Segmented {
      width: parent ? parent.width : 0
      sid: "tab"
      perOptionTint: true
      options: root.translated(parent ? parent.row.options : [])
      fontSize: Style.font.body
      padY: Style.space(6)
    }
  }

  Component {
    id: sectionRow
    Column {
      property var row: parent ? parent.row : ({})
      width: parent ? parent.width : 0
      topPadding: Style.space(8)
      spacing: Style.space(8)
      PanelSeparator { foreground: root.bar.foreground }
      PanelSectionHeader {
        leftPadding: Style.space(6)
        text: strings.t(parent.row.labelKey || "")
        foreground: root.tint
        fontFamily: root.bar.fontFamily
      }
    }
  }

  Component {
    id: sliderRow
    Column {
      id: sliderSection
      property var row: parent ? parent.row : ({})
      readonly property string sid: row.id || ""
      readonly property var spec: Model.sliderSpec(sid)
      width: parent ? parent.width : 0
      spacing: Style.space(2)

      Item {
        width: parent.width
        implicitHeight: Math.max(label.implicitHeight, valueLabel.implicitHeight)
        RowLabel {
          id: label
          anchors.left: parent.left
          anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: strings.t(sliderSection.row.labelKey || "")
        }
        Text {
          id: valueLabel
          textFormat: Text.PlainText
          text: root.sliderLabel(sliderSection.sid, slider.dragging ? slider.liveValue : root.value(sliderSection.sid))
          color: root.tint
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      CursorSurface {
        id: sliderBox
        width: parent.width
        height: slider.implicitHeight
        hasCursor: root.hasCursor(sliderSection.sid)
        onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(sliderBox)
        foreground: root.bar.foreground
        accent: root.tint
        outline: true

        PanelSlider {
          id: slider
          bar: root.bar
          anchors.fill: parent
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(6)
          minimum: sliderSection.spec.min
          maximum: sliderSection.spec.max
          step: sliderSection.spec.step
          integer: sliderSection.spec.integer
          fillColor: root.tint
          knobColor: root.tint
          trackColor: root.soft(root.tint, 0.18)
          value: Number(root.value(sliderSection.sid))
          onMoved: function(v) { root.setValue(sliderSection.sid, v, "live") }
          onReleased: function(v) { root.setValue(sliderSection.sid, v, "apply") }
        }

        HoverHandler {
          onHoveredChanged: if (hovered) root.focusOn(sliderSection.sid, 0)
        }
      }
    }
  }

  Component {
    id: choiceRow
    Item {
      id: choiceItem
      property var row: parent ? parent.row : ({})
      width: parent ? parent.width : 0
      implicitHeight: Math.max(Style.space(30), seg.implicitHeight)
      RowLabel {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.right: seg.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: strings.t(choiceItem.row.labelKey || "")
      }
      Segmented {
        id: seg
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: root.controlWidth
        sid: choiceItem.row.id || ""
        options: root.translated(choiceItem.row.options)
      }
    }
  }

  Component {
    id: switchRow
    CursorSurface {
      id: sw
      property var row: parent ? parent.row : ({})
      readonly property string sid: row.id || ""
      readonly property bool checked: root.value(sid) === true
      width: parent ? parent.width : 0
      height: Math.max(Style.space(30), textCol.implicitHeight + Style.space(8))
      radius: Style.cornerRadius
      foreground: root.bar.foreground
      accent: root.tint
      hasCursor: root.hasCursor(sid) || area.containsMouse
      onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(sw)

      Column {
        id: textCol
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.right: toggle.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)
        RowLabel {
          width: parent.width
          text: strings.t(sw.row.labelKey || "")
        }
        Text {
          width: parent.width
          visible: !!sw.row.captionKey
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: sw.row.captionKey ? strings.t(sw.row.captionKey) : ""
          color: root.muted
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Rectangle {
        id: toggle
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(32)
        height: Style.space(18)
        radius: height / 2
        color: sw.checked ? root.soft(root.tint, 0.3) : root.soft(root.bar.foreground, 0.08)
        border.width: 1
        border.color: sw.checked ? root.tint : root.soft(root.bar.foreground, 0.25)
        Behavior on color { ColorAnimation { duration: Style.duration(150); easing.type: Easing.OutCubic } }

        Rectangle {
          width: parent.height - Style.space(6)
          height: width
          radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          x: sw.checked ? parent.width - width - Style.space(3) : Style.space(3)
          color: sw.checked ? root.tint : root.muted
          Behavior on x { NumberAnimation { duration: Style.duration(150); easing.type: Easing.OutCubic } }
        }
      }

      MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.focusOn(sw.sid, 0)
        onClicked: root.toggleValue(sw.sid)
      }
    }
  }

  Component {
    id: dropdownRow
    Item {
      id: dd
      property var row: parent ? parent.row : ({})
      width: parent ? parent.width : 0
      implicitHeight: dropdown.implicitHeight
      RowLabel {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.right: dropdown.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: strings.t(dd.row.labelKey || "")
      }
      Dropdown {
        id: dropdown
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        width: root.controlWidth
        showLabel: false
        accent: root.tint
        fontFamily: root.bar.fontFamily
        options: root.optionList(dd.row.id)
        value: String(root.value(dd.row.id))
        hasCursor: root.hasCursor(dd.row.id)
        onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(dropdown)
        onHovered: function(h) { if (h) root.focusOn(dd.row.id, 0) }
        onChanged: function(v) { root.setValue(dd.row.id, v) }
      }
    }
  }

  Component {
    id: moreRow
    CursorSurface {
      id: moreItem
      property var row: parent ? parent.row : ({})
      width: parent ? parent.width : 0
      height: Style.space(30)
      radius: Style.cornerRadius
      foreground: root.bar.foreground
      accent: root.tint
      hasCursor: root.hasCursor(row.id || "") || moreArea.containsMouse
      onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(moreItem)

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: (moreItem.row.open ? "\uf078   " : "\uf054   ") + strings.t(moreItem.row.labelKey || "")
        color: root.tint
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      MouseArea {
        id: moreArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.focusOn(moreItem.row.id, 0)
        onClicked: root.toggleMore(moreItem.row.id)
      }
    }
  }

  Component {
    id: warningRow
    Rectangle {
      id: warn
      property var row: parent ? parent.row : ({})
      readonly property color level: row.level === "danger" ? root.danger : root.caution
      width: parent ? parent.width : 0
      height: warnRow.implicitHeight + Style.space(12)
      radius: Style.cornerRadius
      color: root.soft(level, 0.12)
      border.width: 1
      border.color: root.soft(level, 0.55)

      Row {
        id: warnRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Text {
          id: warnIcon
          textFormat: Text.PlainText
          text: "\uf071"
          color: warn.level
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          width: parent.width - warnIcon.width - parent.spacing - (action.visible ? action.width + parent.spacing : 0)
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.tr(warn.row.labelKey, warn.row.arg)
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }

        Button {
          id: action
          visible: !!warn.row.action
          text: strings.t("action." + (warn.row.action || ""))
          fontSize: Style.font.caption
          foreground: warn.level
          accent: warn.level
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.sm
          verticalPadding: Style.space(3)
          bordered: true
          hasCursor: root.hasCursor(warn.row.action || "")
          onClicked: root.runAction(warn.row.action)
          onHovered: function(h) { if (h) root.focusOn(warn.row.action, 0) }
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }

  Component {
    id: noteRow
    Text {
      property var row: parent ? parent.row : ({})
      width: parent ? parent.width : 0
      leftPadding: Style.space(6)
      rightPadding: Style.space(6)
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: root.tr(row.labelKey, row.arg)
      color: root.muted
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component RowLabel: Text {
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
  }

  component Segmented: Grid {
    id: segmented
    property string sid: ""
    property var options: []
    property real fontSize: Style.font.caption
    property real padY: Style.space(4)
    property bool perOptionTint: false
    columns: Math.max(1, options.length)
    spacing: Style.spacing.xs
    readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

    Repeater {
      model: segmented.options

      Rectangle {
        id: seg
        required property var modelData
        required property int index
        readonly property color tone: segmented.perOptionTint ? root.tintFor(modelData.value) : root.tint
        readonly property bool selected: String(root.value(segmented.sid)) === String(modelData.value)
        readonly property bool hot: segArea.containsMouse || root.hasCursor(segmented.sid, index)
        width: segmented.cellWidth
        implicitHeight: segLabel.implicitHeight + segmented.padY * 2 + 2
        radius: Style.cornerRadius
        color: selected ? root.soft(tone, hot ? 0.3 : 0.22) : (hot ? root.soft(tone, 0.1) : "transparent")
        border.width: 1
        border.color: selected || hot ? root.soft(tone, selected ? 0.85 : 0.6) : root.soft(root.bar.foreground, 0.18)
        onHotChanged: if (hot && root.hasCursor(segmented.sid, index)) root.ensureCursorVisible(seg)
        Behavior on color { ColorAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

        Text {
          id: segLabel
          anchors.fill: parent
          anchors.leftMargin: Style.space(4)
          anchors.rightMargin: Style.space(4)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: seg.modelData.label
          color: seg.selected ? seg.tone : root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: segmented.fontSize
          font.bold: seg.selected
        }

        MouseArea {
          id: segArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.focusOn(segmented.sid, seg.index)
          onClicked: root.setValue(segmented.sid, seg.modelData.value)
        }
      }
    }
  }
}
