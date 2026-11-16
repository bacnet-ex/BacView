// In-memory only: survives LiveView navigation within the same tab, but resets on
// full page reload or a new tab (fresh JS context).
const sessionScanForms = new Map()

function scanParamsFromForm(form) {
  const params = {}

  for (const field of form.elements) {
    if (!field.name?.startsWith("scan[")) continue

    const match = field.name.match(/^scan\[(.+)\]$/)
    if (!match) continue

    params[match[1]] = field.value ?? ""
  }

  return params
}

function rememberScanForm(form) {
  const params = scanParamsFromForm(form)
  if (Object.keys(params).length > 0) {
    sessionScanForms.set(form.dataset.transport, params)
  }
}

const ScanFormPersist = {
  mounted() {
    this.persistFromDom = () => {
      rememberScanForm(this.el)
    }

    this.el.addEventListener("input", this.persistFromDom)
    this.el.addEventListener("change", this.persistFromDom)

    this.restoreForTransport()
  },

  updated() {
    if (this.transport !== this.el.dataset.transport) {
      this.restoreForTransport()
    }
  },

  restoreForTransport() {
    this.transport = this.el.dataset.transport
    const scan = sessionScanForms.get(this.transport)
    if (scan) {
      this.pushEvent("scan_form_restore", {scan, transport: this.transport})
    }
  },

  destroyed() {
    rememberScanForm(this.el)
    this.el.removeEventListener("input", this.persistFromDom)
    this.el.removeEventListener("change", this.persistFromDom)
  },
}

export default ScanFormPersist
