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

  property real wheelAccumulator: 0
  property bool persistQueued: false
  property bool liveQueued: false
  property bool dragging: false

  property string focusId: "tab"
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property string activeTab: root.tab === "touchpad" && !root.state.hasTouchpad ? "mouse" : root.tab
  readonly property var rows: Model.layout(root.activeTab, root.target, root.state)
  readonly property var targets: Model.focusTargets(root.rows)
  readonly property string applyPath: {
    var url = String(Qt.resolvedUrl("apply.py"))
    if (url.indexOf("file://") === 0) url = url.slice(7)
    try { return decodeURIComponent(url) } catch (e) { return url }
  }
  readonly property string glyph: root.activeTab === "touchpad" ? "󰟸" : (root.activeTab === "cursor" ? "󰆽" : "󰍽")

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

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

  function translated(options) {
    return options.map(function(o) { return { value: o.value, label: strings.t(o.labelKey) } })
  }

  function sliderLabel(id, v) {
    var t = Model.sliderText(id, v, Commons.I18n.formatNumber)
    return strings.t(t.key).arg(t.arg)
  }

  function heroMeta() {
    var s = root.state
    if (root.activeTab === "cursor") {
      return [strings.t("tab.cursor").toUpperCase(),
              root.sliderLabel("c.size", s.cursor.size),
              (s.cursor.theme === "default" ? strings.t("theme.default") : s.cursor.theme).toUpperCase()].join(" · ")
    }
    var prefix = root.activeTab === "touchpad" ? "t" : "m"
    var name = root.activeTab === "touchpad" ? strings.t("tab.touchpad")
      : (root.target === "all" ? strings.t("target.all") : root.target)
    var parts = [name.toUpperCase()]
    var speedId = Model.speedId(root.activeTab, root.target, s)
    if (speedId) {
      parts.push(strings.t("accel." + Model.rawValue(s, root.target, prefix + ".accel")).toUpperCase())
      parts.push(root.sliderLabel(speedId, root.value(speedId)))
    }
    return parts.join(" · ")
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
    root.state = Model.withValue(root.state, root.target, id, v)
    root.dragging = mode === "live"
    queueApply(mode || "apply")
  }

  function toggleValue(id) {
    setValue(id, !root.value(id))
  }

  function focusTarget() {
    var idx = Model.findTarget(root.targets, root.focusId)
    return idx >= 0 ? root.targets[idx] : null
  }

  function focusOn(id, index) {
    root.cursorActive = true
    root.focusId = id
    root.selectedIndex = index
  }

  function choiceOptions(id) {
    for (var i = 0; i < root.rows.length; i++) {
      var row = root.rows[i]
      if (row.type === "choice" && row.id === id) return row.options
      if (row.type === "pair")
        for (var j = 0; j < row.items.length; j++) if (row.items[j].id === id) return row.items[j].options
    }
    return []
  }

  function moveCursor(delta) {
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
    var t = focusTarget()
    if (!t) return
    if (t.kind === "slider") {
      var spec = Model.sliderSpec(t.id)
      setValue(t.id, Number(root.value(t.id)) + delta * spec.step)
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

  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
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

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (!opened) return
    refresh()
    root.focusId = "tab"
    root.selectedIndex = 0
    root.cursorActive = false
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
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(720))

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
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(8)

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
                case "slider": return sliderRow
                case "choice": return choiceRow
                case "pair": return pairRow
                case "toggles": return togglesRow
                case "dropdown": return dropdownRow
                case "header": return headerRow
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
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.title
    }
  }

  Component {
    id: sliderRow
    SliderSection {
      width: parent ? parent.width : 0
      row: parent ? parent.row : ({})
    }
  }

  Component {
    id: choiceRow
    ChoiceSection {
      width: parent ? parent.width : 0
      row: parent ? parent.row : ({ options: [] })
    }
  }

  Component {
    id: pairRow
    Row {
      id: pair
      property var row: parent ? parent.row : ({ items: [] })
      width: parent ? parent.width : 0
      spacing: Style.space(10)
      Repeater {
        model: pair.row.items
        ChoiceSection {
          required property var modelData
          width: (pair.width - pair.spacing) / 2
          row: modelData
        }
      }
    }
  }

  Component {
    id: togglesRow
    Grid {
      id: grid
      property var row: parent ? parent.row : ({ items: [] })
      width: parent ? parent.width : 0
      columns: 2
      columnSpacing: Style.space(8)
      rowSpacing: Style.space(4)
      readonly property real cellWidth: (width - columnSpacing) / 2
      Repeater {
        model: grid.row.items
        CompactToggle {
          required property var modelData
          width: grid.cellWidth
          toggleId: modelData.id
          label: strings.t(modelData.labelKey)
        }
      }
    }
  }

  Component {
    id: dropdownRow
    Column {
      id: dd
      property var row: parent ? parent.row : ({})
      width: parent ? parent.width : 0
      spacing: Style.space(4)
      PanelSectionHeader {
        text: strings.t(dd.row.labelKey || "")
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
      }
      Dropdown {
        id: dropdown
        width: dd.width
        showLabel: false
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
    id: headerRow
    PanelSectionHeader {
      property var row: parent ? parent.row : ({})
      topPadding: Style.space(6)
      text: strings.t(row.labelKey || "")
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }
  }

  Component {
    id: noteRow
    Text {
      property var row: parent ? parent.row : ({})
      width: parent ? parent.width : 0
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: strings.t(row.labelKey || "")
      color: Qt.darker(root.bar.foreground, 1.4)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component SliderSection: Column {
    id: sliderSection
    property var row: ({})
    readonly property string sid: row.id || ""
    readonly property var spec: Model.sliderSpec(sid)

    spacing: Style.space(2)

    Item {
      width: parent.width
      implicitHeight: Math.max(header.implicitHeight, valueLabel.implicitHeight)

      PanelSectionHeader {
        id: header
        text: strings.t(sliderSection.row.labelKey || "")
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: valueLabel
        textFormat: Text.PlainText
        text: root.sliderLabel(sliderSection.sid, slider.dragging ? slider.liveValue : root.value(sliderSection.sid))
        color: Qt.darker(root.bar.foreground, 1.4)
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
        value: Number(root.value(sliderSection.sid))
        onMoved: function(v) { root.setValue(sliderSection.sid, v, "live") }
        onReleased: function(v) { root.setValue(sliderSection.sid, v, "apply") }
      }

      HoverHandler {
        onHoveredChanged: if (hovered) root.focusOn(sliderSection.sid, 0)
      }
    }
  }

  component ChoiceSection: Column {
    id: choiceSection
    property var row: ({ options: [] })
    readonly property string cid: row.id || ""
    readonly property var options: root.translated(row.options || [])

    spacing: Style.space(4)

    PanelSectionHeader {
      text: strings.t(choiceSection.row.labelKey || "")
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }

    Grid {
      id: choiceGrid
      width: parent.width
      columns: Math.max(1, choiceSection.options.length)
      spacing: Style.spacing.xs
      readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

      Repeater {
        model: choiceSection.options

        Button {
          required property var modelData
          required property int index
          width: choiceGrid.cellWidth
          text: modelData.label
          fontSize: Style.font.caption
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.sm
          verticalPadding: Style.space(4)
          bordered: true
          selected: String(root.value(choiceSection.cid)) === String(modelData.value)
          hasCursor: root.hasCursor(choiceSection.cid, index)
          onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
          onClicked: root.setValue(choiceSection.cid, modelData.value)
          onHovered: function(isHovered) { if (isHovered) root.focusOn(choiceSection.cid, index) }
        }
      }
    }
  }

  component CompactToggle: BorderSurface {
    id: toggleRow
    property string toggleId: ""
    property string label: ""
    readonly property bool checked: root.value(toggleId) === true

    implicitHeight: Style.space(32)
    radius: Style.cornerRadius
    color: "transparent"
    borderSpec: Border.controlSpec(
      root.hasCursor(toggleId) || mouseArea.containsMouse ? "hover-cursor" : "normal",
      root.bar.foreground, Color.accent)

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        text: toggleRow.label
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
        width: parent.width - switchControl.implicitWidth - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
      }

      ToggleSwitch {
        id: switchControl
        checked: toggleRow.checked
        interactive: false
        trackHeight: Style.space(16)
        foreground: root.bar.foreground
        accent: Color.accent
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.focusOn(toggleRow.toggleId, 0)
      onClicked: root.toggleValue(toggleRow.toggleId)
    }
  }
}
