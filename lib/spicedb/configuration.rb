# frozen_string_literal: true

module Spicedb
  class << self
    attr_accessor :token, :url, :tls, :permission_map

    def configure
      yield self
    end
  end
end
