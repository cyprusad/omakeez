import QtQuick 2.15
import QtTest 1.3
import "../../ServiceModel.js" as Model

TestCase {
  name: "OmakeezServiceModel"

  function id(letter) { return "sha256:" + Array(65).join(letter) }

  function validCatalog() {
    var binding = {
      id: id("b"),
      combo: "SUPER + RETURN",
      modifiers: ["SUPER"],
      key: "RETURN",
      xkbCodes: [36],
      description: "Terminal",
      category: "applications",
      phase: "press",
      submap: "",
      dispatcherKind: "exec",
      trackable: true,
      guideEligible: true,
      repeat: false
    }
    var release = JSON.parse(JSON.stringify(binding))
    release.id = id("c")
    release.phase = "release"
    return {
      schemaVersion: 1,
      generatedAt: 1,
      sourceHash: id("a"),
      bindings: [binding, release]
    }
  }

  function test_validCatalogAndLookup() {
    var result = Model.normalizeCatalog(validCatalog())
    verify(result.ok)
    compare(result.catalog.bindings.length, 2)
    compare(result.catalog.byId[id("b")].description, "Terminal")
  }

  function test_catalogRejectsMalformedInputs() {
    verify(!Model.normalizeCatalog("not json").ok)
    var wrongSchema = validCatalog()
    wrongSchema.schemaVersion = 2
    verify(!Model.normalizeCatalog(wrongSchema).ok)

    var duplicate = validCatalog()
    duplicate.bindings.push(duplicate.bindings[0])
    verify(!Model.normalizeCatalog(duplicate).ok)

    var badBinding = validCatalog()
    badBinding.bindings[0].category = "invented"
    verify(!Model.normalizeCatalog(badBinding).ok)

    var badTypes = validCatalog()
    badTypes.bindings[0].trackable = "true"
    verify(!Model.normalizeCatalog(badTypes).ok)
  }

  function test_everyValidProtocolForm() {
    var catalog = Model.normalizeCatalog(validCatalog()).catalog
    compare(Model.parseProtocol("omakeez:v1:super:down", catalog).root, "SUPER")
    compare(Model.parseProtocol("omakeez:v1:guide:down:ALT", catalog).root, "ALT")
    compare(Model.parseProtocol("omakeez:v1:guide:up", catalog).phase, "up")
    compare(Model.parseProtocol("omakeez:v1:mods:SUPER_SHIFT_CTRL_ALT", catalog).modifiers, "SUPER_SHIFT_CTRL_ALT")
    compare(Model.parseProtocol("omakeez:v1:mods:SHIFT_ALT", catalog).modifiers, "SHIFT_ALT")
    var press = Model.parseProtocol("omakeez:v1:match:" + id("b") + ":press", catalog)
    verify(press.ok)
    verify(press.known)
    compare(press.phase, "press")
    var release = Model.parseProtocol("omakeez:v1:match:" + id("c") + ":release", catalog)
    verify(release.ok)
    compare(release.phase, "release")
  }

  function test_protocolRejectsMalformedAndUnknownForms() {
    var catalog = Model.normalizeCatalog(validCatalog()).catalog
    verify(!Model.parseProtocol("omakeez:v2:super:down", catalog).ok)
    verify(!Model.parseProtocol("omakeez:v1:super:down:extra", catalog).ok)
    verify(!Model.parseProtocol("omakeez:v1:guide:down:CAPS", catalog).ok)
    verify(!Model.parseProtocol("omakeez:v1:guide:up:extra", catalog).ok)
    verify(!Model.parseProtocol("omakeez:v1:mods:SUPER_CTRL_SHIFT", catalog).ok)
    verify(!Model.parseProtocol("omakeez:v1:match:" + id("b") + ":press:extra", catalog).ok)
    verify(!Model.parseProtocol("omakeez:v1:match:" + id("b") + ":release", catalog).ok)
    var unknown = Model.parseProtocol("omakeez:v1:match:" + id("d") + ":press", catalog)
    verify(unknown.ok)
    verify(!unknown.known)
  }

  function test_settingsAndBarConfigLookup() {
    compare(Model.normalizeDelay(0), 0)
    compare(Model.normalizeDelay(80), 80)
    compare(Model.normalizeDelay("150"), 150)
    compare(Model.normalizeDelay("disabled"), -1)
    compare(Model.normalizeDelay(99), 0)
    compare(Model.normalizeTopOffset(undefined), 0)
    compare(Model.normalizeTopOffset(48), 48)
    compare(Model.normalizeTopOffset("32"), 32)
    compare(Model.normalizeTopOffset(37.9), 37)
    compare(Model.normalizeTopOffset(-10), 0)
    compare(Model.normalizeTopOffset(9999), 320)
    compare(Model.normalizeTopOffset("notch"), 0)
    compare(Model.normalizeFullscreen(true), true)
    compare(Model.normalizeFullscreen("true"), false)
    compare(Model.normalizeGuideRoot(undefined), true)
    compare(Model.normalizeGuideRoot(true), true)
    compare(Model.normalizeGuideRoot(false), false)

    var barConfig = { layout: { left: [], center: [], right: [
      { id: "io.github.cyprusad.omakeez", guideDelayMs: 150, guideTopOffset: 48, showInFullscreen: true,
        guideSuperEnabled: false, guideShiftEnabled: true, guideCtrlEnabled: false, guideAltEnabled: true,
        extensionOption: "preserve-me" }
    ] } }
    var settings = Model.settingsFor(barConfig, "io.github.cyprusad.omakeez")
    compare(settings.guideDelayMs, 150)
    compare(settings.guideTopOffset, 48)
    compare(settings.showInFullscreen, true)
    compare(settings.guideSuperEnabled, false)
    compare(settings.guideCtrlEnabled, false)
    compare(settings.extensionOption, "preserve-me")
    compare(Model.settingsFor({}, "io.github.cyprusad.omakeez").guideDelayMs, undefined)
  }

  function test_settingUpdatePreservesExistingEntry() {
    var original = {
      id: "io.github.cyprusad.omakeez",
      guideDelayMs: 150,
      guideTopOffset: 48,
      showInFullscreen: true,
      guideSuperEnabled: false,
      guideShiftEnabled: true,
      extensionOption: { keep: true }
    }
    var updated = Model.updatedSettingsEntry(original, { guideTopOffset: 64 }, "io.github.cyprusad.omakeez")
    compare(updated.id, original.id)
    compare(updated.guideDelayMs, 150)
    compare(updated.guideTopOffset, 64)
    compare(updated.showInFullscreen, true)
    compare(updated.guideSuperEnabled, false)
    compare(updated.guideShiftEnabled, true)
    compare(updated.extensionOption.keep, true)
    compare(original.guideTopOffset, 48)
    var cannotReplaceId = Model.updatedSettingsEntry(original, { id: "wrong-plugin" }, "io.github.cyprusad.omakeez")
    compare(cannotReplaceId.id, original.id)
  }

  function test_fullscreenAndEventClassification() {
    compare(Model.parseActiveWindow('{"fullscreen":true}').fullscreen, true)
    compare(Model.parseActiveWindow('{"fullscreen":2}').fullscreen, true)
    compare(Model.parseActiveWindow('{"fullscreen":0}').fullscreen, false)
    verify(!Model.parseActiveWindow('{"fullscreen":"1"}').ok)
    verify(!Model.parseActiveWindow('{"class":"kitty"}').ok)
    verify(Model.isCatalogChangeEvent("configreloaded"))
    verify(Model.isCatalogChangeEvent("activelayout"))
    verify(Model.isFullscreenEvent("activewindowv2"))
    verify(!Model.isFullscreenEvent("custom"))
  }

  function test_catalogGenerationResultAndReloadGuard() {
    var hash = id("a")
    var output = JSON.stringify({ ok: true, sourceHash: hash, bindingCount: 7, changed: true })
    var generation = Model.parseCatalogGeneration(output, 0)
    verify(generation.ok)
    compare(generation.sourceHash, hash)
    compare(generation.changed, true)
    compare(generation.bindingCount, 7)
    verify(!Model.parseCatalogGeneration(output, 1).ok)
    verify(!Model.parseCatalogGeneration("not json", 0).ok)
    verify(!Model.parseCatalogGeneration('{"ok":true,"sourceHash":"sha256:bad","bindingCount":0,"changed":true}', 0).ok)

    verify(Model.shouldReloadCatalogBridge(generation, "enabled", "", "", ""))
    verify(!Model.shouldReloadCatalogBridge(generation, "disabled", "", "", ""))
    verify(!Model.shouldReloadCatalogBridge(generation, "enabled", hash, "", ""))
    verify(!Model.shouldReloadCatalogBridge(generation, "enabled", "", hash, ""))
    verify(!Model.shouldReloadCatalogBridge(generation, "enabled", "", "", hash))
    var newerHash = id("c")
    compare(Model.pendingBridgeReloadAfterCatalog(newerHash, hash), newerHash)
    compare(Model.pendingBridgeReloadAfterCatalog(hash, hash), "")
    compare(Model.pendingBridgeReloadAfterCatalog("invalid", hash), "")
    generation.changed = false
    verify(!Model.shouldReloadCatalogBridge(generation, "enabled", "", "", ""))
  }

  function test_lockStatusFailsClosed() {
    verify(Model.parseLockStatus("true\n", 0).ok)
    compare(Model.parseLockStatus("true\n", 0).locked, true)
    verify(Model.parseLockStatus("false\n", 0).ok)
    compare(Model.parseLockStatus("false\n", 0).locked, false)
    verify(!Model.parseLockStatus("", 0).ok)
    verify(!Model.parseLockStatus("yes", 0).ok)
    verify(!Model.parseLockStatus("false", 1).ok)
  }

  function test_layerStatusAndPolkitEvents() {
    var clear = '{"eDP-1":{"levels":{"0":[],"3":[]}},"DP-1":{"levels":{"0":[]}}}'
    var active = '{"eDP-1":{"levels":{"0":[],"3":[{"namespace":"omarchy-polkit"}]}}}'
    verify(Model.parseLayerStatus(clear, 0).ok)
    compare(Model.parseLayerStatus(clear, 0).active, false)
    verify(Model.parseLayerStatus(active, 0).ok)
    compare(Model.parseLayerStatus(active, 0).active, true)
    verify(!Model.parseLayerStatus("not json", 0).ok)
    verify(!Model.parseLayerStatus("{}", 0).ok)
    verify(!Model.parseLayerStatus('{"eDP-1":{"levels":[]}}', 0).ok)
    verify(!Model.parseLayerStatus('{"eDP-1":{"levels":{}}}', 0).ok)
    verify(!Model.parseLayerStatus(clear, 1).ok)
    var lookalike = '{"eDP-1":{"levels":{"3":[{"namespace":"not-omarchy-polkit"}]}}}'
    verify(Model.parseLayerStatus(lookalike, 0).ok)
    compare(Model.parseLayerStatus(lookalike, 0).active, false)

    verify(Model.isPolkitLayerEvent("openlayer", "omarchy-polkit"))
    verify(Model.isPolkitLayerEvent("closelayer", "omarchy-polkit"))
    verify(Model.isPolkitLayerEvent("openlayer", "omarchy-polkit\n"))
    verify(!Model.isPolkitLayerEvent("openlayer", "other-layer"))
    verify(!Model.isPolkitLayerEvent("openwindow", "omarchy-polkit"))
  }
}
