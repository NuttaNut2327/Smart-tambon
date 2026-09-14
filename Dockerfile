FROM ruby:3.3.6-slim

RUN apt-get update -qq && apt-get install --no-install-recommends -y \
    build-essential libpq-dev libgeos-dev postgresql-client curl && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /rails
COPY Gemfile Gemfile.lock* ./
RUN bundle install
COPY . .
EXPOSE 3000
ENTRYPOINT ["sh", "bin/docker-entrypoint"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
