const SEARCH_INPUT_IDS = [
  "device-search",
  "hierarchy-explorer-search",
  "tree-search",
  "object-search",
]

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
      if (e.target.matches("input, textarea, select, [contenteditable=true]")) return
      if (e.ctrlKey || e.metaKey || e.altKey) return

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
  },

  destroyed() {
    window.removeEventListener("keydown", this.keydownHandler)
  },
}

export default BacViewRoot