# frozen_string_literal: true

module RuboCop
  module Cop
    module Tablecop
      # Checks for multi-line `in` clauses (pattern matching) that could be
      # condensed to a single line using the `then` keyword, with alignment.
      #
      # This cop encourages a table-like, vertically-aligned style for pattern
      # matching case statements where each in clause fits on one line.
      #
      # When guard clauses are present, three-column alignment is used:
      # patterns align, then `if` keywords align, then `then` keywords align.
      #
      # @example
      #   # bad
      #   case response
      #   in [:ok, body]
      #     handle_success(body)
      #   in [:error, code]
      #     handle_error(code)
      #   end
      #
      #   # good (aligned)
      #   case response
      #   in [:ok, body]    then handle_success(body)
      #   in [:error, code] then handle_error(code)
      #   end
      #
      #   # good (with guards - three-column alignment)
      #   case response
      #   in [:ok, body]              then handle_success(body)
      #   in [:error, code] if retry? then handle_retry(code)
      #   in [:error, code]           then handle_error(code)
      #   end
      #
      #   # also good (body too complex for single line)
      #   case response
      #   in [:ok, body]
      #     log_success
      #     handle_success(body)
      #   end
      #
      class CondenseIn < Base
        extend AutoCorrector

        MSG = "Condense `in` to single line with aligned `then`"

        def on_case_match(node)
          in_nodes = node.in_pattern_branches
          return if in_nodes.empty?

          # Analyze which in-patterns can be condensed
          condensable = in_nodes.map { |n| [n, condensable?(n)] }

          # If none can be condensed, nothing to do
          return unless condensable.any? { |_, can| can }

          # Calculate alignment widths from all condensable in-patterns
          max_pattern_width = calculate_max_pattern_width(condensable)
          max_guard_width = calculate_max_guard_width(condensable)

          # Check if alignment would exceed line length for any condensable in-pattern
          use_alignment = can_align_all?(condensable, max_pattern_width, max_guard_width, node)

          # Register offenses and corrections for each condensable in-pattern
          condensable.each do |in_node, can_condense|
            next unless can_condense
            next if in_node.single_line?  # Already condensed

            register_offense(in_node, max_pattern_width, max_guard_width, use_alignment, node)
          end
        end

        private

        def condensable?(node)
          # Must have a body
          return false unless node.body

          # Body must be a simple single expression (not begin block with multiple statements)
          return false if node.body.begin_type? && node.body.children.size > 1

          # No heredocs
          return false if contains_heredoc?(node.body)

          # No multi-line strings
          return false if contains_multiline_string?(node.body)

          # No control flow that can't be safely condensed
          return false if contains_complex_control_flow?(node.body)

          # No comments between in and body
          return false if comment_between?(node)

          # Pattern must be on one line
          return false unless pattern_single_line?(node)

          # Guard (if present) must be on one line
          return false unless guard_single_line?(node)

          # Check if condensed form would exceed line length (without alignment)
          single_line = build_single_line(node, 0, 0)
          base_indent = node.loc.keyword.column
          return false if (base_indent + single_line.length) > max_line_length

          true
        end

        def calculate_max_pattern_width(condensable)
          condensable
            .select { |_, can| can }
            .map { |n, _| pattern_width(n) }
            .max || 0
        end

        def calculate_max_guard_width(condensable)
          condensable
            .select { |_, can| can }
            .map { |n, _| guard_width(n) }
            .max || 0
        end

        def pattern_width(in_node)
          in_node.pattern.source.length
        end

        def guard_width(in_node)
          guard = in_node.children[1]
          return 0 unless guard

          guard.source.length
        end

        def can_align_all?(condensable, max_pattern_width, max_guard_width, case_node)
          base_indent = case_node.loc.keyword.column

          condensable.all? do |in_node, can_condense|
            next true unless can_condense
            next true if in_node.single_line?

            # Check if aligned version fits
            single_line = build_single_line(in_node, max_pattern_width, max_guard_width)
            (base_indent + single_line.length) <= max_line_length
          end
        end

        def build_single_line(in_node, pad_pattern_to, pad_guard_to)
          pattern_source = in_node.pattern.source
          body_source = in_node.body.source.gsub(/\s*\n\s*/, " ").strip
          guard = in_node.children[1]

          if pad_pattern_to > 0
            pattern_padding = " " * (pad_pattern_to - pattern_source.length)

            if guard
              guard_source = guard.source
              guard_padding = " " * (pad_guard_to - guard_source.length)
              "in #{pattern_source}#{pattern_padding} #{guard_source}#{guard_padding} then #{body_source}"
            elsif pad_guard_to > 0
              # No guard on this branch, but other branches have guards
              # Pad to align with where 'then' would be after guards
              total_padding = " " * (pad_pattern_to - pattern_source.length + pad_guard_to + 1)
              "in #{pattern_source}#{total_padding} then #{body_source}"
            else
              "in #{pattern_source}#{pattern_padding} then #{body_source}"
            end
          else
            if guard
              "in #{pattern_source} #{guard.source} then #{body_source}"
            else
              "in #{pattern_source} then #{body_source}"
            end
          end
        end

        def register_offense(in_node, max_pattern_width, max_guard_width, use_alignment, _case_node)
          add_offense(in_node) do |corrector|
            pattern_width = use_alignment ? max_pattern_width : 0
            guard_width = use_alignment ? max_guard_width : 0
            single_line = build_single_line(in_node, pattern_width, guard_width)
            corrector.replace(in_node, single_line)
          end
        end

        def pattern_single_line?(node)
          pattern = node.pattern
          pattern.first_line == pattern.last_line
        end

        def guard_single_line?(node)
          guard = node.children[1]
          return true unless guard

          guard.first_line == guard.last_line
        end

        def contains_heredoc?(node)
          return false unless node

          return true if node.respond_to?(:heredoc?) && node.heredoc?

          node.each_descendant(:str, :dstr, :xstr).any?(&:heredoc?)
        end

        def contains_multiline_string?(node)
          return false unless node

          node.each_descendant(:str, :dstr).any? do |str_node|
            next false if str_node.heredoc?

            str_node.source.include?("\n")
          end
        end

        def contains_complex_control_flow?(node)
          return false unless node

          # Multi-line if/unless/case can't be condensed safely
          if node.if_type? || node.case_type? || node.case_match_type?
            return true unless node.single_line?
          end

          # Check for multi-statement blocks
          node.each_descendant(:block, :numblock) do |block_node|
            return true if block_node.body&.begin_type?
          end

          # Check descendants for complex control flow
          node.each_descendant(:if, :case, :case_match) do |control_node|
            return true unless control_node.single_line?
          end

          false
        end

        def comment_between?(in_node)
          return false unless in_node.body

          comments = processed_source.comments
          in_line = in_node.loc.keyword.line
          body_line = in_node.body.first_line

          comments.any? do |comment|
            comment.loc.line.between?(in_line, body_line - 1)
          end
        end

        def max_line_length
          config.for_cop("Layout/LineLength")["Max"] || 120
        end
      end
    end
  end
end
