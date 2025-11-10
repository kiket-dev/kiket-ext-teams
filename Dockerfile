FROM ruby:3.3-alpine

WORKDIR /app

RUN apk add --no-cache build-base git tzdata

COPY Gemfile ./
RUN bundle install --without development test

COPY . .

ENV RACK_ENV=production
ENV PORT=8080
EXPOSE 8080

CMD ["bundle", "exec", "puma", "-C", "puma.rb"]
