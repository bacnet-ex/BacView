const FOCUSABLE_SELECTOR = [
  'input:not([disabled]):not([type="hidden"]):not([type="button"]):not([type="submit"])',
  "textarea:not([disabled])",
  "select:not([disabled])",
].join(", ")

function preferredField(root) {
  return (
    root.querySelector("[data-autofocus]:not([disabled])") ||
    root.querySelector(FOCUSABLE_SELECTOR)
  )
}

function isTextLike(field) {
  return (
    field.tagName === "TEXTAREA" ||
    (field.tagName === "INPUT" &&
      !["checkbox", "radio", "range", "file", "button", "submit"].includes(field.type))
  )
}

function focusField(field) {
  if (!field) return false

  field.focus({preventScroll: true})

  if (typeof field.select === "function" && isTextLike(field)) {
    field.select()
  }

  return document.activeElement === field
}

function scheduleFocus(root, attempt = 0) {
  const run = () => {
    if (focusField(preferredField(root))) return
    // LiveView patches can land just after mount; retry briefly.
    if (attempt < 8) {
      setTimeout(() => scheduleFocus(root, attempt + 1), 25)
    }
  }

  if (attempt === 0) {
    requestAnimationFrame(run)
  } else {
    run()
  }
}

const FocusFirstInput = {
  mounted() {
    scheduleFocus(this.el)
  },

  updated() {
    // Re-focus when the form body swaps if focus left the modal.
    if (this.el.contains(document.activeElement)) return
    scheduleFocus(this.el)
  },
}

export default FocusFirstInput
