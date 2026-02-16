# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap
pin "application", preload: true

# Tool UI glue
pin "salary_book", to: "salary_book.js"
pin "team_summary", to: "team_summary.js"
pin "two_way_utility", to: "two_way_utility.js"
pin "system_values", to: "system_values.js"

# Entity workspace UX (scrollspy local nav)
pin "workspace", to: "workspace.js"

# Shared commandbar controls (global nav + dark mode)
pin "shared/commandbar_navigation", to: "shared/commandbar_navigation.js"

# Shared combobox keyboard shortcuts / glue
pin "shared/combobox", to: "shared/combobox.js"
