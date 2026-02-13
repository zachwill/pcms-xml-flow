# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap
pin "application", preload: true

# Salary Book tool
pin "tools/salary_book", to: "tools/salary_book.js"
pin "tools/team_summary", to: "tools/team_summary.js"

# Entity workspace UX (scrollspy local nav)
pin "entities/workspace", to: "entities/workspace.js"

# Shared commandbar controls (global nav + dark mode)
pin "shared/commandbar_navigation", to: "shared/commandbar_navigation.js"

# Shared combobox keyboard shortcuts / glue
pin "shared/combobox", to: "shared/combobox.js"
