"""
Layout constants for TEAM_COCKPIT sheet.

Defines column positions and sizing for the cockpit panels.
"""

from ..command_bar import get_content_start_row

# =============================================================================
# Layout Constants
# =============================================================================


def get_readouts_start_row() -> int:
    """Return the row where readouts content starts (after command bar)."""
    return get_content_start_row()


# Column layout for readouts (left side)
COL_READOUT_LABEL = 0
COL_READOUT_VALUE = 1
COL_READOUT_DESC = 2

# Drivers panel column layout (right side)
COL_DRIVERS_LABEL = 4
COL_DRIVERS_PLAYER = 5
COL_DRIVERS_VALUE = 6

# Number of top rows to show in drivers
TOP_N_DRIVERS = 5

# Column widths
READOUT_COLUMN_WIDTHS = {
    COL_READOUT_LABEL: 18,
    COL_READOUT_VALUE: 14,
    COL_READOUT_DESC: 30,
}

DRIVERS_COLUMN_WIDTHS = {
    COL_DRIVERS_LABEL: 16,
    COL_DRIVERS_PLAYER: 20,
    COL_DRIVERS_VALUE: 14,
}
