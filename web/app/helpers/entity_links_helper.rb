# frozen_string_literal: true

# EntityLinksHelper
#
# Goal: keep entity navigation canonical + shareable.
#
# - If a canonical slug exists (web.slugs), link directly to the slug route.
# - Otherwise, link to the numeric fallback route which 301s → slug and creates
#   a canonical slug on-demand.
#
# This is intentionally "dumb" about domain logic — it only knows how to:
# - map entity_type → route helper
# - look up canonical slugs
# - fall back safely
#
# Performance:
# - For list pages, call `prefetch_canonical_slugs(...)` once to avoid N+1.
module EntityLinksHelper
  CANONICAL_PATH_HELPER = {
    "player" => :player_path,
    "team" => :team_path,
    "agent" => :agent_path,
    "agency" => :agency_path,
    "draft_selection" => :draft_selection_path
  }.freeze

  NUMERIC_FALLBACK_PREFIX = {
    "player" => "/players",
    "team" => "/teams",
    "agent" => "/agents",
    "agency" => "/agencies",
    "draft_selection" => "/draft-selections"
  }.freeze

  # Generic entrypoint.
  #
  # Examples:
  #   entity_href(entity_type: "agent", entity_id: 123) #=> /agents/rich-paul (if known)
  #   entity_href(entity_type: "agent", entity_id: 123) #=> /agents/123 (if slug unknown)
  def entity_href(entity_type:, entity_id:)
    type = normalize_entity_type(entity_type)
    id = normalize_entity_id(entity_id)

    return "#" if type.blank? || id.nil?

    if (slug = canonical_slug_for(type, id)).present?
      return send(CANONICAL_PATH_HELPER.fetch(type), slug)
    end

    "#{NUMERIC_FALLBACK_PREFIX.fetch(type)}/#{id}"
  rescue KeyError
    "#"
  end

  # Bulk load canonical slugs into the request-local cache.
  #
  # Call this once at the top of list views to avoid N+1.
  def prefetch_canonical_slugs(entity_type:, entity_ids:)
    type = normalize_entity_type(entity_type)
    return if type.blank?

    ids = Array(entity_ids).filter_map { |v| normalize_entity_id(v) }.uniq
    return if ids.empty?

    cache = canonical_slug_cache

    missing = ids.reject { |id| cache.key?([type, id]) }
    return if missing.empty?

    Slug.where(entity_type: type, entity_id: missing, canonical: true)
      .pluck(:entity_id, :slug)
      .each do |entity_id, slug|
        cache[[type, entity_id.to_i]] = slug
      end

    # Memoize misses as nil so repeated calls don't keep hitting the DB.
    missing.each do |id|
      cache[[type, id]] ||= nil
    end
  end

  # Convenience helpers (keep views readable)
  def player_href(player_id)
    entity_href(entity_type: "player", entity_id: player_id)
  end

  # Teams: prefer team_code when we have it because it is stable and guessable.
  # This also allows `TeamsController#show` to bootstrap the slug registry.
  def team_href(team_code: nil, team_id: nil)
    code = team_code.to_s.strip
    if code.match?(/\A[A-Za-z]{3}\z/)
      return team_path(code.downcase)
    end

    entity_href(entity_type: "team", entity_id: team_id)
  end

  def agent_href(agent_id)
    entity_href(entity_type: "agent", entity_id: agent_id)
  end

  def agency_href(agency_id)
    entity_href(entity_type: "agency", entity_id: agency_id)
  end

  def draft_selection_href(transaction_id)
    entity_href(entity_type: "draft_selection", entity_id: transaction_id)
  end

  private

  def canonical_slug_for(entity_type, entity_id)
    cache = canonical_slug_cache
    key = [entity_type, entity_id]

    return cache[key] if cache.key?(key)

    cache[key] = Slug.where(entity_type: entity_type, entity_id: entity_id, canonical: true).pick(:slug)
  end

  def canonical_slug_cache
    @__entity_links_canonical_slug_cache ||= {}
  end

  def normalize_entity_type(value)
    value.to_s.strip.downcase.presence
  end

  def normalize_entity_id(value)
    return nil if value.nil?

    if value.is_a?(Integer)
      return value if value.positive?
      return nil
    end

    s = value.to_s.strip
    return nil if s.blank?

    id = Integer(s, 10)
    id.positive? ? id : nil
  rescue ArgumentError, TypeError
    nil
  end
end
