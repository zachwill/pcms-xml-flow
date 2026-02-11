module ApplicationHelper
  NEUTRAL_BADGE_CLASSES = "bg-zinc-100/80 dark:bg-zinc-800/60 text-zinc-700 dark:text-zinc-300".freeze

  # Shared neutral badge styling for subtle status pills/chips.
  def neutral_badge_classes
    NEUTRAL_BADGE_CLASSES
  end
end
