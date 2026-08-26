const SUMMARY_SELECTOR = ".bac-collapsible-summary"
const DETAILS_SELECTOR = "details.bac-collapsible"

function eventElement(event) {
  const target = event.target
  if (target instanceof Element) return target
  return target?.parentElement ?? null
}

/** Ctrl/Cmd+click a collapser to expand or collapse it and all nested collapsers. */
export function handleNestedCollapsibleClick(event) {
  if (!(event.ctrlKey || event.metaKey)) return false
  if (typeof event.button === "number" && event.button !== 0) return false

  const origin = eventElement(event)
  if (!origin) return false

  const summary = origin.closest(SUMMARY_SELECTOR)
  if (!summary) return false

  const details = summary.closest(DETAILS_SELECTOR)
  if (!details) return false

  event.preventDefault()

  const open = !details.open
  details.open = open
  details.querySelectorAll(DETAILS_SELECTOR).forEach((child) => {
    child.open = open
  })

  return true
}

export function bindNestedCollapsible(root) {
  const onClick = (event) => {
    handleNestedCollapsibleClick(event)
  }

  root.addEventListener("click", onClick, true)
  return () => root.removeEventListener("click", onClick, true)
}
