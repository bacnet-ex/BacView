const FilterMenu = {
  mounted() {
    this.triggerId = this.el.dataset.triggerId
    this.closeEvent = this.el.dataset.closeEvent
    this.el.classList.add("bac-filter-menu--floating")

    this.reposition = () => this.position()
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
    this.position()
  },

  position() {
    const trigger = document.getElementById(this.triggerId)
    const menu = this.el

    if (!trigger) {
      menu.style.visibility = "visible"
      return
    }
    const gap = 6
    const rect = trigger.getBoundingClientRect()

    menu.style.visibility = "hidden"
    menu.style.display = "flex"
    menu.style.position = "fixed"
    menu.style.left = "0"
    menu.style.top = "0"

    const menuRect = menu.getBoundingClientRect()

    let top = rect.bottom + gap
    let left = rect.left

    if (top + menuRect.height > window.innerHeight - 8) {
      top = Math.max(8, rect.top - menuRect.height - gap)
    }

    if (left + menuRect.width > window.innerWidth - 8) {
      left = Math.max(8, window.innerWidth - menuRect.width - 8)
    }

    menu.style.top = `${top}px`
    menu.style.left = `${left}px`
    menu.style.visibility = "visible"
  },

  destroyed() {
    window.clearTimeout(this.outsideClickTimer)
    window.removeEventListener("resize", this.reposition)
    window.removeEventListener("scroll", this.reposition, true)
    document.removeEventListener("mousedown", this.onPointerDown, true)
  },
}

export default FilterMenu