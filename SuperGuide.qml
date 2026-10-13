import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "GuideModel.js" as GuideModel

Item {
  id: root

  property var service: null
  property bool delayedVisible: false
  property bool expanded: false
  property string renderedHighlightId: ""
  property int focusRevision: 0
  property string frozenMask: ""
  property string frozenGuideRoot: "SUPER"
  property var frozenCards: []

  readonly property bool eligible: service ? GuideModel.eligible({
    integrationState: service.integrationState,
    catalogState: service.catalogState,
    lockStateKnown: service.lockStateKnown,
    desktopLocked: service.desktopLocked,
    credentialPromptStateKnown: service.credentialPromptStateKnown,
    credentialPromptActive: service.credentialPromptActive,
    activeWindowFullscreen: service.activeWindowFullscreen,
    showInFullscreen: service.showInFullscreen
  }) : false
  readonly property int delayValue: service ? Number(service.guideDelayMs) : -1
  readonly property int topOffset: service ? Number(service.guideTopOffset) : 0
  readonly property string currentMask: service && String(service.activeModifiers || "") !== ""
    ? String(service.activeModifiers)
    : service && String(service.activeGuideRoot || "") !== "" ? String(service.activeGuideRoot) : "SUPER"
  readonly property string currentGuideRoot: service && String(service.activeGuideRoot || "") !== ""
    ? String(service.activeGuideRoot) : "SUPER"
  readonly property var lanes: GuideModel.laneCounts(service ? service.catalog : null)

  function displayMask(mask) {
    return String(mask || currentGuideRoot).split("_").join(" + ")
  }

  function guideHint(rootModifier) {
    var rootName = String(rootModifier || "SUPER")
    if (rootName === "SHIFT") return "Hold SHIFT · Add SUPER / CTRL / ALT"
    if (rootName === "CTRL") return "Hold CTRL · Add SUPER / SHIFT / ALT"
    if (rootName === "ALT") return "Hold ALT · Add SUPER / SHIFT / CTRL"
    return "Hold SUPER · Add SHIFT / CTRL / ALT"
  }

  function resetDeck() {
    frozenMask = currentMask
    frozenGuideRoot = currentGuideRoot
    // The catalog is generated in the same priority order as Omarchy's
    // SUPER+K menu. `canopyLayout` then assigns its first item to the center
    // and alternates each following item outward symmetrically.
    frozenCards = GuideModel.rankedBindings(service ? service.catalog : null,
      frozenMask, [])
    expanded = false
  }

  function showGuide() {
    if (!delayedVisible || frozenMask !== currentMask || frozenGuideRoot !== currentGuideRoot) resetDeck()
    delayedVisible = true
  }

  function hideGuide() {
    guideDelayTimer.stop()
    overflowHoverTimer.stop()
    delayedVisible = false
    expanded = false
  }

  function expandOverflow() {
    if (!delayedVisible || expanded || frozenCards.length === 0) return
    expanded = true
  }

  function focusedScreenName() {
    var revision = focusRevision
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  function syncVisibility() {
    var mode = GuideModel.delayMode(service && service.guideVisible === true, delayValue)
    if (!eligible || mode === "hidden" || mode === "disabled") {
      hideGuide()
      return
    }
    if (mode === "immediate") {
      guideDelayTimer.stop()
      showGuide()
      return
    }
    if (!delayedVisible) {
      guideDelayTimer.interval = delayValue
      guideDelayTimer.restart()
    }
  }

  function beginHighlight(bindingId) {
    renderedHighlightId = String(bindingId || "")
    highlightTimer.restart()
  }

  Timer {
    id: guideDelayTimer
    repeat: false
    onTriggered: {
      if (root.eligible && root.service && root.service.guideVisible === true)
        root.showGuide()
    }
  }

  Timer {
    id: highlightTimer
    interval: 140
    repeat: false
    onTriggered: root.renderedHighlightId = ""
  }

  Timer {
    id: overflowHoverTimer
    interval: 150
    repeat: false
    onTriggered: root.expandOverflow()
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onGuideVisibleChanged() { root.syncVisibility() }
    function onGuideDelayMsChanged() { root.syncVisibility() }
    function onIntegrationStateChanged() { root.syncVisibility() }
    function onCatalogStateChanged() { root.syncVisibility() }
    function onDesktopLockedChanged() { root.syncVisibility() }
    function onCredentialPromptActiveChanged() { root.syncVisibility() }
    function onActiveWindowFullscreenChanged() { root.syncVisibility() }
    function onShowInFullscreenChanged() { root.syncVisibility() }
    function onActiveModifiersChanged() {
      if (root.delayedVisible && root.service && root.service.guideVisible === true)
        root.resetDeck()
    }
    function onActiveGuideRootChanged() {
      if (root.delayedVisible && root.service && root.service.guideVisible === true)
        root.resetDeck()
    }
    function onBindingMatched(bindingId) { root.beginHighlight(bindingId) }
  }

  Connections {
    target: Hyprland
    function onFocusedMonitorChanged() {
      root.focusRevision += 1
      if (root.delayedVisible) root.resetDeck()
    }
  }

  Component.onCompleted: syncVisibility()

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: guideWindow
        required property var modelData

        screen: modelData
        visible: GuideModel.focusedVisible(
          root.delayedVisible,
          modelData ? modelData.name : "",
          root.focusedScreenName())
        color: "transparent"
        // Keep a little extra window height for the gradient to dissolve
        // into the desktop instead of ending in a visible horizontal edge.
        implicitHeight: guideContent.y + guideContent.height + Style.space(80)
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; left: true; right: true }

        WlrLayershell.namespace: "omakeez-guide"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // Hover is intentionally confined to this single pill. Every other
        // part of the guide remains pointer-transparent and the expanded
        // state is sticky, so cards themselves never need an input region.
        mask: Region {
          item: overflowPill.visible && !root.expanded ? overflowPill : null
        }

        // Theme-native contrast shield: intentionally opaque behind the
        // primary cards, then progressively transparent below the guide.
        // This makes text readable over a terminal or bright application
        // without requiring compositor-specific blur configuration.
        Rectangle {
          id: guideBackdrop
          x: 0
          // Start the shield at the offset, not at the screen edge. The band a
          // notch occupies also holds the bar, and dimming it to read a guide
          // trades one unreadable thing for another. Above the offset the
          // window stays fully transparent.
          y: root.topOffset
          width: parent.width
          height: guideContent.y - root.topOffset + guideContent.height + Style.space(80)
          z: -1
          gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Util.alpha(Color.menu.background, 0.96) }
            GradientStop { position: 0.28; color: Util.alpha(Color.menu.background, 0.88) }
            GradientStop { position: 0.66; color: Util.alpha(Color.menu.background, 0.48) }
            GradientStop { position: 1.0; color: Util.alpha(Color.menu.background, 0.0) }
          }
        }

        readonly property var guideLayout: GuideModel.canopyLayout(root.frozenCards, {
          width: Math.max(1, guideContent.width),
          height: Math.max(1, height)
        }, root.expanded)

        onVisibleChanged: {
          if (visible && root.service && root.service.recordGuideVisible)
            root.service.recordGuideVisible()
        }

        Item {
          id: guideContent
          x: Style.space(4)
          // The guide's transparent contrast surface already begins at the
          // screen edge. Start the header there too, rather than reserving an
          // opaque-looking dead band for the bar underneath. `guideTopOffset`
          // opts back into that band for displays whose top edge is physically
          // obstructed by a notch or camera housing. The window and shield
          // heights are derived from this y, so both grow with the offset
          // instead of clipping the last row.
          y: Style.space(4) + root.topOffset
          width: Math.max(1, parent.width - Style.space(8))
          height: headerChip.height + Style.space(5) + deckCanvas.height

          BorderSurface {
            id: headerChip
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: headerRow.implicitWidth + Style.space(14)
            implicitHeight: Style.space(24)
            color: Util.alpha(Color.menu.background, 0.82)
            borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border,
              Math.max(1, Style.space(1)))
            radius: Style.cornerRadius

            Row {
              id: headerRow
              anchors.centerIn: parent
              spacing: Style.space(5)
              Text {
                text: root.frozenGuideRoot + " GUIDE"
                color: Color.menu.selectedText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 8
                elide: Text.ElideNone
              }
              Text {
                text: root.expanded ? "All " + guideWindow.guideLayout.total + " bindings"
                  : root.frozenMask === root.frozenGuideRoot ? root.guideHint(root.frozenGuideRoot)
                    : root.displayMask(root.frozenMask)
                color: Color.menu.text
                opacity: 0.84
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }

          Item {
            id: deckCanvas
            x: 0
            y: headerChip.height + Style.space(5)
            width: parent.width
            height: guideWindow.guideLayout.height

            Repeater {
              model: guideWindow.guideLayout.items

              delegate: BorderSurface {
                required property var modelData
                readonly property bool highlighted: modelData.binding.id === root.renderedHighlightId

                x: modelData.x
                y: modelData.y
                width: modelData.width
                height: modelData.height
                radius: Style.cornerRadius
                color: highlighted ? Color.menu.selectedBackground
                  : Util.alpha(Color.menu.background, modelData.opacity)
                borderSpec: highlighted
                  ? Border.surfaceSpec("menu", "selected-border", Color.menu.selectedBorder,
                    Math.max(1, Style.space(1)))
                  : Border.surfaceSpec("menu", "border",
                    Util.alpha(Color.menu.border, Math.min(1, modelData.opacity + 0.12)),
                    Math.max(1, Style.space(1)))

                Behavior on x {
                  NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                  NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Behavior on color { ColorAnimation { duration: 120 } }

                Column {
                  anchors.fill: parent
                  anchors.margins: Style.space(4)
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    height: Math.max(1, (parent.height - parent.spacing) * 0.52)
                    text: modelData.binding.combo
                    color: highlighted ? Color.menu.selectedText : Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Math.max(10, Style.font.caption + 1)
                    font.bold: true
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 8
                    elide: Text.ElideNone
                    maximumLineCount: 1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                  }

                  Text {
                    width: parent.width
                    height: Math.max(1, parent.height - parent.spacing - (parent.height - parent.spacing) * 0.52)
                    text: modelData.binding.description
                    color: highlighted ? Color.menu.selectedText : Color.menu.text
                    opacity: highlighted ? 1 : 0.88
                    font.family: Style.font.family
                    font.pixelSize: Math.max(8, Style.font.caption - 1)
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 8
                    elide: Text.ElideNone
                    maximumLineCount: 1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                  }
                }
              }
            }

            BorderSurface {
              id: overflowPill
              visible: guideWindow.guideLayout.more > 0 && guideWindow.guideLayout.overflow
              x: visible ? guideWindow.guideLayout.overflow.x : 0
              y: visible ? guideWindow.guideLayout.overflow.y : 0
              width: visible ? guideWindow.guideLayout.overflow.width : 0
              height: visible ? guideWindow.guideLayout.overflow.height : 0
              radius: Style.cornerRadius
              color: Util.alpha(Color.menu.background, 0.9)
              borderSpec: Border.surfaceSpec("menu", "border", Color.menu.selectedBorder,
                Math.max(1, Style.space(1)))
              Behavior on color { ColorAnimation { duration: 120 } }

              Text {
                anchors.centerIn: parent
                text: "+" + guideWindow.guideLayout.more + " MORE · HOVER"
                color: Color.menu.selectedText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              HoverHandler {
                id: overflowHover
                enabled: overflowPill.visible && !root.expanded
                onHoveredChanged: {
                  if (hovered) overflowHoverTimer.restart()
                  else overflowHoverTimer.stop()
                }
              }
            }
          }

        }
      }
    }
  }
}
