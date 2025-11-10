# frozen_string_literal: true

workers Integer(ENV.fetch("WEB_CONCURRENCY", 2))
threads_count = Integer(ENV.fetch("RAILS_MAX_THREADS", 5))
threads threads_count, threads_count

preload_app!

rackup DefaultRackup
port ENV.fetch("PORT", 9292)
env = ENV.fetch("RACK_ENV", "development")
environment env

on_worker_boot do
  # Worker specific setup for the pool
end
