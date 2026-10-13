import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "State.js" as State

// Control center as a bar popup: the same chrome as the audio and power
// panels (popup surface, tracked headers, compact tiles, sliders).
Panel {
  id: root
  moduleName: "joseluis.control-center"
  ipcTarget: "joseluis.control-center"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string dndPath: home + "/.local/state/omarchy/notifications.json"

  // Text on the popup surface. The bar's own foreground is for the bar
  // chrome and can be a contrast color that disappears on this card.
  readonly property color foreground: Commons.Color.popups.text
  readonly property string fontFamily: (bar && bar.fontFamily) ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.45)

  property bool wifiEnabled: false
  property string networkKind: "disconnected"
  property string networkName: ""

  readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
  readonly property bool bluetoothOn: bluetoothAdapter ? bluetoothAdapter.enabled === true : false
  property int bluetoothWant: -1
  readonly property bool bluetoothLit: bluetoothWant === 1 || (bluetoothWant === -1 && bluetoothOn)

  property bool nightlightOn: false
  property bool nightlightBusy: false
  property bool dndOn: false
  property bool dndBusy: false
  property bool stayAwake: false
  property bool idleBusy: false

  property int brightness: -1
  property bool brightnessDragging: false
  readonly property bool brightnessKnown: brightness >= 0

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  readonly property real outputVolume: sink && sink.audio ? Math.max(0, Math.min(1, sink.audio.volume)) : 0
  readonly property bool outputMuted: sink && sink.audio ? sink.audio.muted === true : false
  readonly property bool micMuted: source && source.audio ? source.audio.muted === true : true
  readonly property bool micAvailable: source && source.audio

  property int cursorIndex: 0
  property bool cursorActive: false
  // The power button sits outside the card grid.
  property bool headerCursor: false
  property bool sessionOpen: false
  property int sessionIndex: 0
  property bool suspendAllowed: true
  property bool hibernateAllowed: false
  readonly property int cursorCount: 8

  readonly property string wifiDetail: {
    if (!wifiEnabled) return "Apagado"
    if (networkKind === "wifi") return networkName || "Conectado"
    if (networkKind === "ethernet") return "Ethernet"
    return "Sin conexión"
  }
  readonly property string bluetoothDetail: {
    if (!bluetoothAdapter) return "Sin adaptador"
    if (bluetoothWant !== -1) return bluetoothWant === 1 ? "Encendiendo" : "Apagando"
    return bluetoothOn ? "Encendido" : "Apagado"
  }
  readonly property string volumeLabel: !sink || !sink.audio ? "—"
    : (outputMuted ? "Silencio" : Math.round(outputVolume * 100) + "%")
  readonly property string brightnessLabel: brightnessKnown ? brightness + "%" : "—"

  function open() {
    cursorIndex = 0
    cursorActive = false
    headerCursor = false
    sessionOpen = false
    controller.show()
    refresh()
    if (!suspendProbe.running) suspendProbe.running = true
    if (!hibernateProbe.running) hibernateProbe.running = true
  }

  function close() {
    sessionOpen = false
    headerCursor = false
    controller.hide()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function refresh() {
    if (!brightnessRead.running && !brightnessDragging) brightnessRead.running = true
    if (!nightlightRead.running && !nightlightBusy) nightlightRead.running = true
    if (!idleRead.running && !idleBusy) idleRead.running = true
    if (!networkRead.running) networkRead.running = true
    dndFile.reload()
    wifiEnabled = Networking.wifiEnabled === true
  }

  function applyBrightness(text) {
    if (brightnessDragging) return
    var value = State.brightnessPercent(text)
    if (value === null) return
    brightness = value
  }

  function queueBrightness(percent) {
    var arg = State.brightnessArg(percent)
    if (!arg) return
    brightness = Number(arg.replace("%", ""))
    brightnessDragging = true
    pendingBrightness = arg
    brightnessDebounce.restart()
  }

  property string pendingBrightness: ""

  function commitBrightness() {
    if (!pendingBrightness) return
    if (brightnessWrite.running) return
    brightnessWrite.command = ["omarchy-brightness-display", "--no-osd", pendingBrightness]
    pendingBrightness = ""
    brightnessWrite.running = true
  }

  function setOutputVolume(fraction) {
    if (!sink || !sink.audio) return
    var value = Math.max(0, Math.min(1, Number(fraction) || 0))
    sink.audio.volume = value
    if (value > 0 && sink.audio.muted) sink.audio.muted = false
  }

  function toggleOutputMute() {
    if (sink && sink.audio) sink.audio.muted = !sink.audio.muted
  }

  function toggleMic() {
    if (source && source.audio) source.audio.muted = !source.audio.muted
  }

  function toggleWifi() {
    Networking.wifiEnabled = !Networking.wifiEnabled
    wifiEnabled = Networking.wifiEnabled === true
    networkRefresh.restart()
  }

  function toggleBluetooth() {
    if (!bluetoothAdapter || bluetoothWant !== -1) return
    var turnOn = !bluetoothAdapter.enabled
    bluetoothWant = turnOn ? 1 : 0
    bluetoothGiveUp.restart()
    Quickshell.execDetached(["omarchy-bluetooth-power", State.bluetoothPowerArg(turnOn)])
  }

  function toggleNightlight() {
    if (nightlightBusy) return
    nightlightOn = !nightlightOn
    nightlightBusy = true
    nightlightWrite.running = true
  }

  function toggleDnd() {
    if (dndBusy) return
    var next = !dndOn
    dndOn = next
    dndBusy = true
    dndWrite.command = ["omarchy-shell", "notifications", "setDnd", State.dndArg(next)]
    dndWrite.running = true
  }

  function toggleIdle() {
    if (idleBusy) return
    var next = !stayAwake
    stayAwake = next
    idleBusy = true
    idleWrite.command = ["omarchy-toggle-idle", State.idleArg(next)]
    idleWrite.running = true
  }

  // Cards sit in two columns (0–5). Up and down step a whole row;
  // left and right change column. Sliders stay on h/l. Up from the
  // first row lands on the session button.
  function moveCursor(dx, dy) {
    if (!cursorActive) {
      cursorActive = true
      headerCursor = false
      cursorIndex = 0
      return
    }
    if (headerCursor) {
      if (dy > 0) {
        headerCursor = false
        cursorIndex = 0
      } else if (dy < 0) {
        headerCursor = false
        cursorIndex = Math.max(0, cursorCount - 1)
      }
      return
    }
    var last = cursorCount - 1
    if (dy !== 0) {
      if (cursorIndex <= 5) {
        var next = cursorIndex + dy * 2
        if (next < 0) {
          headerCursor = true
          return
        }
        if (next > 5) cursorIndex = 6
        else cursorIndex = next
      } else if (dy < 0) {
        cursorIndex = cursorIndex === 6 ? 4 : cursorIndex - 1
      } else {
        cursorIndex = cursorIndex === last ? 0 : cursorIndex + 1
      }
      return
    }
    if (dx === 0) return
    if (cursorIndex <= 5) {
      if (dx > 0 && cursorIndex % 2 === 0) cursorIndex += 1
      else if (dx < 0 && cursorIndex % 2 === 1) cursorIndex -= 1
    } else if (cursorIndex === 6) {
      queueBrightness((brightnessKnown ? brightness : 1) + dx * 5)
    } else if (cursorIndex === 7) {
      setOutputVolume(outputVolume + dx * 0.05)
    }
  }

  function activateCursor() {
    if (!cursorActive) {
      cursorActive = true
      headerCursor = false
      cursorIndex = 0
      return
    }
    if (headerCursor) {
      toggleSessionMenu()
      return
    }
    if (cursorIndex === 0) toggleWifi()
    else if (cursorIndex === 1) toggleBluetooth()
    else if (cursorIndex === 2) toggleNightlight()
    else if (cursorIndex === 3) toggleDnd()
    else if (cursorIndex === 4) toggleIdle()
    else if (cursorIndex === 5) toggleMic()
    else if (cursorIndex === 7) toggleOutputMute()
  }

  function rebuildSessionRows() {
    if (!sessionModel) return
    var rows = [{ actionId: "lock", glyph: "", title: "Bloquear" }]
    if (suspendAllowed) rows.push({ actionId: "suspend", glyph: "󰒲", title: "Suspender" })
    if (hibernateAllowed) rows.push({ actionId: "hibernate", glyph: "󰤁", title: "Hibernar" })
    rows.push({ actionId: "sep", glyph: "", title: "" })
    rows.push({ actionId: "logout", glyph: "󰍃", title: "Cerrar sesión" })
    rows.push({ actionId: "reboot", glyph: "󰜉", title: "Reiniciar" })
    rows.push({ actionId: "shutdown", glyph: "󰐥", title: "Apagar" })
    sessionModel.clear()
    for (var i = 0; i < rows.length; i++) sessionModel.append(rows[i])
    if (sessionIndex >= sessionModel.count) sessionIndex = 0
  }

  function toggleSessionMenu() {
    if (sessionOpen) {
      sessionOpen = false
      return
    }
    sessionIndex = 0
    sessionOpen = true
    cursorActive = true
    headerCursor = true
  }

  function moveSession(dy) {
    var n = sessionModel.count
    if (n === 0 || dy === 0) return
    var i = sessionIndex
    for (var step = 0; step < n; step++) {
      i = (i + dy + n) % n
      var row = sessionModel.get(i)
      if (row && row.actionId !== "sep") {
        sessionIndex = i
        return
      }
    }
  }

  function runSession(actionId) {
    var command = State.sessionCommand(actionId)
    if (!command) return
    sessionOpen = false
    Quickshell.execDetached(command)
    close()
  }

  onSuspendAllowedChanged: rebuildSessionRows()
  onHibernateAllowedChanged: rebuildSessionRows()
  Component.onCompleted: {
    rebuildSessionRows()
    if (!suspendProbe.running) suspendProbe.running = true
    if (!hibernateProbe.running) hibernateProbe.running = true
  }

  function ensureCursorVisible(item) {
    if (!item || scroller.height <= 0) return
    var pos = item.mapToItem(contentColumn, 0, 0)
    var top = pos.y
    var bottom = top + item.height
    if (top < scroller.contentY) scroller.contentY = Math.max(0, top)
    else if (bottom > scroller.contentY + scroller.height)
      scroller.contentY = Math.max(0, bottom - scroller.height)
  }

  onCursorCountChanged: if (cursorIndex >= cursorCount) cursorIndex = Math.max(0, cursorCount - 1)

  onBluetoothOnChanged: {
    if (bluetoothWant !== -1 && bluetoothOn === (bluetoothWant === 1)) bluetoothWant = -1
  }

  Timer {
    id: poll
    interval: 2500
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }

  Timer {
    id: networkRefresh
    interval: 700
    onTriggered: if (!networkRead.running) networkRead.running = true
  }

  Timer {
    id: brightnessDebounce
    interval: 90
    onTriggered: root.commitBrightness()
  }

  Timer {
    id: bluetoothGiveUp
    interval: 5000
    onTriggered: root.bluetoothWant = -1
  }

  PwObjectTracker {
    objects: {
      var list = []
      if (root.sink) list.push(root.sink)
      if (root.source) list.push(root.source)
      return list
    }
  }

  FileView {
    id: dndFile
    path: root.dndPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      var value = State.dndEnabled(text())
      if (value === null) return
      root.dndOn = value
      root.dndBusy = false
    }
    onLoadFailed: root.dndOn = false
    onFileChanged: reload()
  }

  Process {
    id: brightnessRead
    command: ["omarchy-brightness-display"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyBrightness(text)
    }
  }

  Process {
    id: brightnessWrite
    onExited: {
      root.brightnessDragging = false
      if (root.pendingBrightness) root.commitBrightness()
      else if (!brightnessRead.running) brightnessRead.running = true
    }
  }

  Process {
    id: nightlightRead
    command: ["omarchy-toggle-nightlight", "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.nightlightBusy) return
        var value = State.flagEnabled(text)
        if (value !== null) root.nightlightOn = value
      }
    }
  }

  Process {
    id: nightlightWrite
    command: ["omarchy-toggle-nightlight"]
    onExited: {
      root.nightlightBusy = false
      if (!nightlightRead.running) nightlightRead.running = true
    }
  }

  Process {
    id: idleRead
    command: ["omarchy-toggle-idle", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.idleBusy) return
        var value = State.flagEnabled(text)
        if (value !== null) root.stayAwake = value
      }
    }
  }

  Process {
    id: idleWrite
    onExited: {
      root.idleBusy = false
      if (!idleRead.running) idleRead.running = true
    }
  }

  Process {
    id: networkRead
    command: ["omarchy-network-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var status = State.networkStatus(text)
        root.networkKind = status.kind
        root.networkName = status.name
        root.wifiEnabled = Networking.wifiEnabled === true
      }
    }
  }

  Process {
    id: dndWrite
    onExited: {
      root.dndBusy = false
      dndFile.reload()
    }
  }

  Process {
    id: suspendProbe
    command: ["omarchy-toggle-enabled", "suspend-off"]
    onExited: function(exitCode) { root.suspendAllowed = exitCode !== 0 }
  }

  Process {
    id: hibernateProbe
    command: ["omarchy-hibernation-available"]
    onExited: function(exitCode) { root.hibernateAllowed = exitCode === 0 }
  }

  component PlainText: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
    renderType: Text.NativeRendering
  }

  // Compact tile. The card itself is the toggle: a quiet surface when
  // off, an accent wash when on. `lit` is not named `on` — QML would
  // parse that as a signal handler. Cursor paint stays on the border so
  // an active tile does not lose its fill under the keyboard highlight.
  component SettingCard: BorderSurface {
    id: card

    property string glyph: ""
    property string title: ""
    property string detail: ""
    property bool lit: false
    property bool busy: false
    property bool available: true
    property int cardIndex: 0
    signal activated()

    readonly property bool hot: root.cursorActive && !root.headerCursor && !root.sessionOpen && root.cursorIndex === cardIndex
    readonly property color accent: Commons.Color.accent
    readonly property color offFill: Style.normalFillFor(root.foreground, accent)
    readonly property color onFill: Qt.rgba(accent.r, accent.g, accent.b, hot ? 0.34 : 0.26)

    height: Style.space(54)
    radius: Style.cornerRadius
    opacity: !available ? 0.4 : (busy ? 0.62 : 1)
    color: lit ? onFill : (hot ? Style.hoverFillFor(root.foreground, accent) : offFill)
    borderSpec: hot
      ? Border.controlSpec("hover-cursor", root.foreground, accent)
      : Border.controlSpec("normal", lit ? accent : root.foreground, accent)

    Behavior on color { ColorAnimation { duration: Style.duration(80) } }
    onHotChanged: if (hot) root.ensureCursorVisible(card)

    Item {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)

      PlainText {
        id: glyphText
        text: card.glyph
        font.pixelSize: Style.font.iconLarge
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        opacity: card.lit ? 1 : 0.5
      }

      Column {
        anchors.left: glyphText.right
        anchors.leftMargin: Style.space(8)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        PlainText {
          text: card.title
          width: parent.width
          font.bold: card.lit
        }

        PlainText {
          text: card.detail
          width: parent.width
          font.pixelSize: Style.font.caption
          color: root.dim
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: card.available && !card.busy
      hoverEnabled: true
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.headerCursor = false
        root.cursorIndex = card.cardIndex
      }
      onClicked: card.activated()
    }
  }

  QtObject {
    id: sliderChrome
    property color foreground: root.foreground
    property color background: Commons.Color.popups.background
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.sessionOpen) root.moveSession(dy)
        else root.moveCursor(dx, dy)
      }
      onActivateRequested: {
        if (root.sessionOpen) root.runSession(sessionModel.get(root.sessionIndex) ? sessionModel.get(root.sessionIndex).actionId : "")
        else root.activateCursor()
      }
      onCloseRequested: {
        if (root.sessionOpen) root.sessionOpen = false
        else root.close()
      }
      onTabRequested: function(direction) {
        if (root.sessionOpen) root.sessionOpen = false
        else root.switchPanel(direction)
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: scroller.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerButton.height)

            PlainText {
              id: heroIcon
              text: "󰒓"
              font.pixelSize: Style.font.iconLarge
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            BorderSurface {
              id: powerButton
              width: Style.space(28)
              height: Style.space(28)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              radius: Style.cornerRadius > 0 ? height / 2 : Style.space(4)
              readonly property bool hot: root.headerCursor || root.sessionOpen || powerMouse.containsMouse
              color: hot ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"
              borderSpec: hot
                ? Border.controlSpec("hover-cursor", root.foreground, Commons.Color.accent)
                : Border.none()

              PlainText {
                anchors.centerIn: parent
                text: ""
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Style.font.icon
              }

              MouseArea {
                id: powerMouse
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.headerCursor = true
                }
                onClicked: root.toggleSessionMenu()
              }
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(10)
              anchors.right: powerButton.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              PlainText {
                text: "Centro de control"
                width: parent.width
                font.pixelSize: Style.font.title
                font.bold: true
              }

              PlainText {
                text: "AJUSTES RÁPIDOS"
                width: parent.width
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                color: root.dim
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            id: linkCards
            width: parent.width
            spacing: Style.space(6)
            readonly property int tileWidth: Math.max(0, Math.floor((width - spacing) / 2))

            PanelSectionHeader {
              text: "CONEXIÓN"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: linkCards.spacing

              SettingCard {
                width: linkCards.tileWidth
                glyph: root.wifiEnabled ? "󰤨" : "󰤭"
                title: "Wi-Fi"
                detail: root.wifiDetail
                lit: root.wifiEnabled
                cardIndex: 0
                onActivated: root.toggleWifi()
              }

              SettingCard {
                width: linkCards.tileWidth
                glyph: root.bluetoothLit ? "󰂯" : "󰂲"
                title: "Bluetooth"
                detail: root.bluetoothDetail
                lit: root.bluetoothLit
                busy: root.bluetoothWant !== -1
                available: !!root.bluetoothAdapter
                cardIndex: 1
                onActivated: root.toggleBluetooth()
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            id: systemCards
            width: parent.width
            spacing: Style.space(6)
            readonly property int tileWidth: Math.max(0, Math.floor((width - spacing) / 2))

            PanelSectionHeader {
              text: "SISTEMA"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: systemCards.spacing

              SettingCard {
                width: systemCards.tileWidth
                glyph: "󰔎"
                title: "Luz nocturna"
                detail: root.nightlightOn ? "Encendida" : "Apagada"
                lit: root.nightlightOn
                busy: root.nightlightBusy
                cardIndex: 2
                onActivated: root.toggleNightlight()
              }

              SettingCard {
                width: systemCards.tileWidth
                glyph: "󰂛"
                title: "No molestar"
                detail: root.dndOn ? "Silencio" : "Avisos"
                lit: root.dndOn
                busy: root.dndBusy
                cardIndex: 3
                onActivated: root.toggleDnd()
              }
            }

            Row {
              width: parent.width
              spacing: systemCards.spacing

              SettingCard {
                width: systemCards.tileWidth
                glyph: "󰅶"
                title: "Despierto"
                detail: root.stayAwake ? "Sin bloqueo" : "Puede bloquear"
                lit: root.stayAwake
                busy: root.idleBusy
                cardIndex: 4
                onActivated: root.toggleIdle()
              }

              SettingCard {
                width: systemCards.tileWidth
                glyph: root.micMuted ? "󰍭" : "󰍬"
                title: "Micrófono"
                detail: !root.micAvailable ? "No disponible" : (root.micMuted ? "Silencio" : "Activo")
                lit: root.micAvailable && !root.micMuted
                available: root.micAvailable
                cardIndex: 5
                onActivated: root.toggleMic()
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(brightnessHeader.implicitHeight, brightnessValue.implicitHeight)

              PanelSectionHeader {
                id: brightnessHeader
                text: "BRILLO"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              PlainText {
                id: brightnessValue
                text: root.brightnessLabel
                font.pixelSize: Style.font.caption
                font.bold: true
                color: root.dim
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: brightnessRow
              width: parent.width
              implicitHeight: brightnessSlider.implicitHeight + Style.spacing.controlGap
              height: implicitHeight
              hasCursor: root.cursorActive && !root.headerCursor && !root.sessionOpen && root.cursorIndex === 6
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(brightnessRow)
              foreground: root.foreground

              PanelSlider {
                id: brightnessSlider
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                bar: sliderChrome
                enabled: root.brightnessKnown
                minimum: 1
                maximum: 100
                step: 5
                integer: true
                value: root.brightnessKnown ? root.brightness : 1
                onMoved: function(value) { root.queueBrightness(value) }
                onReleased: function(value) { root.queueBrightness(value) }
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.headerCursor = false
                  root.cursorIndex = 6
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(volumeHeader.implicitHeight, volumeValue.implicitHeight)

              PanelSectionHeader {
                id: volumeHeader
                text: "SONIDO"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              PlainText {
                id: volumeValue
                text: root.volumeLabel
                font.pixelSize: Style.font.caption
                font.bold: true
                color: root.dim
                opacity: root.outputMuted ? 0.5 : 1
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: volumeRow
              width: parent.width
              implicitHeight: volumeSlider.implicitHeight + Style.spacing.controlGap
              height: implicitHeight
              hasCursor: root.cursorActive && !root.headerCursor && !root.sessionOpen && root.cursorIndex === 7
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(volumeRow)
              foreground: root.foreground

              PanelSlider {
                id: volumeSlider
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                bar: sliderChrome
                enabled: root.sink && root.sink.audio
                minimum: 0
                maximum: 1
                step: 0.05
                value: root.outputVolume
                opacity: root.outputMuted ? 0.5 : 1
                onMoved: function(value) { root.setOutputVolume(value) }
                onReleased: function(value) { root.setOutputVolume(value) }
                onRightClicked: root.toggleOutputMute()
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.headerCursor = false
                  root.cursorIndex = 7
                }
              }
            }
          }

        }
      }

      Item {
        id: menuLayer
        anchors.fill: parent
        visible: root.sessionOpen
        z: 20

        MouseArea {
          anchors.fill: parent
          onClicked: root.sessionOpen = false
        }

        BorderSurface {
          id: sessionMenu
          width: Style.space(188)
          height: sessionColumn.implicitHeight + Style.space(8)
          radius: Style.cornerRadius
          color: Commons.Color.menu.background
          borderSpec: Border.localOrSurfaceSpec("menu", "border", Commons.Color.menu.border, Commons.Color.menu.border, 1)
          // The button is pinned to the right edge of this same surface.
          // mapToItem was landing the menu on the left, so align it here.
          x: Math.max(0, parent.width - width)
          y: {
            var p = powerButton.mapToItem(menuLayer, 0, powerButton.height)
            return (p && p.y > 0 ? p.y : Style.space(28)) + Style.space(6)
          }

          Column {
            id: sessionColumn
            x: Style.space(4)
            y: Style.space(4)
            width: parent.width - Style.space(8)
            spacing: 0

            Repeater {
              model: sessionModel

              delegate: Item {
                required property int index
                required property string actionId
                required property string glyph
                required property string title

                width: sessionColumn.width
                height: actionId === "sep" ? Style.space(8) : Style.space(34)

                Rectangle {
                  visible: actionId === "sep"
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  height: 1
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
                }

                Item {
                  id: actionRow
                  visible: actionId !== "sep"
                  anchors.fill: parent
                  readonly property bool hot: root.sessionIndex === index

                  Rectangle {
                    anchors.fill: parent
                    anchors.margins: Style.space(2)
                    radius: Math.max(0, Style.cornerRadius - 2)
                    color: actionRow.hot ? Commons.Color.menu.selectedBackground : "transparent"
                  }

                  PlainText {
                    id: actionGlyph
                    text: glyph
                    font.pixelSize: Style.font.icon
                    width: Style.space(22)
                    horizontalAlignment: Text.AlignHCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    color: actionRow.hot ? Commons.Color.menu.selectedText : root.foreground
                  }

                  PlainText {
                    text: title
                    anchors.left: actionGlyph.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    color: actionRow.hot ? Commons.Color.menu.selectedText : root.foreground
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) root.sessionIndex = index
                    onClicked: root.runSession(actionId)
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  ListModel { id: sessionModel }
}
