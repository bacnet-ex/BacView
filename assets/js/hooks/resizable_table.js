const STORAGE_PREFIX = "bacview-table-columns:"
const MIN_COL_WIDTH = 48

function tableStorageKey(table) {
  if (table.id) return table.id

  const headers = [...table.querySelectorAll("thead th")]
    .map((th) => th.textContent.replace(/\s+/g, " ").trim())
    .join("|")

  return `auto-${headers.slice(0, 120)}`
}

function loadWidths(key) {
  try {
    const raw = localStorage.getItem(`${STORAGE_PREFIX}${key}`)
    return raw ? JSON.parse(raw) : null
  } catch {
    return null
  }
}

function saveWidths(key, widths) {
  localStorage.setItem(`${STORAGE_PREFIX}${key}`, JSON.stringify(widths))
}

function setColumnWidth(th, width) {
  const px = `${width}px`
  th.style.width = px
  th.style.minWidth = px
  th.style.maxWidth = px
}

function applyWidths(table, widths) {
  const ths = [...table.querySelectorAll("thead th")]

  ths.forEach((th, index) => {
    const width = widths[index]
    if (typeof width === "number" && width >= MIN_COL_WIDTH) {
      setColumnWidth(th, width)
    }
  })
}

function getCurrentWidths(table) {
  return [...table.querySelectorAll("thead th")].map((th) => th.offsetWidth)
}

function startDrag(event, table, th, storageKey) {
  const pointerId = event.pointerId ?? "mouse"
  const startX = event.clientX
  const startWidth = th.offsetWidth

  document.body.classList.add("bac-col-resizing")

  const onMove = (moveEvent) => {
    if (moveEvent.pointerId != null && moveEvent.pointerId !== pointerId) return

    const delta = moveEvent.clientX - startX
    const newWidth = Math.max(MIN_COL_WIDTH, startWidth + delta)
    setColumnWidth(th, newWidth)
  }

  const onEnd = (endEvent) => {
    if (endEvent.pointerId != null && endEvent.pointerId !== pointerId) return

    document.body.classList.remove("bac-col-resizing")
    document.removeEventListener("pointermove", onMove)
    document.removeEventListener("pointerup", onEnd)
    document.removeEventListener("pointercancel", onEnd)
    saveWidths(storageKey, getCurrentWidths(table))
  }

  document.addEventListener("pointermove", onMove)
  document.addEventListener("pointerup", onEnd)
  document.addEventListener("pointercancel", onEnd)
}

function ensureResizeHandle(table, th, storageKey) {
  if (th.querySelector(".bac-col-resize-handle")) return

  th.classList.add("bac-table-col-header")

  const handle = document.createElement("span")
  handle.className = "bac-col-resize-handle"
  handle.setAttribute("role", "separator")
  handle.setAttribute("aria-orientation", "vertical")
  handle.setAttribute("aria-label", "Spaltenbreite ändern")
  handle.setAttribute("tabindex", "-1")

  handle.addEventListener("pointerdown", (event) => {
    event.preventDefault()
    event.stopPropagation()
    if (handle.setPointerCapture && event.pointerId != null) {
      handle.setPointerCapture(event.pointerId)
    }
    startDrag(event, table, th, storageKey)
  })

  handle.addEventListener("click", (event) => {
    event.preventDefault()
    event.stopPropagation()
  })

  th.appendChild(handle)
}

export function setupResizableTable(table) {
  if (!table?.matches(".bac-table")) return

  const headerRow = table.querySelector("thead tr")
  if (!headerRow) return

  table.classList.add("bac-table--resizable")
  table.style.tableLayout = "fixed"
  table.style.width = "100%"

  const storageKey = tableStorageKey(table)
  const saved = loadWidths(storageKey)

  const ths = [...headerRow.children].filter((cell) => cell.tagName === "TH")

  if (saved?.length) {
    applyWidths(table, saved)
  }

  ths.forEach((th) => ensureResizeHandle(table, th, storageKey))
}

export function initAllResizableTables(root = document) {
  root.querySelectorAll(".bac-table").forEach(setupResizableTable)
}

const ResizableTable = {
  mounted() {
    setupResizableTable(this.el.querySelector(".bac-table") ?? this.el)
  },

  updated() {
    setupResizableTable(this.el.querySelector(".bac-table") ?? this.el)
  },
}

export default ResizableTable