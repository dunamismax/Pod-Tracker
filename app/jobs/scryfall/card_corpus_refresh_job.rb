module Scryfall
  class CardCorpusRefreshJob < ApplicationJob
    queue_as :card_corpus

    discard_on ActiveJob::DeserializationError

    retry_on Scryfall::Client::RateLimitedError,
      wait: ->(executions) { 30 + (executions * 30) },
      attempts: 5

    retry_on Scryfall::Client::Error,
      wait: ->(executions) { 30 + (executions * 60) },
      attempts: 3

    def perform(bulk_type: BulkImporter::DEFAULT_BULK_TYPE, importer: BulkImporter.new)
      importer.import!(bulk_type: bulk_type)
    end
  end
end
