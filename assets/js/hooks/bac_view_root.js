import {initAllResizableTables} from "./resizable_table"

const SEARCH_INPUT_IDS = [
  "device-search",
  "hierarchy-explorer-search",
  "tree-search",
  "object-search",
]

const FORM_FIELD_SELECTOR = "input, textarea, select, [contenteditable=true]"

// Full-screen / dialog modals (write property, charts, settings, shortcuts help, …).
// While open, only Escape is forwarded so typing "1"/"r" does not fire tab/action shortcuts.
const MODAL_OPEN_SELECTOR = ".bac-modal-backdrop"

// Only Escape bypasses form-field focus and open modals (dismiss / close).
// Shortcut keys like "r" and "?" are typed normally inside inputs.
const GLOBAL_SHORTCUT_KEYS = new Set(["Escape"])

function isFormField(el) {
  return el?.matches?.(FORM_FIELD_SELECTOR) ?? false
}

function isGlobalShortcutKey(e) {
  return GLOBAL_SHORTCUT_KEYS.has(e.key)
}

function isModalOpen() {
  return document.querySelector(MODAL_OPEN_SELECTOR) != null
}

function focusVisibleSearch() {
  for (const id of SEARCH_INPUT_IDS) {
    const input = document.getElementById(id)
    if (!input || input.closest("[hidden]") || input.offsetParent === null || input.disabled) {
      continue
    }

    input.focus()
    if (typeof input.select === "function") input.select()
    return true
  }

  return false
}

const BacViewRoot = {
  mounted() {
    this.keydownHandler = (e) => {
      if (isFormField(e.target) && !isGlobalShortcutKey(e)) return
      // Modal open but field not focused: still block shortcuts (user may intend to type).
      if (isModalOpen() && !isGlobalShortcutKey(e)) return
      if (e.ctrlKey || e.metaKey || e.altKey) return
      if (e.repeat) return

      this.pushEvent("global_keydown", {key: e.key, code: e.code, shift: e.shiftKey})
    }

    window.addEventListener("keydown", this.keydownHandler)

    this.handleEvent("persist_locale", ({locale}) => {
      localStorage.setItem("bacview_locale", locale)
      document.documentElement.lang = locale
      document.cookie = `bacview_locale=${locale};path=/;max-age=31536000;SameSite=Lax`
    })

    this.handleEvent("scroll_to_object", ({type, instance}) => {
      const row = document.getElementById(`object-${type}-${instance}`)
      if (row) {
        row.scrollIntoView({behavior: "smooth", block: "center"})
        row.classList.add("bg-primary/20")
        setTimeout(() => row.classList.remove("bg-primary/20"), 2000)
      }
    })

    this.handleEvent("focus_search", () => {
      focusVisibleSearch()
    })

    this.handleEvent("log_error", ({action, message, detail}) => {
      console.error(`[BacView] ${action || "error"}: ${message}`, detail)
    })

    this.handleEvent("download_file", ({content, filename, mime, encoding}) => {
      let blobData = content
      if (encoding === "base64" && typeof content === "string") {
        const binary = atob(content)
        const bytes = new Uint8Array(binary.length)
        for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
        blobData = bytes
      }
      const blob = new Blob([blobData], {type: mime || "application/octet-stream"})
      const url = URL.createObjectURL(blob)
      const anchor = document.createElement("a")
      anchor.href = url
      anchor.download = filename
      anchor.click()
      URL.revokeObjectURL(url)
    })

    this.initResizableTables()
  },

  updated() {
    this.initResizableTables()
  },

  initResizableTables() {
    initAllResizableTables(this.el)
  },

  destroyed() {
    window.removeEventListener("keydown", this.keydownHandler)
  },
}

export default BacViewRoot