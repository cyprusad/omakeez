import QtQuick 2.15
import QtTest 1.3
import "../../GuideModel.js" as GuideModel

TestCase {
  name: "OmakeezGuideModel"

  function binding(number, modifiers, description, trackable, eligible) {
    return {
      id: "sha256:" + String(number).repeat(64),
      combo: modifiers.join(" + ") + " + KEY" + number,
      modifiers: modifiers,
      key: "KEY" + number,
      xkbCodes: [number + 10],
      description: description,
      category: "other",
      phase: "press",
      submap: "",
      dispatcherKind: "exec",
      trackable: trackable === undefined ? true : trackable,
      guideEligible: eligible === undefined ? true : eligible,
      repeat: false
    }
  }

  function catalog() {
    var bindings = []
    for (var i = 0; i < 14; i++) bindings.push(binding(i, ["SUPER"], "Command " + String.fromCharCode(90 - i)))
    bindings.push(binding(20, ["SUPER", "SHIFT"], "Shift command"))
    bindings.push(binding(21, ["SUPER", "CTRL"], "Hidden command", false))
    return { bindings: bindings }
  }

  function test_exactFilteringAndLimit() {
    var cards = GuideModel.cardModel(catalog(), "SUPER", 12)
    compare(cards.total, 14)
    compare(cards.items.length, 12)
    compare(cards.more, 2)
    compare(cards.items[0].description, "Command Z")

    var shift = GuideModel.cardModel(catalog(), "SUPER_SHIFT", 12)
    compare(shift.total, 1)
    compare(shift.items[0].description, "Shift command")
    compare(GuideModel.cardModel(catalog(), "SHIFT", 12).total, 0)
  }

  function test_priorityDisplayAndCanopyLayout() {
    var source = catalog()
    source.bindings[13].key = "code:20"
    source.bindings[13].combo = "SUPER + code:20"
    var ranked = GuideModel.rankedBindings(source, "SUPER", [source.bindings[13].id])
    compare(ranked[0].id, source.bindings[13].id)
    compare(ranked[0].combo, "SUPER + KEY 20")

    var canonical = GuideModel.rankedBindings(source, "SUPER", [])
    compare(canonical[0].id, source.bindings[0].id)

    var cards = []
    for (var i = 0; i < 38; i++) cards.push({ id: "sha256:" + String(i), combo: "SUPER + " + i, description: "Command " + i })
    var collapsed = GuideModel.canopyLayout(cards, { width: 2560, height: 1440 }, false)
    verify(collapsed.visibleCount > 12)
    compare(collapsed.visibleCount, 27)
    verify(collapsed.more > 0)
    verify(collapsed.overflow !== null)
    verify(collapsed.metrics.cardHeight >= 46)
    compare(collapsed.items[0].binding.id, cards[0].id)
    compare(collapsed.items[0].x + collapsed.items[0].width / 2, 1280)
    compare(collapsed.items[1].y, collapsed.items[2].y)
    compare(collapsed.items[1].x + collapsed.items[2].x + collapsed.items[1].width, 2560)
    compare(collapsed.items[9].binding.id, cards[9].id)
    compare(collapsed.items[10].binding.id, cards[10].id)
    verify(collapsed.items[9].x < collapsed.overflow.x)
    verify(collapsed.items[10].x > collapsed.overflow.x)
    var corners = []
    for (var placement = 0; placement < collapsed.items.length; placement++)
      if (collapsed.items[placement].tier === "corner") corners.push(collapsed.items[placement])
    compare(corners.length, 2)
    compare(corners[0].y, collapsed.overflow.y)
    verify(corners[0].x > collapsed.metrics.margin)
    verify(corners[1].x + corners[1].width < 2560 - collapsed.metrics.margin)
    var outerSecondaryLeft = 2560
    for (var secondary = 0; secondary < collapsed.items.length; secondary++) {
      var item = collapsed.items[secondary]
      if (item.tier === "secondary" && item.x < collapsed.overflow.x)
        outerSecondaryLeft = Math.min(outerSecondaryLeft, item.x)
    }
    compare(corners[0].x + corners[0].width + collapsed.metrics.gap, outerSecondaryLeft)

    var expanded = GuideModel.canopyLayout(cards, { width: 2560, height: 1440 }, true)
    compare(expanded.visibleCount, 38)
    compare(expanded.more, 0)
    compare(expanded.items[0].x, collapsed.items[0].x)
    compare(expanded.items[0].y, collapsed.items[0].y)
    for (var fixed = 0; fixed < collapsed.items.length; fixed++) {
      compare(expanded.items[fixed].binding.id, collapsed.items[fixed].binding.id)
      compare(expanded.items[fixed].x, collapsed.items[fixed].x)
      compare(expanded.items[fixed].y, collapsed.items[fixed].y)
    }
    compare(expanded.items[collapsed.items.length].x, collapsed.overflow.x)
    compare(expanded.items[collapsed.items.length].width, collapsed.overflow.width)
    verify(expanded.height < 1440 * 0.45)

    var alternateLane = GuideModel.canopyLayout(cards.slice(0, 25), { width: 2560, height: 1440 }, false)
    compare(alternateLane.more, 0)
    compare(alternateLane.visibleCount, 25)
    compare(alternateLane.items[0].x + alternateLane.items[0].width / 2, 1280)
    verify(alternateLane.items[9].y > alternateLane.items[0].y)
    verify(alternateLane.items[17].y > alternateLane.items[9].y)

    var twoBindings = GuideModel.canopyLayout(cards.slice(0, 2), { width: 2560, height: 1440 }, false)
    compare(twoBindings.items.length, 2)
    compare(twoBindings.items[0].y, twoBindings.items[1].y)
    compare(twoBindings.items[0].x + twoBindings.items[1].x + twoBindings.items[0].width, 2560)
  }

  function test_lanesAndAccessibilityFiltering() {
    var lanes = GuideModel.laneCounts(catalog())
    compare(lanes.SHIFT, 1)
    compare(lanes.CTRL, 1)
    compare(lanes.ALT, 0)
    compare(GuideModel.cardModel(catalog(), "SUPER_CTRL", 12).total, 0)
  }

  function test_suppressionAndDelayModes() {
    var state = {
      integrationState: "enabled",
      catalogState: "ready",
      lockStateKnown: true,
      desktopLocked: false,
      credentialPromptStateKnown: true,
      credentialPromptActive: false,
      activeWindowFullscreen: false,
      showInFullscreen: false
    }
    verify(GuideModel.eligible(state))
    state.lockStateKnown = false
    verify(!GuideModel.eligible(state))
    state.lockStateKnown = true
    state.credentialPromptStateKnown = false
    verify(!GuideModel.eligible(state))
    state.credentialPromptStateKnown = true
    state.desktopLocked = true
    verify(!GuideModel.eligible(state))
    state.desktopLocked = false
    state.credentialPromptActive = true
    verify(!GuideModel.eligible(state))
    state.credentialPromptActive = false
    state.activeWindowFullscreen = true
    verify(!GuideModel.eligible(state))
    state.showInFullscreen = true
    verify(GuideModel.eligible(state))

    compare(GuideModel.delayMode(false, 0), "hidden")
    compare(GuideModel.delayMode(true, 0), "immediate")
    compare(GuideModel.delayMode(true, 80), "delayed")
    compare(GuideModel.delayMode(true, 150), "delayed")
    compare(GuideModel.delayMode(true, 250), "delayed")
    compare(GuideModel.delayMode(true, -1), "disabled")
  }

  function test_focusAndBarPlacement() {
    verify(GuideModel.focusedVisible(true, "DP-1", "DP-1"))
    verify(!GuideModel.focusedVisible(true, "DP-1", "HDMI-A-1"))
    verify(!GuideModel.focusedVisible(false, "DP-1", "DP-1"))
    verify(!GuideModel.focusedVisible(true, "", "DP-1"))
  }
}
