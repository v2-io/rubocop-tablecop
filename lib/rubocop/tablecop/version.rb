# frozen_string_literal: true

module RuboCop
  module Tablecop
    # Version information for rubocop-tablecop.
    module Version
      STRING = "0.3.0"

      def self.document_version
        STRING.match('\d+\.\d+').to_s
      end
    end

    # For backwards compatibility with code expecting RuboCop::Tablecop::VERSION
    VERSION = Version::STRING
  end
end
