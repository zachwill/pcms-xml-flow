module SalaryBookHelper
  include SalaryBook::FormattingHelper
  include SalaryBook::ContractsHelper
  include SalaryBook::PercentileHelper
  include SalaryBook::AssetsHelper

  # Canonical year horizon for the salary book (keep in sync with controller).
  # If you change this, also update the SQL warehouse pivots in the controller.
  SALARY_YEARS = (2025..2030).to_a.freeze

  # Commandbar "Display → Cap Holds" default.
  # NOTE: This is the player-row cap-hold lens, not the FA Cap Holds section toggle.
  def salary_book_default_display_player_cap_holds?
    true
  end
end
