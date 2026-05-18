# frozen_string_literal: true

module RuboCop
  module Cop
    module Tablecop
      # Converts multi-line single-expression methods to single-line form.
      #
      # Uses endless method syntax (`def foo = expr`) for simple cases, but falls
      # back to traditional one-liner (`def foo() expr end`) for methods with
      # modifier-if/unless that call other methods (which can fail in module_eval
      # contexts or at parse time).
      #
      # This cop avoids the bugs in RuboCop's Style/EndlessMethod:
      # - Heredoc destruction
      # - Rescue clause orphaning
      # - module_eval context failures
      # - Modifier-if with dynamic method failures
      #
      # @example Endless method (safe)
      #   # bad
      #   def foo
      #     42
      #   end
      #
      #   # good
      #   def foo = 42
      #
      # @example Traditional one-liner (modifier-if with method call)
      #   # bad
      #   def clear!
      #     data_layer.clear! if data_layer.respond_to?(:clear!)
      #   end
      #
      #   # good
      #   def clear!() data_layer.clear! if data_layer.respond_to?(:clear!) end
      #
      class SafeEndlessMethod < Base
        extend AutoCorrector

        MSG_ENDLESS = "Use endless method: `def %<name>s%<args>s = %<body>s`"
        MSG_TRADITIONAL = "Use single-line method: `def %<name>s%<args>s %<body>s end`"

        def on_def(node)
          return unless convertible?(node)

          if should_use_traditional?(node)
            register_traditional_offense(node)
          else
            register_endless_offense(node)
          end
        end
        alias on_defs on_def

        private

        def convertible?(node)
          # Skip if already single-line
          return false if node.single_line?

          # Must have a body
          return false unless node.body

          # Setter methods (ending with =) can't use endless syntax
          return false if node.method_name.to_s.end_with?("=")

          # Body must be single expression (not begin block with multiple children)
          return false if node.body.begin_type?

          # ...and must not CONTAIN a multi-statement sequence anywhere
          # (e.g. `@memo ||= begin; a; b; end` — body is an or_asgn, so
          # the check above misses it, and it is not a {}/do-end block so
          # contains_multi_statement_block? misses it too). Collapsing its
          # newlines to spaces would jam `a b` with no separator → invalid
          # Ruby. This was a real corruption: rubocop-tablecop#<safe-
          # endless> turned a valid memoized method into an unparseable
          # one in a downstream project.
          return false if contains_multi_statement_sequence?(node.body)

          # No heredocs
          return false if contains_heredoc?(node.body)

          # No rescue/ensure (these are resbody/ensure node types in the method)
          return false if has_rescue_or_ensure?(node)

          # No multi-statement blocks - condensing them breaks syntax
          # (statements need semicolons or newlines, not just spaces)
          return false if contains_multi_statement_block?(node.body)

          # No complex control flow (if/else, case) - can't condense safely
          return false if contains_complex_control_flow?(node.body)

          # Check line length
          return false unless fits_line_length?(node)

          true
        end

        def should_use_traditional?(node)
          # Use traditional one-liner if body has modifier-if/unless with method calls
          # These can fail in module_eval contexts or at parse time
          body = node.body

          return false unless body.respond_to?(:type)

          if body.type == :if && body.modifier_form?
            # Check if the condition or body contains method calls
            has_method_calls?(body)
          else
            false
          end
        end

        def has_method_calls?(node)
          return false unless node

          # Direct method call (send node)
          return true if node.send_type?

          # Check children
          node.each_child_node do |child|
            return true if has_method_calls?(child)
          end

          false
        end

        def contains_heredoc?(node)
          return false unless node

          return true if node.respond_to?(:heredoc?) && node.heredoc?

          node.each_descendant(:str, :dstr, :xstr).any?(&:heredoc?)
        end

        def has_rescue_or_ensure?(node)
          # Check if the method has a rescue or ensure block
          # These show up as the method body being a :rescue or :ensure node
          return true if node.body&.rescue_type?
          return true if node.body&.ensure_type?

          # Also check for rescue as part of method definition (def foo; rescue; end)
          node.each_descendant(:rescue, :ensure, :resbody).any?
        end

        def contains_multi_statement_block?(node)
          return false unless node

          # Check if node itself is a block with multiple statements
          if node.block_type? || node.numblock_type?
            block_body = node.body
            # Multiple statements show up as a :begin node
            return true if block_body&.begin_type?
          end

          # Check descendants for blocks with multiple statements
          node.each_descendant(:block, :numblock) do |block_node|
            block_body = block_node.body
            return true if block_body&.begin_type?
          end

          false
        end

        # True if `body` is, or contains anywhere, a statement sequence
        # with more than one statement. Two AST shapes (verified, not
        # assumed): an implicit multi-statement body is a `:begin`
        # sequence; an explicit `begin … end` is a `:kwbegin` whose
        # children ARE the statements (no inner `:begin`). Either with
        # >1 child is unsafe to space-join. Single-statement `begin x
        # end` is a 1-child :kwbegin and stays convertible.
        def contains_multi_statement_sequence?(body)
          return false unless body

          body.each_node(:begin, :kwbegin).any? { |seq| seq.children.size > 1 }
        end

        def contains_complex_control_flow?(node)
          return false unless node

          # Multi-line if/unless/case can't be condensed safely
          # (modifier-if is handled separately in should_use_traditional?)
          if node.if_type? || node.case_type?
            return true unless node.single_line?
          end

          # Check descendants for complex control flow
          node.each_descendant(:if, :case) do |control_node|
            return true unless control_node.single_line?
          end

          false
        end

        def fits_line_length?(node)
          endless_line = build_endless_line(node)
          traditional_line = build_traditional_line(node)

          # Use the shorter form for checking
          min_length = [endless_line.length, traditional_line.length].min
          indent = node.loc.keyword.column

          (indent + min_length) <= max_line_length
        end

        def build_method_signature(node)
          if node.defs_type?
            # Singleton method: def self.foo or def obj.foo
            receiver = node.receiver.source
            "def #{receiver}.#{node.method_name}"
          else
            "def #{node.method_name}"
          end
        end

        def build_args(node)
          return "" unless node.arguments?

          args_source = node.arguments.source
          # Arguments source may or may not include parens
          if args_source.start_with?("(")
            args_source
          else
            "(#{args_source})"
          end
        end

        def build_endless_line(node)
          sig = build_method_signature(node)
          args = build_args(node)
          body = node.body.source.gsub(/\s*\n\s*/, " ").strip

          "#{sig}#{args} = #{body}"
        end

        def build_traditional_line(node)
          sig = build_method_signature(node)
          args = if node.arguments?
                   args_source = node.arguments.source
                   args_source.start_with?("(") ? args_source : "(#{args_source})"
                 else
                   "()"
                 end
          body = node.body.source.gsub(/\s*\n\s*/, " ").strip

          "#{sig}#{args} #{body} end"
        end

        def register_endless_offense(node)
          sig = build_method_signature(node)
          args = build_args(node)
          body = node.body.source.gsub(/\s*\n\s*/, " ").strip

          message = format(MSG_ENDLESS, name: sig.sub("def ", ""), args: args, body: body)

          add_offense(node, message: message) do |corrector|
            corrector.replace(node, build_endless_line(node))
          end
        end

        def register_traditional_offense(node)
          sig = build_method_signature(node)
          args = node.arguments? ? "(#{node.arguments.source})" : "()"
          body = node.body.source.gsub(/\s*\n\s*/, " ").strip

          message = format(MSG_TRADITIONAL, name: sig.sub("def ", ""), args: args, body: body)

          add_offense(node, message: message) do |corrector|
            corrector.replace(node, build_traditional_line(node))
          end
        end

        def max_line_length
          config.for_cop("Layout/LineLength")["Max"] || 120
        end
      end
    end
  end
end
