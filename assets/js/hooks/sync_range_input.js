/**
 * Syncs a range slider and optional tick buttons with a text input target.
 *
 * Expects on the hook element:
 * - data-target: id of the text input that is submitted with the form
 * - a child input[type=range]
 * - optional child buttons with data-tick="<integer>"
 */
const SyncRangeInput = {
  mounted() {
    this.range = this.el.querySelector('input[type="range"]')
    this.targetId = this.el.dataset.target
    this.target = this.targetId ? document.getElementById(this.targetId) : null
    this.ticks = Array.from(this.el.querySelectorAll("[data-tick]"))

    if (!this.range || !this.target) return

    this.onRangeInput = () => {
      this.target.value = this.range.value
      this.range.setAttribute("aria-valuenow", this.range.value)
    }

    this.onTickClick = (event) => {
      const button = event.currentTarget
      const tick = button?.dataset?.tick
      if (tick == null || tick === "") return
      this.range.value = tick
      this.target.value = tick
      this.range.setAttribute("aria-valuenow", tick)
    }

    this.onTargetBlur = () => {
      const raw = String(this.target.value ?? "").trim()
      if (raw === "" || !/^-?\d+$/.test(raw)) return

      const min = Number(this.range.min)
      const max = Number(this.range.max)
      let value = Number(raw)
      if (Number.isNaN(value)) return

      if (value < min) value = min
      if (value > max) value = max

      this.range.value = String(value)
      this.range.setAttribute("aria-valuenow", String(value))
    }

    this.range.addEventListener("input", this.onRangeInput)
    this.ticks.forEach((tick) => tick.addEventListener("click", this.onTickClick))
    this.target.addEventListener("blur", this.onTargetBlur)
  },

  destroyed() {
    if (this.range && this.onRangeInput) {
      this.range.removeEventListener("input", this.onRangeInput)
    }
    if (this.ticks && this.onTickClick) {
      this.ticks.forEach((tick) => tick.removeEventListener("click", this.onTickClick))
    }
    if (this.target && this.onTargetBlur) {
      this.target.removeEventListener("blur", this.onTargetBlur)
    }
  },
}

export default SyncRangeInput
