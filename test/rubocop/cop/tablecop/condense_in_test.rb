# frozen_string_literal: true

require_relative "../../../test_helper"

class CondenseInTest < Minitest::Test
  include CopHelper

  def cop_class
    RuboCop::Cop::Tablecop::CondenseIn
  end

  # ===========================================================================
  # Basic Condensing
  # ===========================================================================

  def test_condenses_simple_in_clauses
    source = <<~RUBY
      case response
      in [:ok, body]
        handle_success(body)
      in [:error, code]
        handle_error(code)
      end
    RUBY

    expected = <<~RUBY
      case response
      in [:ok, body]    then handle_success(body)
      in [:error, code] then handle_error(code)
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_condenses_hash_patterns
    source = <<~RUBY
      case data
      in { status: 200, body: }
        body
      in { status: 404 }
        nil
      end
    RUBY

    expected = <<~RUBY
      case data
      in { status: 200, body: } then body
      in { status: 404 }        then nil
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_condenses_variable_patterns
    source = <<~RUBY
      case value
      in Integer => n
        n * 2
      in String => s
        s.upcase
      end
    RUBY

    expected = <<~RUBY
      case value
      in Integer => n then n * 2
      in String => s  then s.upcase
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_leaves_complex_bodies_alone
    source = <<~RUBY
      case response
      in [:ok, body]
        log_success
        handle_success(body)
      end
    RUBY

    assert_no_offenses(source)
  end

  def test_leaves_heredocs_alone
    source = <<~RUBY
      case response
      in [:ok, _]
        <<~MSG
          Success!
        MSG
      end
    RUBY

    assert_no_offenses(source)
  end

  def test_leaves_already_condensed_alone
    source = <<~RUBY
      case response
      in [:ok, body]    then handle_success(body)
      in [:error, code] then handle_error(code)
      end
    RUBY

    assert_no_offenses(source)
  end

  # ===========================================================================
  # Alignment
  # ===========================================================================

  def test_aligns_then_keywords_across_siblings
    source = <<~RUBY
      case response
      in [:ok, body]
        :success
      in [:error, code, message]
        :failure
      in [:timeout]
        :retry
      end
    RUBY

    expected = <<~RUBY
      case response
      in [:ok, body]             then :success
      in [:error, code, message] then :failure
      in [:timeout]              then :retry
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_aligns_with_mixed_condensable_and_not
    source = <<~RUBY
      case response
      in [:ok, body]
        :success
      in [:error, code]
        log_error(code)
        handle_error(code)
      in [:timeout]
        :retry
      end
    RUBY

    expected = <<~RUBY
      case response
      in [:ok, body] then :success
      in [:error, code]
        log_error(code)
        handle_error(code)
      in [:timeout]  then :retry
      end
    RUBY

    assert_correction(source, expected)
  end

  # ===========================================================================
  # Guard Clauses - Three-Column Alignment
  # ===========================================================================

  def test_condenses_with_simple_guard
    source = <<~RUBY
      case value
      in Integer if value > 0
        :positive
      in Integer
        :non_positive
      end
    RUBY

    expected = <<~RUBY
      case value
      in Integer if value > 0 then :positive
      in Integer              then :non_positive
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_three_column_alignment_with_guards
    source = <<~RUBY
      case response
      in [:ok, body]
        handle_success(body)
      in [:error, code] if code < 500
        handle_client_error(code)
      in [:error, code]
        handle_server_error(code)
      end
    RUBY

    # All `then` keywords align: pattern pads to longest pattern,
    # then guard column pads to longest guard, then `then` aligns
    expected = <<~RUBY
      case response
      in [:ok, body]                  then handle_success(body)
      in [:error, code] if code < 500 then handle_client_error(code)
      in [:error, code]               then handle_server_error(code)
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_aligns_multiple_guards
    source = <<~RUBY
      case response
      in [:ok, body]
        :success
      in [:error, code] if code.recoverable?
        :retry
      in [:error, code] if code.critical?
        :alert
      in [:error, code]
        :log
      end
    RUBY

    # All `then` align: pattern column + guard column + then
    expected = <<~RUBY
      case response
      in [:ok, body]                         then :success
      in [:error, code] if code.recoverable? then :retry
      in [:error, code] if code.critical?    then :alert
      in [:error, code]                      then :log
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_unless_guard
    source = <<~RUBY
      case value
      in Integer unless value.zero?
        value * 2
      in Integer
        0
      end
    RUBY

    expected = <<~RUBY
      case value
      in Integer unless value.zero? then value * 2
      in Integer                    then 0
      end
    RUBY

    assert_correction(source, expected)
  end

  # ===========================================================================
  # Line Length Handling
  # ===========================================================================

  def test_no_alignment_if_would_exceed_line_length
    source = <<~RUBY
      case foo
      in [:ok, body]
        "this is a pretty long result string here"
      in [:a_very_long_pattern_name_for_testing, x, y, z]
        "x"
      end
    RUBY

    # Aligned version would push first line over 80 chars. Fall back to no alignment.
    expected = <<~RUBY
      case foo
      in [:ok, body] then "this is a pretty long result string here"
      in [:a_very_long_pattern_name_for_testing, x, y, z] then "x"
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_skips_clause_entirely_if_condensed_exceeds_line_length
    source = <<~RUBY
      case foo
      in [:ok, body]
        :success
      in [:x]
        "this is a very long result string that would exceed the line length limit"
      end
    RUBY

    expected = <<~RUBY
      case foo
      in [:ok, body] then :success
      in [:x]
        "this is a very long result string that would exceed the line length limit"
      end
    RUBY

    assert_correction(source, expected)
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  def test_handles_else_clause
    source = <<~RUBY
      case response
      in [:ok, body]
        :success
      in [:error, code]
        :failure
      else
        :unknown
      end
    RUBY

    expected = <<~RUBY
      case response
      in [:ok, body]    then :success
      in [:error, code] then :failure
      else
        :unknown
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_handles_single_in
    source = <<~RUBY
      case response
      in [:ok, body]
        body
      end
    RUBY

    expected = <<~RUBY
      case response
      in [:ok, body] then body
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_preserves_comments_in_multiline_ins
    source = <<~RUBY
      case response
      in [:ok, body]
        # This is important
        :success
      in [:error, code]
        :failure
      end
    RUBY

    expected = <<~RUBY
      case response
      in [:ok, body]
        # This is important
        :success
      in [:error, code] then :failure
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_skips_in_with_if_else_body
    source = <<~RUBY
      case response
      in [:ok, body]
        if body.empty?
          :empty
        else
          :success
        end
      in [:error, code]
        :failure
      end
    RUBY

    expected = <<~RUBY
      case response
      in [:ok, body]
        if body.empty?
          :empty
        else
          :success
        end
      in [:error, code] then :failure
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_allows_single_line_ternary_in_body
    source = <<~RUBY
      case response
      in [:ok, body]
        body.empty? ? :empty : :success
      in [:error, code]
        :failure
      end
    RUBY

    expected = <<~RUBY
      case response
      in [:ok, body]    then body.empty? ? :empty : :success
      in [:error, code] then :failure
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_handles_splat_patterns
    source = <<~RUBY
      case args
      in [first, *rest]
        process(first, rest)
      in []
        nil
      end
    RUBY

    expected = <<~RUBY
      case args
      in [first, *rest] then process(first, rest)
      in []             then nil
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_handles_as_pattern
    # Pin operator (^var) requires var to be defined, so test with "as" pattern instead
    source = <<~RUBY
      case value
      in Integer => num
        num * 2
      in String => str
        str.upcase
      in other
        other.to_s
      end
    RUBY

    expected = <<~RUBY
      case value
      in Integer => num then num * 2
      in String => str  then str.upcase
      in other          then other.to_s
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_handles_alternative_patterns
    source = <<~RUBY
      case value
      in :foo | :bar
        :foobar
      in :baz
        :baz
      end
    RUBY

    expected = <<~RUBY
      case value
      in :foo | :bar then :foobar
      in :baz        then :baz
      end
    RUBY

    assert_correction(source, expected)
  end

  def test_real_world_http_response_handling
    source = <<~RUBY
      case @http.post("/v1/charges", json: { amount:, currency:, source: })
      in [:ok, 200, body]
        [:ok, body]
      in [:ok, 402, body]
        [:card_declined, body["error"]]
      in [:ok, status, body]
        [:error, status, body]
      in [error, *rest]
        [error, *rest]
      end
    RUBY

    expected = <<~RUBY
      case @http.post("/v1/charges", json: { amount:, currency:, source: })
      in [:ok, 200, body]    then [:ok, body]
      in [:ok, 402, body]    then [:card_declined, body["error"]]
      in [:ok, status, body] then [:error, status, body]
      in [error, *rest]      then [error, *rest]
      end
    RUBY

    assert_correction(source, expected)
  end
end
