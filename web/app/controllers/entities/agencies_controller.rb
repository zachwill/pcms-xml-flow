module Entities
  class AgenciesController < ApplicationController
    # GET /agencies
    def index
      conn = ActiveRecord::Base.connection

      q = params[:q].to_s.strip
      if q.present?
        q_sql = conn.quote("%#{q}%")
        @agencies = conn.exec_query(<<~SQL).to_a
          SELECT agency_id, agency_name, is_active
          FROM pcms.agencies
          WHERE agency_name ILIKE #{q_sql}
          ORDER BY agency_name
          LIMIT 200
        SQL
      else
        @agencies = conn.exec_query(<<~SQL).to_a
          SELECT agency_id, agency_name, is_active
          FROM pcms.agencies
          ORDER BY agency_name
          LIMIT 100
        SQL
      end

      @query = q

      render :index
    end

    # GET /agencies/:slug
    # Canonical route.
    def show
      slug = params[:slug].to_s.strip.downcase
      raise ActiveRecord::RecordNotFound if slug.blank?

      record = Slug.find_by!(entity_type: "agency", slug: slug)

      canonical = Slug.find_by(entity_type: "agency", entity_id: record.entity_id, canonical: true)
      if canonical && canonical.slug != record.slug
        redirect_to agency_path(canonical.slug), status: :moved_permanently
        return
      end

      @agency_id = record.entity_id
      @agency_slug = record.slug

      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(@agency_id)

      @agency = conn.exec_query(<<~SQL).first
        SELECT agency_id, agency_name, is_active
        FROM pcms.agencies
        WHERE agency_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless @agency

      @agents = conn.exec_query(<<~SQL).to_a
        SELECT agent_id, full_name, is_active
        FROM pcms.agents
        WHERE agency_id = #{id_sql}
        ORDER BY full_name
      SQL

      render :show
    end

    # GET /agencies/:id (numeric fallback)
    def redirect
      id = Integer(params[:id])

      canonical = Slug.find_by(entity_type: "agency", entity_id: id, canonical: true)
      if canonical
        redirect_to agency_path(canonical.slug), status: :moved_permanently
        return
      end

      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(id)

      row = conn.exec_query(<<~SQL).first
        SELECT agency_name
        FROM pcms.agencies
        WHERE agency_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless row

      base = row["agency_name"].to_s.parameterize
      base = "agency-#{id}" if base.blank?

      slug = base
      i = 2
      while Slug.exists?(entity_type: "agency", slug: slug)
        slug = "#{base}-#{i}"
        i += 1
      end

      Slug.create!(entity_type: "agency", entity_id: id, slug: slug, canonical: true)

      redirect_to agency_path(slug), status: :moved_permanently
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end
  end
end
