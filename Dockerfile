# syntax=docker/dockerfile:1
# check=error=true

FROM docker.io/library/node:26.8.2-slim@sha256:f7bb8247fdb16250dbec7fd0e24f091c6f5f0a29d256f3aef5816a7a369166b2 AS frontend

WORKDIR /frontend
COPY frontend/package.json frontend/package-lock.json frontend/.npmrc ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

FROM docker.io/library/ruby:4.0.7-slim@sha256:f86fd77fc63d216167479fec2bc5f90d5f2b9a555721316774fdbe5c18670d3a AS base

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 postgresql-client && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    THRUSTER_HTTP_PORT="10000" \
    THRUSTER_CACHE_SIZE="8388608"

FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY .ruby-version Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .
COPY --from=frontend /public/spa /rails/public/spa
COPY --from=frontend /frontend/dist /rails/frontend/dist
RUN bundle exec bootsnap precompile -j 1 app/ lib/

FROM base

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails
RUN mkdir -p /rails/tmp /rails/log && chown -R rails:rails /rails/tmp /rails/log

USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 10000
CMD ["./bin/thrust", "./bin/rails", "server"]
