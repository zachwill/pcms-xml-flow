# syntax=docker/dockerfile:1

# ─── Stage 1: base ──────────────────────────────────────────────────
FROM ruby:3.4-slim AS base

WORKDIR /rails

# Runtime deps only
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libpq5 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development:test"

# ─── Stage 2: build ─────────────────────────────────────────────────
FROM base AS build

# Build-time deps (compilers, pg headers, git for bundler)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libpq-dev libyaml-dev git && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Everything under web/ is the Rails app
COPY web/ .

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Precompile assets (Tailwind CSS, propshaft manifests).
# SECRET_KEY_BASE_DUMMY lets Rails boot without real credentials.
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

# ─── Stage 3: runtime ───────────────────────────────────────────────
FROM base

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p db log tmp public && \
    chown -R rails:rails db log tmp public
USER 1000:1000

# Puma listens on $PORT (Railway sets this automatically)
EXPOSE 3000

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
