const FilterMenu = {
  mounted() {
    this.triggerId = this.el.dataset.triggerId
    this.closeEvent = this.el.dataset.closeEvent
    this.el.classList.add("bac-filter-menu--floating")
    this._positioned = false

    this.reposition = (event) => {
      // Ignore scrolls inside the menu (list scrollbar) — only re-anchor when
      // the page or an ancestor scroller moves the trigger.
      if (event?.type === "scroll" && this.el.contains(event.target)) {
        return
      }

      this.position()
    }

    this.reposition()

    this.onPointerDown = (event) => {
      const trigger = document.getElementById(this.triggerId)

      if (this.el.contains(event.target) || trigger?.contains(event.target)) {
        return
      }

      this.pushEvent(this.closeEvent, {})
    }

    window.addEventListener("resize", this.reposition)
    window.addEventListener("scroll", this.reposition, true)

    this.outsideClickTimer = window.setTimeout(() => {
      document.addEventListener("mousedown", this.onPointerDown, true)
    }, 50)
  },

  updated() {
    // LiveView re-renders on checkbox toggles; keep the menu anchored without
    // a full hide/show flash if the trigger has not moved.
    this.position({ soft: true })
  },

  position(opts = {}) {
    const soft = opts.soft === true
    const trigger = document.getElementById(this.triggerId)
    const menu = this.el

    if (!trigger) {
      menu.style.visibility = "visible"
      return
    }

    const gap = 6
    const rect = trigger.getBoundingClientRect()

    menu.style.display = "flex"
    menu.style.position = "fixed"

    // First layout (or hard reposition): measure from a known origin without
    // flashing on soft updates after each filter click.
    if (!soft || !this._positioned) {
      menu.style.visibility = "hidden"
      menu.style.left = "0"
      menu.style.top = "0"
    }

    const menuRect = menu.getBoundingClientRect()

    let top = rect.bottom + gap
    let left = rect.left

    if (top + menuRect.height > window.innerHeight - 8) {
      top = Math.max(8, rect.top - menuRect.height - gap)
    }

    if (left + menuRect.width > window.innerWidth - 8) {
      left = Math.max(8, window.innerWidth - menuRect.width - 8)
    }

    // Soft update: only write styles if the trigger moved enough to matter.
    if (soft && this._positioned) {
      const prevTop = parseFloat(menu.style.top) || 0
      const prevLeft = parseFloat(menu.style.left) || 0

      if (Math.abs(prevTop - top) < 0.5 && Math.abs(prevLeft - left) < 0.5) {
        menu.style.visibility = "visible"
        return
      }
    }

    menu.style.top = `${top}px`
    menu.style.left = `${left}px`
    menu.style.visibility = "visible"
    this._positioned = true
  },

  destroyed() {
    window.clearTimeout(this.outsideClickTimer)
    window.removeEventListener("resize", this.reposition)
    window.removeEventListener("scroll", this.reposition, true)
    document.removeEventListener("mousedown", this.onPointerDown, true)
  },
}

export default FilterMenu
