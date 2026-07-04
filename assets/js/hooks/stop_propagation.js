const StopPropagation = {
  mounted() {
    this.stop = (event) => event.stopPropagation()
    this.el.addEventListener("click", this.stop, false)
  },

  destroyed() {
    this.el.removeEventListener("click", this.stop, false)
  },
}

export default StopPropagation