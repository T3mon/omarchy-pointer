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

  property var mouse: Model.mouseDefaults()
  property var touchpad: Model.touchpadDefaults()
  property bool hasTouchpad: false
  property string device: "mouse"

  property real wheelAccumulator: 0
  property bool persistQueued: false
  property bool liveQueued: false

  property string focusSection: "speed"
  property int selectedIndex: -1
  property bool cursorActive: false

  readonly property bool touchpadTab: root.device === "touchpad" && root.hasTouchpad
  readonly property var active: root.touchpadTab ? root.touchpad : root.mouse
  readonly property real speedPercent: Model.speedPercentFromSensitivity(root.active.sensitivity)
  readonly property real scrollPercent: Model.scrollPercentFromFactor(root.active.scrollFactor)
  readonly property var visibleSections: Model.visibleSections(root.device, root.hasTouchpad)
  readonly property string applyPath: {
    var url = String(Qt.resolvedUrl("apply.py"))
    if (url.indexOf("file://") === 0) url = url.slice(7)
    try { return decodeURIComponent(url) } catch (e) { return url }
  }

  readonly property var deviceOptions: [
    { value: "mouse", label: strings.t("device.mouse") },
    { value: "touchpad", label: strings.t("device.touchpad") }
  ]
  readonly property var accelOptions: [
    { value: "adaptive", label: strings.t("accel.adaptive") },
    { value: "flat", label: strings.t("accel.flat") }
  ]
  readonly property var primaryOptions: [
    { value: "left", label: strings.t("primary.left") },
    { value: "right", label: strings.t("primary.right") }
  ]

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function heroMeta() {
    var a = root.active
    var parts = [strings.t(root.touchpadTab ? "device.touchpad" : "device.mouse").toUpperCase(),
                 strings.t("accel." + a.accelProfile).toUpperCase(),
                 Commons.I18n.formatNumber(Math.round(speedSlider.dragging ? speedSlider.liveValue : root.speedPercent)) + "%"]
    if (a.naturalScroll) parts.push(strings.t("meta.natural"))
    if (a.leftHanded) parts.push(strings.t("meta.left"))
    return parts.join(" · ")
  }

  function applyParsed(parsed) {
    if (!parsed.ok) return
    root.mouse = parsed.mouse
    root.touchpad = parsed.touchpad
    root.hasTouchpad = parsed.hasTouchpad
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
    setProc.command = ["python3", root.applyPath, mode, Model.statePayload(root.mouse, root.touchpad)]
    setProc.running = true
  }

  function setField(key, value, mode) {
    if (root.touchpadTab) root.touchpad = Model.withField(root.touchpad, key, value)
    else root.mouse = Model.withField(root.mouse, key, value)
    queueApply(mode || "apply")
  }

  function setSpeed(percent, mode) { setField("sensitivity", Model.sensitivityFromSpeedPercent(percent), mode) }
  function setScroll(percent, mode) { setField("scrollFactor", Model.factorFromScrollPercent(percent), mode) }

  function setDevice(value) {
    root.device = value === "touchpad" && root.hasTouchpad ? "touchpad" : "mouse"
  }

  function choiceOptions(section) {
    if (section === "device") return root.deviceOptions
    if (section === "accel") return root.accelOptions
    if (section === "primary") return root.primaryOptions
    return []
  }

  function applyChoice(section, value) {
    if (section === "device") setDevice(value)
    else if (section === "accel") setField("accelProfile", value === "flat" ? "flat" : "adaptive")
    else if (section === "primary") setField("leftHanded", value === "right")
  }

  function moveCursor(delta) {
    var sections = root.visibleSections
    var sIdx = sections.indexOf(root.focusSection)
    if (sIdx < 0) {
      root.focusSection = sections[0]
      root.selectedIndex = Model.sectionFirstIndex(root.focusSection)
      return
    }
    var next = sIdx + (delta > 0 ? 1 : -1)
    if (next < 0 || next >= sections.length) return
    root.focusSection = sections[next]
    root.selectedIndex = Model.sectionFirstIndex(root.focusSection)
  }

  function moveCursorH(delta) {
    if (root.focusSection === "speed") { setSpeed(root.speedPercent + delta * 5); return }
    if (root.focusSection === "scroll") { setScroll(root.scrollPercent + delta * 5); return }
    if (Model.sectionIsChoice(root.focusSection)) {
      var max = Model.sectionChoiceCount(root.focusSection) - 1
      root.selectedIndex = Math.max(0, Math.min(max, root.selectedIndex + delta))
    }
  }

  function activateCursor() {
    var field = Model.toggleField(root.focusSection)
    if (field) { setField(field, !root.active[field]); return }
    if (Model.sectionIsChoice(root.focusSection)) {
      var options = choiceOptions(root.focusSection)
      if (root.selectedIndex >= 0 && root.selectedIndex < options.length)
        applyChoice(root.focusSection, options[root.selectedIndex].value)
    }
  }

  function clampCursor() {
    if (root.visibleSections.indexOf(root.focusSection) < 0) {
      root.focusSection = root.visibleSections[0]
      root.selectedIndex = Model.sectionFirstIndex(root.focusSection)
    }
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

  function showSpeedOsd() {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: root.touchpadTab ? "󰟸" : "󰍽",
      value: root.speedPercent
    }))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (!opened) return
    refresh()
    root.focusSection = "speed"
    root.selectedIndex = -1
    root.cursorActive = false
  }

  onVisibleSectionsChanged: clampCursor()
  onHasTouchpadChanged: if (!root.hasTouchpad) root.device = "mouse"

  Process {
    id: getProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyParsed(Model.parseState(text))
    }
  }

  Process {
    id: setProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseState(text)
        if (parsed.ok) root.hasTouchpad = parsed.hasTouchpad
      }
    }
    onRunningChanged: if (!running) root.flushApply()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍽"
    tooltipText: strings.t("tooltip")
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.setSpeed(root.speedPercent + wheel.steps * 5)
      root.showSpeedOsd()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(640))

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

          ChoiceSection {
            width: parent.width
            visible: root.hasTouchpad
            sectionId: "device"
            title: strings.t("section.device")
            options: root.deviceOptions
            value: root.touchpadTab ? "touchpad" : "mouse"
            onActivated: function(v) { root.setDevice(v) }
          }

          SliderSection {
            id: speedSlider
            width: parent.width
            sectionId: "speed"
            title: strings.t("section.speed")
            value: root.speedPercent
            valueText: Commons.I18n.formatNumber(Math.round(dragging ? liveValue : root.speedPercent)) + "%"
            onMoved: function(v) { root.setSpeed(v, "live") }
            onReleased: function(v) { root.setSpeed(v, "apply") }
          }

          SliderSection {
            width: parent.width
            sectionId: "scroll"
            title: strings.t("section.scroll")
            value: root.scrollPercent
            valueText: Commons.I18n.formatNumber(Math.round(dragging ? liveValue : root.scrollPercent)) + "%"
            onMoved: function(v) { root.setScroll(v, "live") }
            onReleased: function(v) { root.setScroll(v, "apply") }
          }

          Row {
            width: parent.width
            spacing: Style.space(10)

            ChoiceSection {
              width: (parent.width - parent.spacing) / 2
              sectionId: "accel"
              title: strings.t("section.accel")
              options: root.accelOptions
              value: root.active.accelProfile
              onActivated: function(v) { root.applyChoice("accel", v) }
            }

            ChoiceSection {
              width: (parent.width - parent.spacing) / 2
              sectionId: "primary"
              title: strings.t("section.primary")
              options: root.primaryOptions
              value: root.active.leftHanded ? "right" : "left"
              onActivated: function(v) { root.applyChoice("primary", v) }
            }
          }

          Grid {
            id: switchGrid
            width: parent.width
            columns: 2
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(4)
            readonly property real cellWidth: (width - columnSpacing) / 2

            Repeater {
              model: root.touchpadTab
                ? ["natural", "tap", "dwt", "clickfinger", "drag3fg"]
                : ["natural"]

              CompactToggle {
                required property string modelData
                width: switchGrid.cellWidth
                sectionId: modelData
                label: strings.t("toggle." + modelData)
                checked: root.active[Model.toggleField(modelData)] === true
                onClicked: root.setField(Model.toggleField(modelData), !checked)
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
      text: root.touchpadTab ? "󰟸" : "󰍽"
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.title
    }
  }

  component SliderSection: Column {
    id: sliderSection
    required property string sectionId
    required property string title
    required property string valueText
    property real value: 0
    property alias dragging: slider.dragging
    property alias liveValue: slider.liveValue
    signal moved(real value)
    signal released(real value)

    spacing: Style.space(2)

    Item {
      width: parent.width
      implicitHeight: Math.max(header.implicitHeight, valueLabel.implicitHeight)

      PanelSectionHeader {
        id: header
        text: sliderSection.title
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: valueLabel
        textFormat: Text.PlainText
        text: sliderSection.valueText
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
      id: sliderRow
      width: parent.width
      height: slider.implicitHeight
      hasCursor: root.cursorActive && root.focusSection === sliderSection.sectionId
      onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(sliderRow)
      foreground: root.bar.foreground
      outline: true

      PanelSlider {
        id: slider
        bar: root.bar
        anchors.fill: parent
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        minimum: 0
        maximum: 100
        step: 5
        integer: true
        value: sliderSection.value
        onMoved: function(v) { sliderSection.moved(v) }
        onReleased: function(v) { sliderSection.released(v) }
      }

      HoverHandler {
        onHoveredChanged: if (hovered) {
          root.cursorActive = true
          root.focusSection = sliderSection.sectionId
          root.selectedIndex = -1
        }
      }
    }
  }

  component ChoiceSection: Column {
    id: choiceSection
    required property string sectionId
    required property string title
    required property var options
    required property string value
    signal activated(string value)

    spacing: Style.space(4)

    PanelSectionHeader {
      text: choiceSection.title
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }

    Grid {
      id: choiceRow
      width: parent.width
      columns: choiceSection.options.length
      spacing: Style.spacing.xs
      readonly property real cellWidth: columns > 0 ? (width - spacing * (columns - 1)) / columns : 0

      Repeater {
        model: choiceSection.options

        Button {
          required property var modelData
          required property int index
          width: choiceRow.cellWidth
          text: modelData.label
          fontSize: Style.font.caption
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.sm
          verticalPadding: Style.space(4)
          bordered: true
          selected: choiceSection.value === modelData.value
          hasCursor: root.cursorActive && root.focusSection === choiceSection.sectionId && root.selectedIndex === index
          onClicked: choiceSection.activated(modelData.value)
          onHovered: function(isHovered) {
            if (!isHovered) return
            root.cursorActive = true
            root.focusSection = choiceSection.sectionId
            root.selectedIndex = index
          }
        }
      }
    }
  }

  component CompactToggle: BorderSurface {
    id: toggleRow
    required property string label
    required property string sectionId
    property bool checked: false
    signal clicked()

    implicitHeight: Style.space(32)
    radius: Style.cornerRadius
    color: "transparent"
    borderSpec: Border.controlSpec(
      (root.cursorActive && root.focusSection === sectionId) || mouseArea.containsMouse ? "hover-cursor" : "normal",
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
      onEntered: {
        root.cursorActive = true
        root.focusSection = toggleRow.sectionId
        root.selectedIndex = 0
      }
      onClicked: toggleRow.clicked()
    }
  }
}
