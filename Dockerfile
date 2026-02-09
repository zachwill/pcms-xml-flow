# syntax=docker/dockerfile:1

# ─── Stage 1: build ─────────────────────────────────────────────────
FROM ruby:3.4-slim AS build

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libpq-dev libyaml-dev git && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV=production \
    RAILS_SERVE_STATIC_FILES=true \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development:test"

# Install gems first for better layer caching
COPY web/Gemfile web/Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy app source
COPY web/ .

# Precompile assets at build time
RUN mkdir -p app/assets/builds
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rake tailwindcss:build
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rake assets:precompile
RUN test -f public/assets/.manifest.json

# ─── Stage 2: runtime ───────────────────────────────────────────────
FROM ruby:3.4-slim

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libpq5 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV=production \
    RAILS_SERVE_STATIC_FILES=true \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development:test"

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p db log tmp public && \
    chown -R rails:rails db log tmp public
USER 1000:1000

EXPOSE 3000

# Single-file startup: generate SECRET_KEY_BASE if deploy env didn't set one.
CMD ["sh", "-lc", "if [ -z \"${SECRET_KEY_BASE:-}\" ]; then export SECRET_KEY_BASE=$(ruby -rsecurerandom -e 'print SecureRandom.hex(64)'); fi; exec bundle exec puma -C config/puma.rb"]
