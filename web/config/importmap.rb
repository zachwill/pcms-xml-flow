# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap
pin "application", preload: true

# Tool UI glue
pin "tools/salary_book", to: "tools/salary_book.js"
pin "tools/team_summary", to: "tools/team_summary.js"
pin "tools/two_way_utility", to: "tools/two_way_utility.js"
pin "tools/system_values", to: "tools/system_values.js"

# Entity workspace UX (scrollspy local nav)
pin "entities/workspace", to: "entities/workspace.js"

# Shared commandbar controls (global nav + dark mode)
pin "shared/commandbar_navigation", to: "shared/commandbar_navigation.js"

# Shared combobox keyboard shortcuts / glue
pin "shared/combobox", to: "shared/combobox.js"
