# syntax=docker/dockerfile:1.7
ARG RUBY_VERSION=3.4.7
ARG BUNDLER_VERSION=2.6.9

############################
# Base
############################
FROM ruby:${RUBY_VERSION}-slim-bookworm AS base

ENV APP_HOME=/app \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3

WORKDIR ${APP_HOME}

RUN apt-get update -y && apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      curl \
      libpq5 \
    && rm -rf /var/lib/apt/lists/*

############################
# deps: build tools + bundler + node (tailwind)
############################
FROM base AS deps

ARG BUNDLER_VERSION=2.6.9

RUN apt-get update -y && apt-get install -y --no-install-recommends \
  build-essential \
  pkg-config \
  libpq-dev \
  libyaml-dev \
  nodejs \
  npm \
    && rm -rf /var/lib/apt/lists/*


RUN gem update --system && gem install bundler -v "${BUNDLER_VERSION}"


COPY infra/Gemfile infra/Gemfile.lock* infra/

COPY infra/Gemfile.test infra/Gemfile.test


COPY infra/ infra/

COPY rails_application/Gemfile rails_application/Gemfile.lock* rails_application/
COPY ecommerce/ ecommerce/


WORKDIR ${APP_HOME}/infra
RUN bundle _${BUNDLER_VERSION}_ install --jobs ${BUNDLE_JOBS} --retry ${BUNDLE_RETRY}


WORKDIR ${APP_HOME}/rails_application
RUN bundle _${BUNDLER_VERSION}_ install --jobs ${BUNDLE_JOBS} --retry ${BUNDLE_RETRY}

WORKDIR ${APP_HOME}

############################
# test stage
############################
FROM deps AS test
ENV RAILS_ENV=test NODE_ENV=test

COPY . ${APP_HOME}

WORKDIR ${APP_HOME}
CMD ["bash", "-lc", "make test"]

############################
# mut stage
############################
FROM deps AS mut
ENV RAILS_ENV=test NODE_ENV=test

COPY . ${APP_HOME}

WORKDIR ${APP_HOME}
CMD ["bash", "-lc", "make mutate"]

############################
# prod-build: assets
############################
FROM deps AS prod-build
ENV RAILS_ENV=production NODE_ENV=production SECRET_KEY_BASE=dummy

COPY . ${APP_HOME}
WORKDIR ${APP_HOME}/rails_application
RUN bundle _${BUNDLER_VERSION}_ exec rails assets:precompile

############################
# prod runtime
############################
FROM base AS prod
ENV RAILS_ENV=production NODE_ENV=production

RUN useradd -m -u 10001 appuser
WORKDIR ${APP_HOME}

COPY --from=deps /bundle /bundle
COPY --from=prod-build /app /app

RUN chown -R appuser:appuser ${APP_HOME} /bundle
USER appuser

WORKDIR ${APP_HOME}/rails_application
EXPOSE 3000

CMD ["bash", "-lc", "bundle exec puma -C config/puma.rb"]