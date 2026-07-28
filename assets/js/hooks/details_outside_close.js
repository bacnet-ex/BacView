/** Closes a native <details> element when the user clicks outside or presses Escape. */
const DetailsOutsideClose = {
  mounted() {
    this.onPointerDown = (event) => {
      if (!this.el.open) return
      if (this.el.contains(event.target)) return
      this.el.open = false
    }

    this.onKeyDown = (event) => {
      if (event.key === "Escape" && this.el.open) {
        this.el.open = false
      }
    }

    // Close after choosing a menu item so the panel does not stay open under modals.
    this.onMenuActivate = (event) => {
      const item = event.target.closest("[role='menuitem']")
      if (!item || !this.el.contains(item)) return
      queueMicrotask(() => {
        this.el.open = false
      })
    }

    this.el.addEventListener("click", this.onMenuActivate)

    // Delay so the opening click does not immediately close the menu.
    this.outsideClickTimer = window.setTimeout(() => {
      document.addEventListener("mousedown", this.onPointerDown, true)
      document.addEventListener("keydown", this.onKeyDown, true)
    }, 0)
  },

  destroyed() {
    window.clearTimeout(this.outsideClickTimer)
    this.el.removeEventListener("click", this.onMenuActivate)
    document.removeEventListener("mousedown", this.onPointerDown, true)
    document.removeEventListener("keydown", this.onKeyDown, true)
  },
}

export default DetailsOutsideClose
