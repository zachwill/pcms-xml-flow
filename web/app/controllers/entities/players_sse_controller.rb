module Entities
  class PlayersSseController < ApplicationController
    # GET /players/:slug/sse/bootstrap
    # Reserved for progressive show-page hydration (phase 3).
    def bootstrap
      head :not_implemented
    end
  end
end
