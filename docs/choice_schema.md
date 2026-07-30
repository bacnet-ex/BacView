# CHOICE form fields (BeamTypes → editor)

Complex property forms (write modal, collection items) build kind pickers and
active-arm fields from **bacstack typespecs** via `BACnet.BeamTypes`, not from
hand-maintained option lists in the editor.

| Layer | Module | Role |
|-------|--------|------|
| Resolve + cache | `BacView.BACnet.Protocol.BeamTypesCache` | `resolve_struct_type(module, :t)` → field map, `:persistent_term` |
| CHOICE analysis | `BacView.BACnet.Protocol.ChoiceSchema` | Arms, active arm, `apply_arm`, form options |
| Blanks | `BacView.BACnet.Protocol.CollectionItemTemplate` | `blank_from_bac_type/1`, `blank_struct/1` |
| UI consumer | `BacView.BACnet.Protocol.ComplexPropertyEditor` | Collect fields, apply form paths, kind-switch ordering |

LiveView entry points: `ObjectLive` + `WritePropertyModal` call
`ComplexPropertyEditor.form_fields/1` and `apply_form_fields/2`.

---

## Two CHOICE shapes

### Tagged (discriminant field + exclusive payload fields)

BeamTypes example (`CalendarEntry`):

```elixir
%{
  type: {:type_list, [literal: :date, literal: :date_range, literal: :week_n_day]},
  date: {:type_list, [struct: BACnetDate, literal: nil]},
  date_range: {:type_list, [struct: DateRange, literal: nil]},
  week_n_day: {:type_list, [struct: WeekNDay, literal: nil]}
}
```

Detection:

1. A field whose `type_list` members are all `{:literal, atom}` (at least two).
2. For each literal `L`, a same-named field exists as optional payload (`struct | nil` or similar).

Form path for the picker is the real discriminant key (usually `type`).

Covered today: **Recipient**, **CalendarEntry**, **BACnetTimestamp**.

### Inline (single multi-type / optional field)

BeamTypes examples:

```elixir
# NameValue — optional Encoding
%{name: :octet_string, value: {:type_list, [struct: Encoding, literal: nil]}}

# SpecialEvent — multi-struct period
%{
  period: {:type_list, [struct: CalendarEntry, struct: ObjectIdentifier]},
  list: ...,
  priority: ...
}
```

Detection (intentionally strict to avoid false positives):

- Multi-type **or** exactly one payload plus `nil`, **and**
- Either the union includes `nil` (optional), **or** every non-nil member is `{:struct, _}`.

Not treated as CHOICE (plain field):

- `ObjectIdentifier.type` → `{:constant, :object_type} | :unsigned_integer` (type alias, not a UI kind).

Form path for the picker is a **synthetic** discriminant:

| Source field | Synthetic path (stable for UI/tests) |
|--------------|--------------------------------------|
| `value` | `value_kind` |
| `period` | `period_kind` |
| other `f` | `#{f}_kind` |

Covered today: **NameValue** (`value`), **SpecialEvent** (`period`).

---

## Runtime behaviour

### Collect fields

For any `%mod{}` with non-empty `ChoiceSchema.analyze(mod).choices`:

1. Walk BeamTypes field order.
2. On a tagged discriminant: emit kind picker, then recurse into the **active** arm only.
3. On an inline source field: emit synthetic kind picker, then recurse into the payload if present.
4. Plain fields (and nested structs without choices) use the generic walk.

`Encoding` keeps a dedicated collector (internal encoding/type/value UI is not ChoiceSchema v1).

### Apply kind switch

When a form path’s last segment is a CHOICE discriminant:

- Parse arm id against schema options (unknown → `{:error, :invalid_enum}`).
- If kind **unchanged**, leave the struct alone so sibling field edits in the same submit survive.
- If kind **changed**, `ChoiceSchema.apply_arm/3` blanks the new arm and nils inactive tagged legs.

If any discriminant on the submit **changed**, `apply_form_fields/2` applies **only** discriminant paths (stale previous-branch fields are ignored). Discriminants are also sorted last among paths so branch rebuild wins when both appear.

### Blanks

`apply_arm` delegates to `CollectionItemTemplate.blank_from_bac_type/1` by default.

Product-specific blanks live in `ChoiceSchema` (not the editor):

| Context | Override |
|---------|----------|
| `Recipient` + arm `:device` | `ObjectIdentifier{type: :device, instance: 0}` |
| `SpecialEvent` + arm `:calendar_reference` | `ObjectIdentifier{type: :calendar, instance: 0}` |

Dedicated helpers (`blank_recipient/1`, `blank_calendar_entry/1`, …) remain for collection “add item” UX.

---

## Overrides (labels and arm ids only)

Arm **existence** always comes from BeamTypes. Overrides are for polish and path stability only.

Defined on `ChoiceSchema` module attributes:

```elixir
# Stable synthetic form keys
@synthetic_discriminant_keys %{value: :value_kind, period: :period_kind}

# Arm id ≠ module_kind_id(LastSegment) when UI/tests already use another atom
@arm_id_overrides %{
  {SpecialEvent, :period, ObjectIdentifier} => :calendar_reference
}

# Display labels
@label_overrides %{
  none: "None",
  calendar_reference: "Calendar Reference",
  datetime: "Date Time"
}
```

Default arm id for `{:struct, Mod}` is the underscored last module segment
(`Encoding` → `:encoding`, `CalendarEntry` → `:calendar_entry`).

Default label is title-cased underscored name (`:date_range` → `"Date Range"`).

**When to add an override**

| Need | Where |
|------|--------|
| Keep an existing form path / option atom after bacstack renames | `@arm_id_overrides` or `@synthetic_discriminant_keys` |
| Friendlier label without changing the atom | `@label_overrides` |
| Domain-specific blank (device id vs analog_input) | `special_blank/2` in ChoiceSchema |

Do **not** hard-code arm lists in `ComplexPropertyEditor` for shapes ChoiceSchema already understands.

---

## Adding a new bacstack CHOICE type

1. Ensure the typespec is a **tagged** or **inline** shape above.
2. Open the write modal / run `ChoiceSchema.analyze(YourStruct)` in `iex` — arms should appear without editor edits.
3. If option ids or labels must match existing UI, add an override.
4. Add a unit case in `test/bac_view/bacnet/protocol/choice_schema_test.exs` (golden arm ids).
5. If LiveView paths are new, cover collect + kind switch in `complex_property_editor_test.exs`.

If analysis returns no choices, the editor falls back to a generic `Map.from_struct` walk (no kind picker).

---

## Drift guard (NameValue)

bacstack may narrow or widen unions. `choice_schema_test.exs` asserts that
`NameValue` arms are only `:none` and `:encoding` (no `:date_time`). That catches
stale UI assumptions when BeamTypes change.

---

## What is not automated (v1)

- Full generic walk replacement for non-CHOICE structs.
- `Encoding`’s own encoding/type/value controls.
- Perfect labels for every arm without overrides.
- Changing bacstack typespecs from BacView.

---

## Quick iex checks

```elixir
alias BacView.BACnet.Protocol.ChoiceSchema

ChoiceSchema.analyze(BACnet.Protocol.CalendarEntry)
ChoiceSchema.analyze(BACnet.Protocol.NameValue)
ChoiceSchema.options(hd(ChoiceSchema.analyze(BACnet.Protocol.SpecialEvent).choices))
```
