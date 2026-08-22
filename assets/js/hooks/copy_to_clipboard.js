const COPY_FEEDBACK_MS = 1500

async function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    await navigator.clipboard.writeText(text)
    return
  }

  const input = document.createElement("textarea")
  input.value = text
  input.setAttribute("readonly", "")
  input.style.position = "fixed"
  input.style.left = "-9999px"
  document.body.appendChild(input)
  input.select()
  const ok = document.execCommand("copy")
  document.body.removeChild(input)
  if (!ok) throw new Error("copy failed")
}

const CopyToClipboard = {
  mounted() {
    this.onClick = async (event) => {
      event.preventDefault()
      const text = this.el.getAttribute("data-clipboard-text") || ""
      if (!text) return

      try {
        await copyText(text)
        this.showCopied()
      } catch (_err) {
        // Clipboard can fail; the button still exposes the URI via data-clipboard-text.
      }
    }

    this.el.addEventListener("click", this.onClick)
  },

  destroyed() {
    this.clearCopiedTimer()
    this.el.removeEventListener("click", this.onClick)
  },

  showCopied() {
    const copiedLabel = this.el.getAttribute("data-copied-label")
    if (!this.idleLabel) {
      this.idleLabel = this.el.getAttribute("aria-label")
      this.idleTitle = this.el.getAttribute("title")
    }

    this.el.setAttribute("data-copied", "true")
    if (copiedLabel) {
      this.el.setAttribute("aria-label", copiedLabel)
      this.el.setAttribute("title", copiedLabel)
    }

    this.clearCopiedTimer()
    this.copiedTimer = window.setTimeout(() => this.clearCopied(), COPY_FEEDBACK_MS)
  },

  clearCopied() {
    this.el.removeAttribute("data-copied")
    if (this.idleLabel) this.el.setAttribute("aria-label", this.idleLabel)
    if (this.idleTitle) this.el.setAttribute("title", this.idleTitle)
    this.clearCopiedTimer()
  },

  clearCopiedTimer() {
    if (this.copiedTimer) {
      window.clearTimeout(this.copiedTimer)
      this.copiedTimer = null
    }
  },
}

export default CopyToClipboard
