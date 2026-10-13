.pragma library

var CATEGORIES = [
  "windows", "workspaces", "applications", "system", "capture",
  "media", "clipboard", "notifications", "style", "other"
]
var MODIFIERS = ["SUPER", "SHIFT", "CTRL", "ALT"]
var PROTOCOL_PREFIX = "omakeez:v1:"

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function hasOnlyStrings(values, allowed) {
  if (!Array.isArray(values)) return false
  var seen = {}
  for (var i = 0; i < values.length; i++) {
    if (typeof values[i] !== "string" || allowed.indexOf(values[i]) === -1 || seen[values[i]]) return false
    seen[values[i]] = true
  }
  return true
}

function validId(value) {
  return typeof value === "string" && /^sha256:[0-9a-f]{64}$/.test(value)
}

function validSourceHash(value) {
  return validId(value)
}

function validCodeList(values) {
  if (!Array.isArray(values)) return false
  for (var i = 0; i < values.length; i++) {
    if (typeof values[i] !== "number" || !isFinite(values[i]) || Math.floor(values[i]) !== values[i] || values[i] < 1) return false
  }
  return true
}

function normalizedBinding(raw) {
  if (!isObject(raw)) return null
  var requiredStrings = ["id", "combo", "key", "description", "submap", "dispatcherKind"]
  for (var i = 0; i < requiredStrings.length; i++) {
    if (typeof raw[requiredStrings[i]] !== "string") return null
  }
  if (!validId(raw.id) || !hasOnlyStrings(raw.modifiers, MODIFIERS)) return null
  if (CATEGORIES.indexOf(raw.category) === -1) return null
  if (raw.phase !== "press" && raw.phase !== "release") return null
  if (!validCodeList(raw.xkbCodes)) return null
  if (typeof raw.trackable !== "boolean" || typeof raw.guideEligible !== "boolean") return null
  if (raw.repeat !== undefined && typeof raw.repeat !== "boolean") return null
  if (raw.available !== undefined && typeof raw.available !== "boolean") return null
  if (raw.unavailable !== undefined && typeof raw.unavailable !== "boolean") return null

  return {
    id: raw.id,
    combo: raw.combo,
    modifiers: raw.modifiers.slice(),
    key: raw.key,
    xkbCodes: raw.xkbCodes.slice(),
    description: raw.description,
    category: raw.category,
    phase: raw.phase,
    submap: raw.submap,
    dispatcherKind: raw.dispatcherKind,
    trackable: raw.trackable,
    guideEligible: raw.guideEligible,
    repeat: raw.repeat === true,
    available: raw.available !== false,
    unavailable: raw.unavailable === true
  }
}

function normalizeCatalog(raw) {
  var value = raw
  if (typeof value === "string") {
    try { value = JSON.parse(value) } catch (e) { return { ok: false, error: "invalid-json" } }
  }
  if (!isObject(value) || value.schemaVersion !== 1 || !validSourceHash(value.sourceHash)
      || typeof value.generatedAt !== "number" || !isFinite(value.generatedAt)
      || !Array.isArray(value.bindings)) {
    return { ok: false, error: "invalid-catalog" }
  }

  var bindings = []
  var byId = {}
  for (var i = 0; i < value.bindings.length; i++) {
    var binding = normalizedBinding(value.bindings[i])
    if (!binding || byId[binding.id]) return { ok: false, error: "invalid-binding" }
    byId[binding.id] = binding
    bindings.push(binding)
  }
  return {
    ok: true,
    catalog: {
      schemaVersion: 1,
      generatedAt: value.generatedAt,
      sourceHash: value.sourceHash,
      bindings: bindings,
      byId: byId
    }
  }
}

function allowedModifierMask(mask) {
  if (typeof mask !== "string" || mask === "") return false
  var parts = mask.split("_")
  var seen = {}
  for (var i = 0; i < parts.length; i++) {
    if (MODIFIERS.indexOf(parts[i]) === -1 || seen[parts[i]]) return false
    seen[parts[i]] = true
    if (i > 0 && MODIFIERS.indexOf(parts[i]) <= MODIFIERS.indexOf(parts[i - 1])) return false
  }
  return true
}

function parseProtocol(payload, catalog) {
  if (typeof payload !== "string" || payload.indexOf(PROTOCOL_PREFIX) !== 0)
    return { ok: false, error: "wrong-prefix" }

  // Retain the original Super events during the transition so an older bridge
  // cannot leave the service without a guide lifecycle.
  if (payload === PROTOCOL_PREFIX + "super:down") return { ok: true, type: "guide", phase: "down", root: "SUPER" }
  if (payload === PROTOCOL_PREFIX + "super:up") return { ok: true, type: "guide", phase: "up", root: "SUPER" }

  var guideDown = payload.match(/^omakeez:v1:guide:down:(SUPER|SHIFT|CTRL|ALT)$/)
  if (guideDown) return { ok: true, type: "guide", phase: "down", root: guideDown[1] }
  if (payload === PROTOCOL_PREFIX + "guide:up") return { ok: true, type: "guide", phase: "up" }

  var modifierMatch = payload.match(/^omakeez:v1:mods:(.*)$/)
  if (modifierMatch) {
    if (!allowedModifierMask(modifierMatch[1])) return { ok: false, error: "invalid-modifiers" }
    return { ok: true, type: "mods", modifiers: modifierMatch[1] }
  }

  var match = payload.match(/^omakeez:v1:match:(sha256:[0-9a-f]{64}):(press|release)$/)
  if (match) {
    var known = !!(catalog && catalog.byId && catalog.byId[match[1]])
    if (known && catalog.byId[match[1]].phase !== match[2]) return { ok: false, error: "phase-mismatch" }
    return { ok: true, type: "match", id: match[1], phase: match[2], known: known }
  }
  return { ok: false, error: "invalid-protocol" }
}

function normalizeDelay(value) {
  if (value === false || String(value).toLowerCase() === "disabled") return -1
  var number = Number(value)
  return [0, 80, 150, 250].indexOf(number) !== -1 ? number : 0
}

function normalizeTopOffset(value) {
  var number = Number(value)
  if (!isFinite(number)) return 0
  return Math.min(320, Math.max(0, Math.floor(number)))
}

function normalizeFullscreen(value) {
  return value === true
}

function normalizeGuideRoot(value) {
  return value !== false
}

function settingsFor(barConfig, moduleName) {
  if (!isObject(barConfig) || !isObject(barConfig.layout)) return {}
  var sections = ["left", "center", "right"]
  var targetId = String(moduleName || "")
  for (var s = 0; s < sections.length; s++) {
    var entries = barConfig.layout[sections[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (isObject(entry) && String(entry.id || "") === targetId) return entry
    }
  }
  return {}
}

function updatedSettingsEntry(entry, changes, moduleName) {
  var next = { id: String(moduleName || "") }
  if (isObject(entry)) {
    for (var key in entry) if (key !== "id") next[key] = entry[key]
  }
  if (isObject(changes)) {
    for (var changed in changes) if (changed !== "id") next[changed] = changes[changed]
  }
  return next
}

function parseActiveWindow(raw) {
  var value = raw
  if (typeof value === "string") {
    try { value = JSON.parse(value) } catch (e) { return { ok: false, error: "invalid-json" } }
  }
  if (!isObject(value)) return { ok: false, error: "invalid-activewindow" }
  if (typeof value.fullscreen === "boolean") return { ok: true, fullscreen: value.fullscreen }
  if (typeof value.fullscreen === "number" && isFinite(value.fullscreen) && Math.floor(value.fullscreen) === value.fullscreen)
    return { ok: true, fullscreen: value.fullscreen > 0 }
  return { ok: false, error: "missing-fullscreen" }
}

function parseLockStatus(raw, exitCode) {
  if (exitCode !== 0) return { ok: false, error: "lock-query-failed" }
  if (typeof raw !== "string") return { ok: false, error: "invalid-lock-status" }
  var value = raw.trim()
  if (value === "true") return { ok: true, locked: true }
  if (value === "false") return { ok: true, locked: false }
  return { ok: false, error: "invalid-lock-status" }
}

function parseLayerStatus(raw, exitCode) {
  if (exitCode !== 0) return { ok: false, error: "layer-query-failed" }
  var value = raw
  if (typeof value === "string") {
    try { value = JSON.parse(value) } catch (e) { return { ok: false, error: "invalid-layer-json" } }
  }
  if (!isObject(value)) return { ok: false, error: "invalid-layer-status" }

  var monitors = Object.keys(value)
  if (monitors.length === 0) return { ok: false, error: "missing-layer-monitors" }
  for (var m = 0; m < monitors.length; m++) {
    var monitor = value[monitors[m]]
    if (!isObject(monitor) || !isObject(monitor.levels))
      return { ok: false, error: "invalid-layer-monitor" }
    var levels = Object.keys(monitor.levels)
    if (levels.length === 0) return { ok: false, error: "missing-layer-levels" }
    for (var l = 0; l < levels.length; l++) {
      var layers = monitor.levels[levels[l]]
      if (!Array.isArray(layers)) return { ok: false, error: "invalid-layer-list" }
      for (var i = 0; i < layers.length; i++) {
        var layer = layers[i]
        if (!isObject(layer) || typeof layer.namespace !== "string")
          return { ok: false, error: "invalid-layer-entry" }
        if (layer.namespace === "omarchy-polkit") return { ok: true, active: true }
      }
    }
  }
  return { ok: true, active: false }
}

function isPolkitLayerEvent(name, data) {
  var eventName = String(name || "")
  return (eventName === "openlayer" || eventName === "closelayer")
    && String(data || "").trim() === "omarchy-polkit"
}

function isCatalogChangeEvent(name) {
  return ["configreloaded", "configreloadedv2", "activelayout", "activekeyboardlayout", "keyboardlayout"].indexOf(String(name || "")) !== -1
}

function parseCatalogGeneration(raw, exitCode) {
  if (Number(exitCode) !== 0) return { ok: false, error: "generator-failed" }
  var result
  try { result = JSON.parse(String(raw || "")) } catch (e) {
    return { ok: false, error: "invalid-generator-output" }
  }
  if (!isObject(result) || result.ok !== true
      || typeof result.sourceHash !== "string"
      || !/^sha256:[0-9a-f]{64}$/.test(result.sourceHash)
      || typeof result.changed !== "boolean"
      || !Number.isInteger(result.bindingCount) || result.bindingCount < 0) {
    return { ok: false, error: "invalid-generator-result" }
  }
  return {
    ok: true,
    sourceHash: result.sourceHash,
    changed: result.changed,
    bindingCount: result.bindingCount
  }
}

function shouldReloadCatalogBridge(generation, integrationState, lastReloadHash, activeReloadHash, pendingReloadHash) {
  return isObject(generation)
    && generation.ok === true
    && generation.changed === true
    && integrationState === "enabled"
    && typeof generation.sourceHash === "string"
    && /^sha256:[0-9a-f]{64}$/.test(generation.sourceHash)
    && generation.sourceHash !== String(lastReloadHash || "")
    && generation.sourceHash !== String(activeReloadHash || "")
    && generation.sourceHash !== String(pendingReloadHash || "")
}

function pendingBridgeReloadAfterCatalog(sourceHash, activeReloadHash) {
  var hash = String(sourceHash || "")
  if (!/^sha256:[0-9a-f]{64}$/.test(hash) || hash === String(activeReloadHash || "")) return ""
  return hash
}

function isFullscreenEvent(name) {
  return ["activewindow", "activewindowv2", "fullscreen"].indexOf(String(name || "")) !== -1
}
