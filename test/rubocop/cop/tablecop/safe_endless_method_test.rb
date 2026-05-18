# frozen_string_literal: true

require_relative "../../../test_helper"

class SafeEndlessMethodTest < Minitest::Test
  include CopHelper

  def cop_class
    RuboCop::Cop::Tablecop::SafeEndlessMethod
  end

  # ===========================================================================
  # Basic Conversion to Endless
  # ===========================================================================

  def test_converts_simple_method_to_endless
    source = <<~RUBY
      def foo
        42
      end
    RUBY

    expected = <<~RUBY
      def foo = 42
    RUBY

    assert_correction(source, expected)
  end

  def test_converts_method_with_args_to_endless
    source = <<~RUBY
      def add(a, b)
        a + b
      end
    RUBY

    expected = <<~RUBY
      def add(a, b) = a + b
    RUBY

    assert_correction(source, expected)
  end

  def test_converts_method_returning_method_call
    source = <<~RUBY
      def name
        @name.to_s
      end
    RUBY

    expected = <<~RUBY
      def name = @name.to_s
    RUBY

    assert_correction(source, expected)
  end

  # ===========================================================================
  # Traditional One-liner for Modifier-if/unless with Method Calls
  # ===========================================================================

  def test_uses_traditional_for_modifier_if_with_method_call
    source = <<~RUBY
      def clear!
        data_layer.clear! if data_layer.respond_to?(:clear!)
      end
    RUBY

    # Uses traditional one-liner because modifier-if calls methods
    expected = <<~RUBY
      def clear!() data_layer.clear! if data_layer.respond_to?(:clear!) end
    RUBY

    assert_correction(source, expected)
  end

  def test_uses_traditional_for_modifier_unless_with_method_call
    source = <<~RUBY
      def skip
        perform unless disabled?
      end
    RUBY

    expected = <<~RUBY
      def skip() perform unless disabled? end
    RUBY

    assert_correction(source, expected)
  end

  def test_endless_ok_for_modifier_if_with_literals
    source = <<~RUBY
      def maybe
        42 if true
      end
    RUBY

    # Modifier-if with literal condition is safe for endless
    expected = <<~RUBY
      def maybe = 42 if true
    RUBY

    assert_correction(source, expected)
  end

  # ===========================================================================
  # Skip Already Single-line Methods
  # ===========================================================================

  def test_skips_already_endless
    source = <<~RUBY
      def foo = 42
    RUBY

    assert_no_offenses(source)
  end

  def test_skips_already_traditional_oneliner
    source = <<~RUBY
      def foo() 42 end
    RUBY

    assert_no_offenses(source)
  end

  def test_skips_already_traditional_oneliner_with_semicolon
    source = <<~RUBY
      def foo; 42; end
    RUBY

    assert_no_offenses(source)
  end

  # ===========================================================================
  # Skip Methods with Heredocs
  # ===========================================================================

  def test_skips_method_with_heredoc
    source = <<~RUBY
      def template
        <<~HTML
          <h1>Hello</h1>
        HTML
      end
    RUBY

    assert_no_offenses(source)
  end

  # ===========================================================================
  # Skip Methods with Rescue/Ensure
  # ===========================================================================

  def test_skips_method_with_rescue
    source = <<~RUBY
      def safe_call
        risky_operation
      rescue StandardError
        nil
      end
    RUBY

    assert_no_offenses(source)
  end

  def test_skips_method_with_ensure
    source = <<~RUBY
      def with_cleanup
        do_work
      ensure
        cleanup
      end
    RUBY

    assert_no_offenses(source)
  end

  # ===========================================================================
  # Skip Methods with Multiple Statements
  # ===========================================================================

  def test_skips_multi_statement_body
    source = <<~RUBY
      def complex
        setup
        perform
      end
    RUBY

    assert_no_offenses(source)
  end

  # Regression: a multi-statement `begin … end` nested as a
  # sub-expression (here the RHS of `||=`, the classic memoization
  # idiom). The method body is an `or_asgn`, not a :begin, so the
  # direct-body guard missed it; it is not a {}/do-end block either.
  # Endless-converting it collapsed `a\n b` to `a b` → invalid Ruby
  # that broke a downstream project at parse time. Must be skipped.
  def test_skips_multi_statement_begin_in_memoization
    source = <<~RUBY
      def records
        @records ||= begin
          csvs = glob.sort
          Parser.parse_files(csvs)
        end
      end
    RUBY

    assert_no_offenses(source)
  end

  # Single-statement explicit `begin … end` stays convertible — it
  # remains valid Ruby when newlines collapse to spaces.
  def test_converts_single_statement_begin
    source = <<~RUBY
      def value
        begin
          compute
        end
      end
    RUBY

    expected = <<~RUBY
      def value = begin compute end
    RUBY

    assert_correction(source, expected)
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  def test_handles_method_with_block
    source = <<~RUBY
      def items
        @items.map { |x| x * 2 }
      end
    RUBY

    expected = <<~RUBY
      def items = @items.map { |x| x * 2 }
    RUBY

    assert_correction(source, expected)
  end

  def test_handles_method_with_ternary
    source = <<~RUBY
      def status
        valid? ? :ok : :error
      end
    RUBY

    expected = <<~RUBY
      def status = valid? ? :ok : :error
    RUBY

    assert_correction(source, expected)
  end

  def test_respects_line_length
    source = <<~RUBY
      def very_long_method_name_that_takes_up_space
        "this is also a long string that combined would exceed the limit"
      end
    RUBY

    # If endless form would exceed line length, skip
    assert_no_offenses(source)
  end

  def test_handles_singleton_method
    source = <<~RUBY
      def self.version
        VERSION
      end
    RUBY

    expected = <<~RUBY
      def self.version = VERSION
    RUBY

    assert_correction(source, expected)
  end

  # ===========================================================================
  # Skip Methods with Multi-statement Blocks
  # ===========================================================================

  def test_skips_method_with_multi_statement_do_block
    source = <<~RUBY
      def read(query)
        Result.try do
          ds = apply_query(dataset, query)
          ds.map { |row| build_record(row) }
        end
      end
    RUBY

    # Multi-statement blocks can't be condensed to single line without semicolons
    assert_no_offenses(source)
  end

  def test_skips_method_with_multi_statement_brace_block
    source = <<~RUBY
      def process
        items.each { |i|
          validate(i)
          transform(i)
        }
      end
    RUBY

    assert_no_offenses(source)
  end

  def test_allows_single_statement_block
    source = <<~RUBY
      def items
        @items.map { |x| x * 2 }
      end
    RUBY

    expected = <<~RUBY
      def items = @items.map { |x| x * 2 }
    RUBY

    assert_correction(source, expected)
  end

  # ===========================================================================
  # Skip Setter Methods
  # ===========================================================================

  def test_skips_setter_methods
    source = <<~RUBY
      def []=(key, value)
        @attributes[key] = value
      end
    RUBY

    # Setter methods can't use endless syntax
    assert_no_offenses(source)
  end

  def test_skips_named_setter_methods
    source = <<~RUBY
      def name=(value)
        @name = value
      end
    RUBY

    assert_no_offenses(source)
  end

  # ===========================================================================
  # Skip Complex Control Flow
  # ===========================================================================

  def test_skips_method_with_if_else
    source = <<~RUBY
      def schema_id(id = nil)
        if id
          @schema_id = id.to_s
        else
          @schema_id ||= default_schema_id
        end
      end
    RUBY

    # if/else can't be condensed without semicolons
    assert_no_offenses(source)
  end

  def test_allows_single_line_ternary
    source = <<~RUBY
      def status
        valid? ? :ok : :error
      end
    RUBY

    expected = <<~RUBY
      def status = valid? ? :ok : :error
    RUBY

    assert_correction(source, expected)
  end
end
