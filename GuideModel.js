.pragma library

function exactModifiers(binding, mask) {
  if (!binding || !Array.isArray(binding.modifiers)) return false
  var expected = String(mask || "SUPER").split("_")
  if (expected.length !== binding.modifiers.length) return false
  for (var i = 0; i < expected.length; i++) {
    if (expected[i] !== binding.modifiers[i]) return false
  }
  return true
}

function displayCombo(binding) {
  var combo = String(binding && binding.combo || "")
  var key = String(binding && binding.key || "")
  var code = /^code:([0-9]+)$/i.exec(key)
  if (code) {
    var replacement = "KEY " + code[1]
    if (combo === "" || /^code:[0-9]+$/i.test(combo)) return replacement
    return combo.replace(/code:[0-9]+$/i, replacement)
  }
  return combo !== "" ? combo : key
}

function priorityLookup(ids) {
  var result = {}
  var source = Array.isArray(ids) ? ids : []
  for (var i = 0; i < source.length; i++) {
    var id = String(source[i] || "")
    if (id !== "" && result[id] === undefined) result[id] = i
  }
  return result
}

function rankedBindings(catalog, mask, priorityIds) {
  var source = catalog && Array.isArray(catalog.bindings) ? catalog.bindings : []
  var priorities = priorityLookup(priorityIds)
  var matches = []
  for (var i = 0; i < source.length; i++) {
    var binding = source[i]
    if (!binding || binding.trackable !== true || binding.guideEligible !== true) continue
    if (!exactModifiers(binding, mask)) continue
    matches.push({
      id: String(binding.id || ""),
      combo: displayCombo(binding),
      description: String(binding.description || ""),
      category: String(binding.category || "other"),
      priority: priorities[binding.id] === undefined ? -1 : priorities[binding.id],
      catalogOrder: i
    })
  }
  matches.sort(function(a, b) {
    var aPriority = Number(a.priority)
    var bPriority = Number(b.priority)
    if (aPriority >= 0 || bPriority >= 0) {
      if (aPriority < 0) return 1
      if (bPriority < 0) return -1
      if (aPriority !== bPriority) return aPriority - bPriority
    }
    return a.catalogOrder - b.catalogOrder
  })
  return matches
}

function cardModel(catalog, mask, limit, priorityIds) {
  var matches = rankedBindings(catalog, mask, priorityIds)
  var count = Number(limit)
  if (!isFinite(count) || count < 1) count = 12
  count = Math.floor(count)
  return { items: matches.slice(0, count), total: matches.length, more: Math.max(0, matches.length - count) }
}

function number(value, fallback) {
  var parsed = Number(value)
  return isFinite(parsed) && parsed > 0 ? parsed : fallback
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value))
}

function canopyMetrics(viewport, expanded) {
  var width = number(viewport && viewport.width, 1920)
  var compact = width >= 2400 ? 206 : width >= 1800 ? 182 : 158
  if (expanded === true) compact = Math.max(142, compact - 18)
  var gap = width >= 1800 ? 8 : 6
  var margin = width >= 1800 ? 18 : 10
  var columns = Math.floor((width - margin * 2 + gap) / (compact + gap))
  columns = clamp(columns, 5, expanded === true ? 12 : 9)
  if (columns % 2 === 0 && columns > 5) columns -= 1
  var cornerWidth = Math.round(compact * 0.78)
  // Reserve the original wider center slot so the secondary row and its
  // attached corner caps keep their stepped canopy geometry.
  var moreWidth = Math.round(compact * 1.45)
  var secondaryLeftCount = Math.ceil(Math.max(0, columns - 1) / 2)
  var outerSecondaryLeft = width / 2 - moreWidth / 2 - gap
    - (compact + gap) * secondaryLeftCount
  var cornerX = outerSecondaryLeft - gap - cornerWidth
  var cornerCaps = expanded !== true
    && cornerX >= margin
  return {
    width: width,
    cardWidth: compact,
    // A two-line card keeps the complete shortcut and its purpose legible
    // without making the canopy any wider.
    cardHeight: expanded === true ? 42 : 46,
    gap: gap,
    margin: margin,
    crownColumns: columns,
    cornerWidth: cornerWidth,
    cornerX: Math.round(cornerX),
    cornerCaps: cornerCaps,
    wingPairs: expanded !== true && width >= 1800 ? 4 : 2
  }
}

function centeredOffsets(count) {
  var total = Math.max(0, Math.floor(Number(count) || 0))
  var result = []
  if (total % 2 === 1) {
    result.push(0)
    for (var distance = 1; result.length < total; distance++) {
      result.push(-distance)
      if (result.length < total) result.push(distance)
    }
    return result
  }
  for (var half = 0.5; result.length < total; half += 1) {
    result.push(-half)
    if (result.length < total) result.push(half)
  }
  return result
}

function placeCentered(items, start, count, metrics, y, tier, opacity) {
  var result = []
  var offsets = centeredOffsets(count)
  var center = metrics.width / 2
  var step = metrics.cardWidth + metrics.gap
  for (var i = 0; i < count; i++) {
    var binding = items[start + i]
    if (!binding) break
    result.push({
      binding: binding,
      x: Math.round(center + offsets[i] * step - metrics.cardWidth / 2),
      y: Math.round(y),
      width: metrics.cardWidth,
      height: metrics.cardHeight,
      tier: tier,
      opacity: opacity
    })
  }
  return result
}

function append(destination, values) {
  for (var i = 0; i < values.length; i++) destination.push(values[i])
}

function collapsedCanopyLayout(source, metrics) {
  var crown = metrics.crownColumns
  var placements = []
  var topCount = Math.min(crown, source.length)
  append(placements, placeCentered(source, 0, topCount, metrics, 0, "primary", 1))

  var center = metrics.width / 2
  // Keep the wide reserved slot for secondary-card placement, but draw the
  // hover affordance itself at normal card width so its replacement is stable.
  var moreSlotWidth = Math.round(metrics.cardWidth * 1.45)
  var moreWidth = metrics.cardWidth
  var secondCount = crown - 1
  var secondY = metrics.cardHeight + metrics.gap
  var cursor = topCount
  var i
  // The overflow pill occupies the visual center of this row. Continue the
  // priority reading order from its left and right edges: closest left,
  // closest right, then move outward in alternating pairs.
  for (i = 0; i < secondCount; i++) {
    var secondaryBinding = source[cursor++]
    if (!secondaryBinding) break
    var secondaryDistance = Math.floor(i / 2)
    var secondaryLeft = i % 2 === 0
    placements.push({ binding: secondaryBinding,
      x: Math.round(secondaryLeft
        ? center - moreSlotWidth / 2 - metrics.gap - (metrics.cardWidth + metrics.gap) * (secondaryDistance + 1)
        : center + moreSlotWidth / 2 + metrics.gap + (metrics.cardWidth + metrics.gap) * secondaryDistance),
      y: secondY, width: metrics.cardWidth, height: metrics.cardHeight,
      tier: "secondary", opacity: 0.9 })
  }

  for (i = 0; i < metrics.wingPairs * 2; i++) {
    var wingBinding = source[cursor++]
    if (!wingBinding) break
    var wingRow = Math.floor(i / 2)
    var onLeft = i % 2 === 0
    placements.push({
      binding: wingBinding,
      x: onLeft ? metrics.margin : metrics.width - metrics.margin - metrics.cardWidth,
      y: Math.round((metrics.cardHeight + metrics.gap) * (2 + wingRow)),
      width: metrics.cardWidth,
      height: metrics.cardHeight,
      tier: "wing",
      opacity: wingRow === 0 ? 0.76 : 0.62
    })
  }

  // Wide displays have usable upper corner space outside the central crown.
  // These are intentionally the last collapsed items: they add capacity
  // without competing with the center-first priority reading order.
  if (metrics.cornerCaps) {
    for (i = 0; i < 2; i++) {
      var cornerBinding = source[cursor++]
      if (!cornerBinding) break
      placements.push({
        binding: cornerBinding,
        x: i === 0 ? metrics.cornerX : metrics.width - metrics.cornerX - metrics.cornerWidth,
        y: secondY,
        width: metrics.cornerWidth,
        height: metrics.cardHeight,
        tier: "corner",
        opacity: 0.54
      })
    }
  }

  var height = (metrics.cardHeight + metrics.gap) * (2 + metrics.wingPairs) - metrics.gap
  var more = Math.max(0, source.length - placements.length)
  return {
    items: placements,
    more: more,
    total: source.length,
    visibleCount: placements.length,
    expanded: false,
    height: height,
    overflow: more > 0 ? {
        x: Math.round(center - moreWidth / 2),
        y: secondY,
        width: moreWidth,
        height: metrics.cardHeight
      } : null,
    metrics: metrics
  }
}

function expandedCanopyLayout(source, metrics, collapsed) {
  if (collapsed.more === 0) return collapsed

  var placements = collapsed.items.slice()
  var used = {}
  var step = metrics.cardHeight + metrics.gap
  var i

  // The collapsed canopy is the visual frame. Expansion must not move a
  // visible card, because the frame is what makes the guide scannable.
  for (i = 0; i < collapsed.items.length; i++) {
    var existing = collapsed.items[i]
    used[existing.binding.id] = true
  }

  var remaining = []
  for (i = 0; i < source.length; i++)
    if (used[source[i].id] !== true) remaining.push(source[i])

  // The first remaining binding fills the old +MORE center. The rest are
  // balanced across the open interior of the fixed left/right wing frame;
  // unlike the old reflow, no already-visible card changes its position.
  var centerBinding = remaining.shift()
  if (centerBinding) append(placements, placeCentered([centerBinding], 0, 1, metrics,
    step, "mound", 1))

  var interiorCapacity = Math.max(1, Math.floor(
    (metrics.width - metrics.margin * 2 - metrics.cardWidth * 2 - metrics.gap * 2)
      / (metrics.cardWidth + metrics.gap)))
  var rowCount = remaining.length > 0
    ? Math.ceil(remaining.length / interiorCapacity) : 0
  var base = rowCount > 0 ? Math.floor(remaining.length / rowCount) : 0
  var extra = rowCount > 0 ? remaining.length % rowCount : 0
  for (var row = 0, cursor = 0; row < rowCount; row++) {
    var count = base + (row < extra ? 1 : 0)
    append(placements, placeCentered(remaining, cursor, count, metrics,
      (row + 2) * step, "mound", 1))
    cursor += count
  }
  var height = Math.max(collapsed.height, (rowCount + 2) * step - metrics.gap)
  return {
    items: placements,
    more: 0,
    total: source.length,
    visibleCount: source.length,
    expanded: true,
    height: height,
    overflow: null,
    metrics: metrics
  }
}

function canopyLayout(items, viewport, expanded) {
  var source = Array.isArray(items) ? items : []
  // Expansion preserves the collapsed card dimensions and coordinates.
  var metrics = canopyMetrics(viewport, false)
  var collapsed = collapsedCanopyLayout(source, metrics)
  if (expanded === true) return expandedCanopyLayout(source, metrics, collapsed)
  return collapsed
}

function laneCounts(catalog) {
  var result = { SHIFT: 0, CTRL: 0, ALT: 0 }
  var source = catalog && Array.isArray(catalog.bindings) ? catalog.bindings : []
  for (var i = 0; i < source.length; i++) {
    var modifiers = source[i] && source[i].modifiers
    if (!Array.isArray(modifiers) || modifiers.length !== 2 || modifiers[0] !== "SUPER") continue
    if (result[modifiers[1]] !== undefined) result[modifiers[1]] += 1
  }
  return result
}

function eligible(state) {
  if (!state || state.integrationState !== "enabled" || state.catalogState !== "ready") return false
  if (state.lockStateKnown !== true || state.credentialPromptStateKnown !== true) return false
  if (state.desktopLocked === true || state.credentialPromptActive === true) return false
  return state.showInFullscreen === true || state.activeWindowFullscreen !== true
}

function delayMode(guideVisible, delay) {
  if (guideVisible !== true) return "hidden"
  var value = Number(delay)
  if (value === 0) return "immediate"
  if (value === 80 || value === 150 || value === 250) return "delayed"
  return "disabled"
}

function focusedVisible(shouldShow, screenName, focusedName) {
  return shouldShow === true && String(screenName || "") !== ""
    && String(screenName || "") === String(focusedName || "")
}
