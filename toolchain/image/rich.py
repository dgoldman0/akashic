"""The rich terminal's host bounds for an image's session.

RichTerminalProfile holds the bounds an image gives MegaPad's hosted rich
terminal, and the desktop-apt1 constants size the canonical Desktop's: the
terminal geometry it accepts, the retained policy's budgets and the
shell's quotas.  A session's server takes its policies from them.
"""

from __future__ import annotations

from dataclasses import dataclass, replace

from .megapad import MEGAPAD_ROOT  # noqa: F401  (MegaPad's modules follow)

from rich_terminal.retained_model import IMAGE_FORMATS, RetainedFeature, RetainedPolicy
from shared.session import RichTerminalSessionPolicy


# The rich Desktop machine has 384 MiB of external memory.  Desk's rich
# storage (the engine's banks, the screen and shell producers' storage and
# the shell model's snapshot) is not sized up front: it starts small and
# grows from the system heap in the general-XMEM partition as the screen and
# its content need.  After networking, the rich-terminal module and the
# cold Desk closure load, the general partition has about 178 MiB free;
# Desk then needs about 15 MiB for a 280 by 84 screen with Pad open.  The
# machine's memory is the only limit on that growth.  Networking takes a
# quarter of the general partition for its tables, so changing the machine
# size also changes them.
DESKTOP_APT1_EXT_MEM_MIB = 384


@dataclass(frozen=True)
class RichTerminalProfile:
    """Product bounds for one explicitly rich-terminal-enabled profile."""

    guest_rx_bytes: int
    guest_tx_bytes: int
    guest_collection_native_bytes: int
    guest_data_graphics_native_bytes: int
    guest_status_field_native_bytes: int
    guest_field_native_bytes: int
    host_policy: RichTerminalSessionPolicy
    retained_policy: RetainedPolicy | None = None
    # Desk also publishes its panes and taskbar through the shell producer,
    # whose storage grows from Desk's memory as each candidate needs.
    shell: bool = False

    def __post_init__(self) -> None:
        if not isinstance(self.host_policy, RichTerminalSessionPolicy):
            raise TypeError("host_policy must be a RichTerminalSessionPolicy")
        if self.retained_policy is not None and not isinstance(
            self.retained_policy, RetainedPolicy
        ):
            raise TypeError("retained_policy must be a RetainedPolicy or None")
        for name in (
            "guest_rx_bytes",
            "guest_tx_bytes",
            "guest_collection_native_bytes",
            "guest_data_graphics_native_bytes",
            "guest_status_field_native_bytes",
            "guest_field_native_bytes",
        ):
            value = getattr(self, name)
            if isinstance(value, bool) or not isinstance(value, int):
                raise TypeError(f"{name} must be an integer")
        if not isinstance(self.shell, bool):
            raise TypeError("shell must be a bool")
        if not 0 < self.guest_collection_native_bytes <= 0xFFFFFFFF:
            raise ValueError(
                "guest_collection_native_bytes must be a positive u32"
            )
        if self.guest_collection_native_bytes & 7:
            raise ValueError(
                "guest_collection_native_bytes must be eight-byte aligned"
            )
        if not 0 < self.guest_data_graphics_native_bytes <= 0xFFFFFFFF:
            raise ValueError(
                "guest_data_graphics_native_bytes must be a positive u32"
            )
        # One nonempty canonical graph needs its 112-byte UDG header and the
        # smallest current 128-byte STATUS record.  These are wire/model ABI
        # sizes, not a product graph-count limit.
        if self.guest_data_graphics_native_bytes < 112 + 128:
            raise ValueError(
                "guest_data_graphics_native_bytes cannot admit one "
                "instrument graph"
            )
        if self.guest_data_graphics_native_bytes & 7:
            raise ValueError(
                "guest_data_graphics_native_bytes must be eight-byte aligned"
            )
        if not 72 <= self.guest_status_field_native_bytes <= 0xFFFFFFFF:
            raise ValueError(
                "guest_status_field_native_bytes must admit one field in a u32 bank"
            )
        if self.guest_status_field_native_bytes & 7:
            raise ValueError(
                "guest_status_field_native_bytes must be eight-byte aligned"
            )
        if not 192 <= self.guest_field_native_bytes <= 0xFFFFFFFF:
            raise ValueError("guest_field_native_bytes must admit one FIELD in a u32 bank")
        if self.guest_field_native_bytes & 7:
            raise ValueError("guest_field_native_bytes must be eight-byte aligned")
        if self.guest_rx_bytes < 4_168:
            raise ValueError("guest_rx_bytes must admit the control reserve")
        # Screen width sets no bound: PT splits CELL spans, and the engine
        # refuses a terminal glyph-run limit the transport cannot carry.
        required_payload = max(
            80 + self.guest_collection_native_bytes,
            104 + self.guest_data_graphics_native_bytes,
            96 + self.guest_status_field_native_bytes,
            80 + self.guest_field_native_bytes,
        )
        if self.shell:
            required_payload = max(required_payload, DESKTOP_APT1_SHELL_MAX_PAYLOAD_BYTES)
        maximum_payload = required_payload
        if self.retained_policy is not None:
            if (
                self.retained_policy.client_to_terminal_max_payload
                < required_payload
            ):
                raise ValueError(
                    "retained client payload cannot admit a selected native object"
                )
            maximum_payload = max(
                maximum_payload,
                self.retained_policy.client_to_terminal_max_payload,
            )
        if self.guest_tx_bytes < max(73, 40 + maximum_payload):
            raise ValueError("guest_tx_bytes cannot admit a maximum frame")

    def configuration(self, cols: int, rows: int):
        return self.host_policy.configuration(
            cols,
            rows,
            retained_policy=self.retained_policy,
        )


# The geometry the simulated terminal itself accepts, and the per-terminal
# budgets derived from it below.  Desk sizes nothing from them: a larger
# screen grows Desk's storage, and the terminal grants or refuses its space.
DESKTOP_APT1_MAX_COLS = 400
DESKTOP_APT1_MAX_ROWS = 200
DESKTOP_APT1_MAX_CELLS = DESKTOP_APT1_MAX_COLS * DESKTOP_APT1_MAX_ROWS
DESKTOP_APT1_UIDL_BINDINGS = 32
DESKTOP_APT1_UIDL_RECORDS = 256
DESKTOP_APT1_UIDL_TEXT_BYTES = 12_288
DESKTOP_APT1_UIDL_AGGREGATE_RECORDS = (
    DESKTOP_APT1_UIDL_BINDINGS * DESKTOP_APT1_UIDL_RECORDS
)
DESKTOP_APT1_UIDL_AGGREGATE_TEXT_BYTES = (
    DESKTOP_APT1_UIDL_BINDINGS * DESKTOP_APT1_UIDL_TEXT_BYTES
)
# This is the exact default selected by desk-apt1.f from the aggregate UIDL
# text bank.  Keep it explicit in the product profile so the host policy and
# caller-owned guest banks cannot silently diverge.
DESKTOP_APT1_COLLECTION_NATIVE_BYTES = (
    DESKTOP_APT1_UIDL_AGGREGATE_TEXT_BYTES
)
# Separate caller-selected static-field bytes. One canonical field needs at
# least its 72-byte native header; no application-specific field count is used.
DESKTOP_APT1_STATUS_FIELD_HEADER_BYTES = 72
DESKTOP_APT1_STATUS_FIELD_NATIVE_BYTES = DESKTOP_APT1_UIDL_AGGREGATE_TEXT_BYTES
DESKTOP_APT1_MAX_STATUS_FIELDS = (
    DESKTOP_APT1_STATUS_FIELD_NATIVE_BYTES // DESKTOP_APT1_STATUS_FIELD_HEADER_BYTES
)
DESKTOP_APT1_STATUS_FIELD_PAYLOAD_FIXED_BYTES = 96
DESKTOP_APT1_STATUS_FIELD_FRAME_FIXED_BYTES = 136
# A canonical FIELD needs a 224-byte root; each CHOICE consumes at least its
# 24-byte native record. These independent conservative bounds account for
# roots and content items without hard-coding Sound Lab's four parameters.
DESKTOP_APT1_FIELD_HEADER_BYTES = 224
DESKTOP_APT1_FIELD_CHOICE_HEADER_BYTES = 24
DESKTOP_APT1_FIELD_NATIVE_BYTES = DESKTOP_APT1_UIDL_AGGREGATE_TEXT_BYTES
DESKTOP_APT1_MAX_FIELDS = DESKTOP_APT1_FIELD_NATIVE_BYTES // DESKTOP_APT1_FIELD_HEADER_BYTES
DESKTOP_APT1_FIELD_CHOICES = (
    DESKTOP_APT1_FIELD_NATIVE_BYTES // DESKTOP_APT1_FIELD_CHOICE_HEADER_BYTES
)
# Match desk-apt1.f's renderer-neutral DATA_GRAPHICS bank: every possible
# UIDL record may be one minimum 112-byte UDG root.  Object, region, operation,
# UTF-8, transport, and transaction capacities below all derive from this
# selected byte bank rather than from any applet's current graph count.
DESKTOP_APT1_DATA_GRAPHICS_HEADER_BYTES = 112
DESKTOP_APT1_DATA_GRAPHICS_STATUS_RECORD_BYTES = 128
DESKTOP_APT1_DATA_GRAPHICS_NATIVE_BYTES = (
    DESKTOP_APT1_UIDL_AGGREGATE_RECORDS
    * DESKTOP_APT1_DATA_GRAPHICS_HEADER_BYTES
)
# Complete snapshot storage bounds include one DEFINE per native history and
# at most one sample chunk per i64 value. Declared history reservations are
# independent finite limits; sparse/empty histories still consume their full
# authored capacity.
DESKTOP_APT1_SERIES_HEADER_BYTES = 72
DESKTOP_APT1_MAX_SERIES = (
    DESKTOP_APT1_DATA_GRAPHICS_NATIVE_BYTES // DESKTOP_APT1_SERIES_HEADER_BYTES
)
DESKTOP_APT1_SERIES_MAX_CHUNKS = DESKTOP_APT1_DATA_GRAPHICS_NATIVE_BYTES // 8
DESKTOP_APT1_SERIES_OPERATIONS = (
    DESKTOP_APT1_MAX_SERIES + DESKTOP_APT1_SERIES_MAX_CHUNKS
)
DESKTOP_APT1_SERIES_WIRE_BYTES = (
    80 * DESKTOP_APT1_SERIES_OPERATIONS + DESKTOP_APT1_DATA_GRAPHICS_NATIVE_BYTES
)
DESKTOP_APT1_MAX_HISTORY_PER_SERIES = 32_768
# A POLYLINE keeps each point as two native cells, sixteen bytes, in the same
# DATA_GRAPHICS bank, so that bank bounds both the points of one line and the
# points of every line.  An owner asks for only the points its lines need.
DESKTOP_APT1_POLYLINE_POINT_BYTES = 16
DESKTOP_APT1_MAX_PATH_POINTS = (
    DESKTOP_APT1_DATA_GRAPHICS_NATIVE_BYTES // DESKTOP_APT1_POLYLINE_POINT_BYTES
)
DESKTOP_APT1_TOTAL_SAMPLE_SLOTS = 65_536
DESKTOP_APT1_MAX_SAMPLES_PER_APPEND = 4_096
# Two thirds of the machine is general XMEM, where Desk's rich storage grows;
# the dictionary keeps about 126 MiB and the cold closure uses about 2 MiB.
DESKTOP_APT1_XMEM_RESERVE_BYTES = 256 << 20
if DESKTOP_APT1_DATA_GRAPHICS_NATIVE_BYTES < (
    DESKTOP_APT1_DATA_GRAPHICS_HEADER_BYTES
    + DESKTOP_APT1_DATA_GRAPHICS_STATUS_RECORD_BYTES
):
    raise ValueError(
        "desktop-apt1 DATA_GRAPHICS bank cannot admit one instrument graph"
    )
DESKTOP_APT1_DATA_GRAPHICS_DESCRIPTORS = min(
    DESKTOP_APT1_DATA_GRAPHICS_NATIVE_BYTES
    // DESKTOP_APT1_DATA_GRAPHICS_HEADER_BYTES,
    DESKTOP_APT1_UIDL_AGGREGATE_RECORDS,
)
DESKTOP_APT1_MAX_INSTRUMENTS = (
    DESKTOP_APT1_DATA_GRAPHICS_NATIVE_BYTES
    // DESKTOP_APT1_DATA_GRAPHICS_STATUS_RECORD_BYTES
)
DESKTOP_APT1_INSTRUMENT_REGIONS = min(
    DESKTOP_APT1_DATA_GRAPHICS_DESCRIPTORS,
    DESKTOP_APT1_MAX_INSTRUMENTS,
)
DESKTOP_APT1_MAX_REGIONS = 1 + DESKTOP_APT1_INSTRUMENT_REGIONS
# Match the producer's worst-case canonical graph density: one 80-byte TABSET
# root, then every remaining semantic control may be a minimum 48-byte TAB.
# This is a storage negotiation bound derived from the caller-selected native
# bank, not a product tab-count limit.
DESKTOP_APT1_COLLECTION_TABSET_FIXED_BYTES = 80
DESKTOP_APT1_COLLECTION_TAB_MIN_BYTES = 48
DESKTOP_APT1_COLLECTION_ITEM_HEADER_BYTES = 64
DESKTOP_APT1_CONTROL_FRAME_FIXED_BYTES = 120
DESKTOP_APT1_FRAME_HEADER_BYTES = 40
DESKTOP_APT1_REGION_FRAME_BYTES = 104
DESKTOP_APT1_INSTRUMENT_FRAME_FIXED_BYTES = 152
DESKTOP_APT1_READOUT_PAYLOAD_FIXED_BYTES = 104
DESKTOP_APT1_CONTROL_PAYLOAD_FIXED_BYTES = (
    DESKTOP_APT1_CONTROL_FRAME_FIXED_BYTES
    - DESKTOP_APT1_FRAME_HEADER_BYTES
)


def desktop_apt1_collection_control_capacity(native_bytes: int) -> int:
    """Return the canonical TABSET/TAB control density for a native bank."""

    if isinstance(native_bytes, bool) or not isinstance(native_bytes, int):
        raise TypeError("native collection capacity must be an integer")
    if not 0 < native_bytes <= 0xFFFFFFFF:
        return 0
    if native_bytes < DESKTOP_APT1_COLLECTION_TABSET_FIXED_BYTES:
        return 0
    controls = 1 + (
        native_bytes - DESKTOP_APT1_COLLECTION_TABSET_FIXED_BYTES
    ) // DESKTOP_APT1_COLLECTION_TAB_MIN_BYTES
    if not 0 < controls <= 0xFFFFFFFF:
        return 0
    return controls


DESKTOP_APT1_COLLECTION_CONTROLS = (
    desktop_apt1_collection_control_capacity(
        DESKTOP_APT1_COLLECTION_NATIVE_BYTES
    )
)
if DESKTOP_APT1_COLLECTION_CONTROLS == 0:
    raise ValueError(
        "desktop-apt1 native collection bank cannot admit a canonical root"
    )
DESKTOP_APT1_CONTENT_ITEMS = (
    DESKTOP_APT1_COLLECTION_NATIVE_BYTES
    // DESKTOP_APT1_COLLECTION_ITEM_HEADER_BYTES
    + DESKTOP_APT1_FIELD_CHOICES
)
DESKTOP_APT1_MAX_CONTROLS = (
    DESKTOP_APT1_UIDL_AGGREGATE_RECORDS
    + DESKTOP_APT1_COLLECTION_CONTROLS
    + DESKTOP_APT1_MAX_FIELDS
)
DESKTOP_APT1_MAX_OBJECTS = (
    DESKTOP_APT1_MAX_CELLS
    + DESKTOP_APT1_MAX_CONTROLS
    + DESKTOP_APT1_CONTENT_ITEMS
    + DESKTOP_APT1_MAX_INSTRUMENTS
    + DESKTOP_APT1_MAX_STATUS_FIELDS
)
DESKTOP_APT1_MAX_OPERATIONS = (
    DESKTOP_APT1_MAX_CELLS
    + DESKTOP_APT1_MAX_CONTROLS
    + DESKTOP_APT1_MAX_INSTRUMENTS
    + DESKTOP_APT1_MAX_REGIONS
    + DESKTOP_APT1_MAX_STATUS_FIELDS
    + DESKTOP_APT1_SERIES_OPERATIONS
)
DESKTOP_APT1_MAX_GLYPH_RUN_BYTES = 4 * DESKTOP_APT1_MAX_COLS
# RETAINED-1 applies max_glyph_run_bytes to each formatted READOUT as well as
# each residual glyph run.  Multiplying that negotiated per-object bound by
# the caller-derived instrument ceiling admits every advertised instrument
# without encoding a separate applet or readout-text cap.
DESKTOP_APT1_INSTRUMENT_FORMATTED_BYTES = (
    DESKTOP_APT1_MAX_GLYPH_RUN_BYTES * DESKTOP_APT1_MAX_INSTRUMENTS
)
DESKTOP_APT1_TOTAL_UTF8_BYTES = (
    4 * DESKTOP_APT1_MAX_CELLS
    + DESKTOP_APT1_UIDL_AGGREGATE_TEXT_BYTES
    + DESKTOP_APT1_COLLECTION_NATIVE_BYTES
    + DESKTOP_APT1_INSTRUMENT_FORMATTED_BYTES
    + DESKTOP_APT1_STATUS_FIELD_NATIVE_BYTES
    + DESKTOP_APT1_FIELD_NATIVE_BYTES
)
DESKTOP_APT1_MAX_ROW_PAYLOAD_BYTES = 12 + 8 * DESKTOP_APT1_MAX_COLS
DESKTOP_APT1_MAX_COLLECTION_PAYLOAD_BYTES = (
    DESKTOP_APT1_CONTROL_PAYLOAD_FIXED_BYTES
    + max(
        DESKTOP_APT1_UIDL_TEXT_BYTES,
        DESKTOP_APT1_COLLECTION_NATIVE_BYTES,
        DESKTOP_APT1_FIELD_NATIVE_BYTES,
    )
)
DESKTOP_APT1_MAX_INSTRUMENT_PAYLOAD_BYTES = (
    DESKTOP_APT1_READOUT_PAYLOAD_FIXED_BYTES
    + DESKTOP_APT1_DATA_GRAPHICS_NATIVE_BYTES
)
DESKTOP_APT1_MAX_STATUS_FIELD_PAYLOAD_BYTES = (
    DESKTOP_APT1_STATUS_FIELD_PAYLOAD_FIXED_BYTES
    + DESKTOP_APT1_STATUS_FIELD_NATIVE_BYTES
)
DESKTOP_APT1_MAX_PAYLOAD_BYTES = max(
    DESKTOP_APT1_MAX_ROW_PAYLOAD_BYTES,
    DESKTOP_APT1_MAX_COLLECTION_PAYLOAD_BYTES,
    DESKTOP_APT1_MAX_INSTRUMENT_PAYLOAD_BYTES,
    DESKTOP_APT1_MAX_STATUS_FIELD_PAYLOAD_BYTES,
)
# A collection CONTROL is atomic.  STX1 needs 72 fixed bytes, 36 bytes per
# item, and raw UTF-8; its native source needs 168 fixed bytes, 72 bytes per
# item, and padded UTF-8.  The caller's native bank is therefore also an honest
# upper bound for the wire content, without inventing a second item cap.
DESKTOP_APT1_MAX_COLLECTION_CONTENT_BYTES = (
    DESKTOP_APT1_COLLECTION_NATIVE_BYTES
)
DESKTOP_APT1_GUEST_TX_BYTES = (
    DESKTOP_APT1_FRAME_HEADER_BYTES + DESKTOP_APT1_MAX_PAYLOAD_BYTES
)
DESKTOP_APT1_CONTROL_VARIABLE_BYTES = (
    DESKTOP_APT1_UIDL_AGGREGATE_TEXT_BYTES
    + DESKTOP_APT1_COLLECTION_NATIVE_BYTES
    + DESKTOP_APT1_FIELD_NATIVE_BYTES
)
# METER has the largest fixed INSTRUMENT frame (152 bytes); adding the entire
# DATA_GRAPHICS bank separately covers every READOUT unit span and every
# POLYLINE's points, eight wire bytes for each sixteen native ones.  This is a
# conservative combined-family wire bound selected from caller-owned bytes,
# not a hidden per-unit or per-applet limit.
DESKTOP_APT1_INSTRUMENT_WIRE_BYTES = (
    DESKTOP_APT1_INSTRUMENT_FRAME_FIXED_BYTES
    * DESKTOP_APT1_MAX_INSTRUMENTS
    + DESKTOP_APT1_DATA_GRAPHICS_NATIVE_BYTES
)
DESKTOP_APT1_REGION_WIRE_BYTES = (
    DESKTOP_APT1_REGION_FRAME_BYTES * DESKTOP_APT1_MAX_REGIONS
)
DESKTOP_APT1_STATUS_FIELD_WIRE_BYTES = (
    DESKTOP_APT1_STATUS_FIELD_FRAME_FIXED_BYTES * DESKTOP_APT1_MAX_STATUS_FIELDS
    + DESKTOP_APT1_STATUS_FIELD_NATIVE_BYTES
)
DESKTOP_APT1_HIDDEN_START_BYTES = (
    160
    + DESKTOP_APT1_REGION_WIRE_BYTES
    + 124 * DESKTOP_APT1_MAX_CELLS
    + DESKTOP_APT1_CONTROL_FRAME_FIXED_BYTES * DESKTOP_APT1_MAX_CONTROLS
    + DESKTOP_APT1_CONTROL_VARIABLE_BYTES
    + DESKTOP_APT1_INSTRUMENT_WIRE_BYTES
    + DESKTOP_APT1_STATUS_FIELD_WIRE_BYTES
    + DESKTOP_APT1_SERIES_WIRE_BYTES
)
DESKTOP_APT1_MAX_COUPLED_TRANSACTION_BYTES = (
    DESKTOP_APT1_HIDDEN_START_BYTES
    + 56
    + DESKTOP_APT1_MAX_ROWS * (40 + DESKTOP_APT1_MAX_ROW_PAYLOAD_BYTES)
)

# The terminal's budget for the optional shell: what this profile's terminal
# grants a Desk with 64 panes, 64 tasks and 12 pins and their text.  Desk's
# own model is not bounded by it: a larger shell asks the terminal for more
# space, which the terminal may refuse.  These quotas are added to every
# existing app-family allowance; they do not enlarge collection, FIELD,
# STATUS_FIELD or DATA_GRAPHICS source banks.
DESKTOP_APT1_SHELL_MODEL_BYTES = 49_152
DESKTOP_APT1_SHELL_MAX_ENTRIES = 140
DESKTOP_APT1_SHELL_TEXT_BYTES = (
    DESKTOP_APT1_SHELL_MODEL_BYTES - 128 - 168 * DESKTOP_APT1_SHELL_MAX_ENTRIES
)
# Each entry may be a pane, with a content region and, while its
# application shows a prompt, a modal region over that content.
DESKTOP_APT1_SHELL_REGIONS = 2 * DESKTOP_APT1_SHELL_MAX_ENTRIES + 3
DESKTOP_APT1_SHELL_CONTROLS = DESKTOP_APT1_SHELL_MAX_ENTRIES + 2
DESKTOP_APT1_SHELL_PANES = DESKTOP_APT1_SHELL_MAX_ENTRIES
DESKTOP_APT1_SHELL_OBJECTS = DESKTOP_APT1_SHELL_CONTROLS + DESKTOP_APT1_SHELL_PANES
DESKTOP_APT1_SHELL_OPERATIONS = DESKTOP_APT1_SHELL_REGIONS + DESKTOP_APT1_SHELL_OBJECTS
DESKTOP_APT1_SHELL_WIRE_BYTES = (
    104 * DESKTOP_APT1_SHELL_REGIONS + 120 * DESKTOP_APT1_SHELL_CONTROLS
    + 144 * DESKTOP_APT1_SHELL_PANES + DESKTOP_APT1_SHELL_TEXT_BYTES
)
DESKTOP_APT1_SHELL_MAX_PAYLOAD_BYTES = 104 + DESKTOP_APT1_SHELL_TEXT_BYTES


# Pictures.  The rich Desktop terminal holds raw RGBA8 pictures up to 4096
# pixels a side, an image size practically every renderer takes, and as many
# bytes as one picture that large; a producer asks its owner for only what
# its pictures need.  Sixteen pictures leave room for several applets that
# show one each.  A chunk is as long as one frame's payload lets it be.
DESKTOP_APT1_MAX_IMAGE_SIDE = 4_096
DESKTOP_APT1_MAX_RESOURCES = 16
DESKTOP_APT1_TOTAL_RESOURCE_BYTES = DESKTOP_APT1_MAX_IMAGE_SIDE ** 2 * 4
DESKTOP_APT1_MAX_RESOURCE_CHUNK_BYTES = DESKTOP_APT1_MAX_PAYLOAD_BYTES - 32


# The rich Desktop terminal without the shell's panes and taskbar.
DESKTOP_APT1_RICH_TERMINAL_BASE = RichTerminalProfile(
    guest_rx_bytes=8_192,
    guest_tx_bytes=DESKTOP_APT1_GUEST_TX_BYTES,
    guest_collection_native_bytes=DESKTOP_APT1_COLLECTION_NATIVE_BYTES,
    guest_data_graphics_native_bytes=(
        DESKTOP_APT1_DATA_GRAPHICS_NATIVE_BYTES
    ),
    guest_status_field_native_bytes=DESKTOP_APT1_STATUS_FIELD_NATIVE_BYTES,
    guest_field_native_bytes=DESKTOP_APT1_FIELD_NATIVE_BYTES,
    host_policy=RichTerminalSessionPolicy(
        max_cols=DESKTOP_APT1_MAX_COLS,
        max_rows=DESKTOP_APT1_MAX_ROWS,
        egress_high_publications=2,
        egress_high_batches=32,
        egress_low_batches=4,
        ingress_bytes=128 * 1024,
        ingress_events=256,
        ingress_control_bytes=4_096,
        ingress_control_events=32,
        geometry_events=8,
        pending_outbound_bytes=128 * 1024,
        pending_outbound_events=256,
        ansi_history_bytes=256 * 1024,
        service_batches=4,
    ),
    retained_policy=RetainedPolicy(
        features=(
            RetainedFeature.CORE
            | RetainedFeature.INSTRUMENT
            | RetainedFeature.CONTROLS
            | RetainedFeature.CONTROL_COLLECTIONS
            | RetainedFeature.CONTROL_ITEMS
            | RetainedFeature.CONTROL_DOCUMENTS
            | RetainedFeature.GRID_CELLS
            | RetainedFeature.STATUS_FIELDS
            | RetainedFeature.FIELDS
            | RetainedFeature.DIALOGS
            | RetainedFeature.SERIES
            | RetainedFeature.VECTOR
            | RetainedFeature.RGBA_IMAGE
        ),
        max_owner_records=1,
        max_live_owners=1,
        max_regions=DESKTOP_APT1_MAX_REGIONS,
        max_resources=DESKTOP_APT1_MAX_RESOURCES,
        max_objects=DESKTOP_APT1_MAX_OBJECTS,
        max_series=DESKTOP_APT1_MAX_SERIES,
        max_operations_per_transaction=DESKTOP_APT1_MAX_OPERATIONS,
        max_resource_chunk_bytes=DESKTOP_APT1_MAX_RESOURCE_CHUNK_BYTES,
        max_retained_transaction_bytes=(
            DESKTOP_APT1_MAX_COUPLED_TRANSACTION_BYTES
        ),
        total_resource_bytes=DESKTOP_APT1_TOTAL_RESOURCE_BYTES,
        # Raw pixels, and QOI, PNG and JPEG files the terminal decodes.
        image_formats=IMAGE_FORMATS,
        max_image_width=DESKTOP_APT1_MAX_IMAGE_SIDE,
        max_image_height=DESKTOP_APT1_MAX_IMAGE_SIDE,
        max_path_points=DESKTOP_APT1_MAX_PATH_POINTS,
        max_glyph_run_bytes=DESKTOP_APT1_MAX_GLYPH_RUN_BYTES,
        max_samples_per_append=DESKTOP_APT1_MAX_SAMPLES_PER_APPEND,
        max_history_per_series=DESKTOP_APT1_MAX_HISTORY_PER_SERIES,
        minimum_presentation_interval_us=0,
        total_sample_slots=DESKTOP_APT1_TOTAL_SAMPLE_SLOTS,
        total_utf8_bytes=DESKTOP_APT1_TOTAL_UTF8_BYTES,
        total_path_points=DESKTOP_APT1_MAX_PATH_POINTS,
        client_to_terminal_max_payload=DESKTOP_APT1_MAX_PAYLOAD_BYTES,
        terminal_to_client_max_payload=64,
        base_max_transaction_bytes=DESKTOP_APT1_MAX_COUPLED_TRANSACTION_BYTES,
    ),
)


def desktop_apt1_shell_profile(
    base: RichTerminalProfile = DESKTOP_APT1_RICH_TERMINAL_BASE,
) -> RichTerminalProfile:
    """Add the shell's terminal quotas to a rich terminal profile.

    Its storage is not sized here: it grows from Desk's memory.  A profile
    already carrying the shell is rejected so repeated configuration cannot
    silently accumulate quotas.
    """
    if not isinstance(base, RichTerminalProfile):
        raise TypeError("base must be a RichTerminalProfile")
    retained = base.retained_policy
    shell_features = RetainedFeature.PANES | RetainedFeature.TASKBARS
    if retained is None:
        raise ValueError("shell selection requires an existing retained policy")
    if base.shell or retained.features & shell_features:
        raise ValueError("shell selection requires a base without the shell")
    payload = max(retained.client_to_terminal_max_payload,
                  DESKTOP_APT1_SHELL_MAX_PAYLOAD_BYTES)
    selected = replace(
        retained,
        features=retained.features | shell_features,
        max_regions=retained.max_regions + DESKTOP_APT1_SHELL_REGIONS,
        max_objects=retained.max_objects + DESKTOP_APT1_SHELL_OBJECTS,
        max_operations_per_transaction=(retained.max_operations_per_transaction
                                        + DESKTOP_APT1_SHELL_OPERATIONS),
        total_utf8_bytes=retained.total_utf8_bytes + DESKTOP_APT1_SHELL_TEXT_BYTES,
        max_retained_transaction_bytes=(retained.max_retained_transaction_bytes
                                        + DESKTOP_APT1_SHELL_WIRE_BYTES),
        base_max_transaction_bytes=(retained.base_max_transaction_bytes
                                    + DESKTOP_APT1_SHELL_WIRE_BYTES),
        client_to_terminal_max_payload=payload,
    )
    return replace(
        base, retained_policy=selected, shell=True,
        guest_tx_bytes=max(base.guest_tx_bytes, DESKTOP_APT1_FRAME_HEADER_BYTES + payload),
    )


# Desk publishes its panes and taskbar as rich objects through the shell
# producer. A changed draw with the acknowledged layout goes out as a retained
# DELTA; layout changes publish a complete hidden replacement. The scratch and
# bank sizes are those the shell was qualified with at 280 by 84 cells.
DESKTOP_APT1_RICH_TERMINAL = desktop_apt1_shell_profile()
