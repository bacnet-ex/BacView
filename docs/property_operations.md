# Property reads, bulk writes, and exports

These paths have different data sources and lifecycles. A full object-property
load is described in the [README](../README.md#device-load-vs-object-property-load).
Complex write forms are described in [choice_schema.md](choice_schema.md).

## One-shot ReadProperty

The application header opens a ReadProperty modal on all three primary routes.
`ReadPropertyHook` initializes its state and handles events and async completion;
`ReadPropertyLive` owns the form and display. The request runs through
`BacView.BACnet.SinglePropertyRead`, independently of a full object-property load.

- A device-instance locator uses `Discovery.resolve_destination/1`: cached
  transport address first, otherwise a targeted Who-Is / I-Am probe.
- An address locator reads directly using the selected transport: IPv4 address
  with optional port, or an MS/TP MAC address.
- Object types and properties accept names or numeric identifiers. An omitted
  property defaults to `present_value`; an optional array index is forwarded to
  the client, including index `0` for an array's length.
- `all` (8), `optional` (80), and `required` (105) are ReadPropertyMultiple
  selectors. A one-shot read rejects them with `{:rpm_only_property, property}`
  and does not call the stack.
- A file object with no property refers to file content and is rejected by this
  ReadProperty path. Use the File object's transfer panel for AtomicReadFile.
- `:unsupported_object_type` triggers a retry with `raw: true`.

A pasted BACnet URI fills the structured fields when the URI text changes.
After that, the locator/object/property fields are authoritative. The modal calls
`SinglePropertyRead.from_form/2`; `from_params/2` is an alias that also ignores a
URI field. Programmatic URI reads use `from_uri/2` explicitly.

Heavy-property exclusions belong to automatic individual property loads. They
do not prevent an explicit one-shot read of a named heavy property.

## Bulk scalar writes

Select objects on a device page and use the selection bar's property-write
action. `BulkWritePropertyLive` prepares the modal and jobs;
`BulkPropertyWrite` parses values and executes them.

The candidate list is the intersection of writable scalar properties from the
selected object types' bacstack schemas. Read-only properties and collection or
complex values are excluded. Types without a schema do not narrow the
intersection; if none have a schema, there are no candidates. A candidate is
schema guidance, not proof that a particular device will accept the write.

The submitted text is parsed separately for each object. Parse failures appear
on that object's row; valid jobs continue. Network writes are sequential through
`DeviceSession.write_property/5`, with `:writing`, `:ok`, and `:error` row updates
and a final completion message. A failed object does not roll back successful
writes or stop later jobs. The modal cannot be closed or resubmitted while busy.

`PropertyWriter.write_opts/3` adds priority only for commandable `present_value`
writes; the default priority is `8`. NULL/relinquish tokens such as `null`, `nil`,
and `reset` are accepted for `present_value`. Successful non-NULL writes to the
summary properties listed in `BulkPropertyWrite` publish a session property
update. This is not a readback of the device's effective value.

## Cached property export

The header's property export opens on every primary route through
`PropertyExportHook` / `PropertyExportLive`. Select loaded devices, objects, and
properties, then download CSV or JSON.

The input is `DeviceSession.scanned/1`, read again when exporting. Exporting
does not issue fresh BACnet reads, and a scan need not contain every property
that an explicit object-property load can retrieve.

- Object keys include device, type, and instance:
  `PropertyExport.object_key/3` produces `device_id|type|instance`.
- Available properties are the union on the selected objects. For bacstack
  objects, use `_metadata.properties_list` plus `_unknown_properties`; plain maps
  contribute their keys. Internal metadata is excluded.
- Numeric unknown property identifiers remain selectable and are exported as
  numeric string keys, such as `"512"`.
- Missing selected values become an empty CSV cell or JSON `null`.
- CSV is UTF-8, uses semicolons, and starts with `device_instance`, `object_type`,
  and `object_instance`. Nested values retain list/struct boundaries; weekly
  schedules use localized weekdays and available binary/multistate text.
- JSON is an array of objects with those three identity fields and a
  `properties` map containing the selected values.

Object/property search and type filters affect the visible choices. The
select-all/clear actions for objects and properties operate on visible matches,
preserving selections outside the current filter.

EDE uses the separate `EdeExport` module and `bacnet_ede`. The global
`MultiEdeExportHook` / `MultiEdeExportLive` path combines selected loaded devices
in one EDE project, preserving device instances and unique key names. It also
uses scanned objects. File and Structured View types are excluded by default.

Both export modals use the existing `download_file` event and the `BacViewRoot`
browser hook. Keep download behavior shared across web, desktop, and Android.

## Focused verification

```bash
mix test test/bac_view/bacnet/single_property_read_test.exs test/bac_view/bacnet/protocol/bacnet_uri_test.exs test/bac_view_web/read_property_modal_live_test.exs
mix test test/bac_view/bacnet/bulk_property_write_test.exs test/bac_view_web/bulk_write_property_live_test.exs test/bac_view_web/bulk_write_property_modal_test.exs
mix test test/bac_view/bacnet/property_export_test.exs test/bac_view_web/property_export_live_test.exs test/bac_view/bacnet/ede_export_test.exs test/bac_view_web/multi_ede_export_live_test.exs
```

Run `mix precommit` for the complete Elixir and host Rust checks. The tests use
fake clients/session data; they do not establish live-device interoperability
or verify browser/native file saving on a target platform.
