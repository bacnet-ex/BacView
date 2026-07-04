const palette = [
  "#22d3ee",
  "#34d399",
  "#fbbf24",
  "#f87171",
  "#a78bfa",
  "#fb7185",
  "#38bdf8",
  "#4ade80",
]

const defaultLocale = "de-DE"

function chartLocale(el) {
  return el.dataset.locale || defaultLocale
}

function formatChartTime(el, seconds) {
  const date = new Date(seconds * 1000)

  return new Intl.DateTimeFormat(chartLocale(el), {
    timeZone: "UTC",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date)
}

function formatChartDateTime(el, seconds) {
  const date = new Date(seconds * 1000)

  return new Intl.DateTimeFormat(chartLocale(el), {
    timeZone: "UTC",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(date)
}

function escapeHtml(text) {
  return String(text)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
}

function formatChartValue(value) {
  if (value == null) return "—"

  if (typeof value === "number") {
    return value.toLocaleString(defaultLocale, {maximumFractionDigits: 3})
  }

  return String(value)
}

const TrendLogChart = {
  mounted() {
    this.visibleSeries = new Set()
    this.activeSeriesMeta = []
    this.handleEvent("trend-chart:update", (payload) => this.renderChart(payload))
    this.el.addEventListener("change", (event) => this.onLegendToggle(event))
  },

  destroyed() {
    this.destroyPlot()
    this.hideTooltip()
  },

  onLegendToggle(event) {
    const input = event.target.closest("[data-series-id]")
    if (!input || input.type !== "checkbox") return

    const seriesId = input.dataset.seriesId

    if (input.checked) {
      this.visibleSeries.add(seriesId)
    } else {
      this.visibleSeries.delete(seriesId)
    }

    if (this.lastPayload) {
      this.renderChart(this.lastPayload)
    }
  },

  destroyPlot() {
    if (this.plot) {
      this.plot.destroy()
      this.plot = null
    }
  },

  hideTooltip() {
    const tooltip = this.el.querySelector("[data-chart-tooltip]")
    if (tooltip) tooltip.classList.add("hidden")
  },

  positionTooltip(tooltip, u) {
    const margin = 12
    const offsetX = 12
    const offsetY = 8

    tooltip.classList.remove("hidden")
    tooltip.style.visibility = "hidden"
    tooltip.style.left = "0px"
    tooltip.style.top = "0px"

    const shellRect = this.el.getBoundingClientRect()
    const tooltipRect = tooltip.getBoundingClientRect()

    const anchorX = shellRect.left + u.cursor.left + u.bbox.left
    const anchorY = shellRect.top + u.cursor.top + u.bbox.top

    let left = anchorX + offsetX
    let top = anchorY - tooltipRect.height - offsetY

    if (left + tooltipRect.width > shellRect.right - margin) {
      left = anchorX - tooltipRect.width - offsetX
    }

    if (top < shellRect.top + margin) {
      top = anchorY + offsetY
    }

    left = Math.max(margin, Math.min(left, window.innerWidth - tooltipRect.width - margin))
    top = Math.max(margin, Math.min(top, window.innerHeight - tooltipRect.height - margin))

    tooltip.style.left = `${left}px`
    tooltip.style.top = `${top}px`
    tooltip.style.visibility = ""
  },

  updateTooltip(u) {
    const tooltip = this.el.querySelector("[data-chart-tooltip]")
    if (!tooltip) return

    const idx = u.cursor.idx

    if (idx == null) {
      this.hideTooltip()
      return
    }

    const seconds = u.data[0][idx]
    const rows = []

    this.activeSeriesMeta.forEach((meta, seriesIndex) => {
      const value = u.data[seriesIndex + 1][idx]
      if (value == null) return

      rows.push({
        color: palette[seriesIndex % palette.length],
        label: meta.label,
        value: formatChartValue(value),
        unit: meta.unit_label || "",
      })
    })

    if (rows.length === 0) {
      this.hideTooltip()
      return
    }

    tooltip.replaceChildren()

    const timeEl = document.createElement("div")
    timeEl.className = "bac-trend-chart-tooltip-time"
    timeEl.textContent = formatChartDateTime(this.el, seconds)
    tooltip.appendChild(timeEl)

    rows.forEach((row) => {
      const rowEl = document.createElement("div")
      rowEl.className = "bac-trend-chart-tooltip-row"

      const swatch = document.createElement("span")
      swatch.className = "bac-trend-chart-tooltip-swatch"
      swatch.style.background = row.color

      const label = document.createElement("span")
      label.className = "bac-trend-chart-tooltip-label"
      label.textContent = row.label

      const value = document.createElement("span")
      value.className = "bac-trend-chart-tooltip-value"
      value.textContent = row.unit ? `${row.value} ${row.unit}` : row.value

      rowEl.append(swatch, label, value)
      tooltip.appendChild(rowEl)
    })

    this.positionTooltip(tooltip, u)
  },

  renderChart(payload) {
    if (!payload || !payload.series || payload.series.length === 0) {
      this.destroyPlot()
      this.hideTooltip()
      this.lastPayload = payload
      this.activeSeriesMeta = []
      this.renderLegend([])
      this.renderEmpty(payload && payload.empty_label)
      return
    }

    if (this.visibleSeries.size === 0) {
      payload.series.forEach((series) => this.visibleSeries.add(series.id))
    }

    this.lastPayload = payload

    const activeSeries = payload.series.filter((series) => this.visibleSeries.has(series.id))
    this.activeSeriesMeta = activeSeries

    if (activeSeries.length === 0) {
      this.destroyPlot()
      this.hideTooltip()
      this.renderEmpty("Keine Serien ausgewählt.")
      this.renderLegend(payload.series)
      return
    }

    const timestamps = this.collectTimestamps(activeSeries)
    const xData = timestamps.map((t) => t / 1000)

    const scales = {x: {time: true}}
    const axes = [{
      stroke: "#64748b",
      grid: {stroke: "#1e293b"},
      space: 80,
      values: (_u, vals) => vals.map((v) => formatChartTime(this.el, v)),
    }]
    const series = [{}]

    payload.scales.forEach((scale, index) => {
      const used = activeSeries.some((s) => s.scale_id === scale.id)
      if (!used) return

      scales[scale.id] = {
        auto: true,
        side: scale.side === "right" ? 1 : 3,
      }

      axes.push({
        scale: scale.id,
        stroke: palette[index % palette.length],
        grid: {show: index === 0},
        label: scale.label,
        size: 56,
        gap: 4,
      })
    })

    activeSeries.forEach((entry, index) => {
      series.push({
        scale: entry.scale_id,
        label: entry.label,
        stroke: palette[index % palette.length],
        width: 2,
        spanGaps: true,
        value: (_, v) => formatChartValue(v),
      })
    })

    const data = [xData, ...activeSeries.map((entry) => {
      return timestamps.map((t) => {
        const point = entry.points.find((p) => p.t === t)
        return point ? point.v : null
      })
    })]

    this.destroyPlot()

    const canvas = this.el.querySelector("[data-chart-canvas]")
    if (!canvas) return

    this.drawPlot(canvas, {scales, axes, series, data, legendSeries: payload.series})
  },

  drawPlot(canvas, ctx, attempt = 0) {
    const canvasHeight = canvas.clientHeight
    const height = Math.max(
      canvasHeight > 0 ? canvasHeight : 0,
      Number(this.el.dataset.height || 0),
      320,
    )

    if (canvasHeight <= 0 && attempt < 4) {
      requestAnimationFrame(() => this.drawPlot(canvas, ctx, attempt + 1))
      return
    }

    const UPlot = globalThis.__bacview_uplot__
    if (!UPlot) return

    this.plot = new UPlot(
      {
        width: canvas.clientWidth,
        height,
        scales: ctx.scales,
        axes: ctx.axes,
        series: ctx.series,
        cursor: {
          drag: {x: true, y: false},
          focus: {prox: 24},
        },
        hooks: {
          setCursor: [(u) => this.updateTooltip(u)],
        },
      },
      ctx.data,
      canvas,
    )

    this.renderLegend(ctx.legendSeries)
    this.renderEmpty(null)
  },

  collectTimestamps(seriesList) {
    const set = new Set()
    seriesList.forEach((series) => {
      series.points.forEach((point) => set.add(point.t))
    })
    return Array.from(set).sort((a, b) => a - b)
  },

  renderLegend(seriesList) {
    const legend = this.el.querySelector("[data-chart-legend]")
    if (!legend) return

    legend.innerHTML = seriesList
      .map((series, index) => {
        const checked = this.visibleSeries.has(series.id) ? "checked" : ""
        const color = palette[index % palette.length]

        return `
          <label class="bac-trend-legend-item" style="--series-color: ${color}">
            <input type="checkbox" data-series-id="${series.id}" ${checked} class="bac-checkbox" />
            <span class="bac-trend-legend-swatch"></span>
            <span class="bac-trend-legend-label">${escapeHtml(series.label)}</span>
            <span class="bac-trend-legend-unit">${series.unit_label || ""}</span>
          </label>
        `
      })
      .join("")
  },

  renderEmpty(message) {
    const empty = this.el.querySelector("[data-chart-empty]")
    if (!empty) return

    if (message) {
      empty.textContent = message
      empty.classList.remove("hidden")
    } else {
      empty.textContent = ""
      empty.classList.add("hidden")
    }
  },
}

export default TrendLogChart