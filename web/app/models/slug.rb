class Slug < ApplicationRecord
  SLUG_REGEX = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  RESERVED_WORDS = %w[pane sidebar sse bootstrap up tools].freeze

  before_validation :normalize

  validates :entity_type, presence: true
  validates :entity_id, presence: true

  validates :slug,
    presence: true,
    format: { with: SLUG_REGEX },
    uniqueness: { scope: :entity_type }

  validate :single_canonical_slug, if: :canonical?
  validate :slug_not_reserved

  scope :canonical, -> { where(canonical: true) }

  def self.reserved_slug?(value)
    RESERVED_WORDS.include?(value.to_s.strip.downcase)
  end

  private

  def normalize
    self.entity_type = entity_type.to_s.strip.downcase
    self.slug = slug.to_s.strip.downcase
  end

  def single_canonical_slug
    rel = Slug.where(entity_type: entity_type, entity_id: entity_id, canonical: true)
    rel = rel.where.not(id: id) if persisted?

    return unless rel.exists?

    errors.add(:canonical, "already exists for this entity")
  end

  def slug_not_reserved
    return unless self.class.reserved_slug?(slug)

    errors.add(:slug, "is reserved")
  end
end
