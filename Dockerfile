FROM ruby:3.4-slim

WORKDIR /app

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git tzdata && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile ./
RUN bundle install --without development test

COPY . .

ENV RACK_ENV=production
ENV PORT=8080
EXPOSE 8080

CMD ["bundle", "exec", "puma", "-C", "puma.rb"]
