# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2026-05-18

### Fixed

- **`Tablecop/SafeEndlessMethod` no longer corrupts methods whose body
  contains a multi-statement `begin … end` nested as a sub-expression**
  (e.g. the memoization idiom `@memo ||= begin; a; b; end`). The body
  is an `or_asgn`, so the existing direct-body `:begin` guard missed
  it, and it is not a `{}`/`do-end` block so the block guard missed it
  too; autocorrect collapsed `a\n b` into `a b` (no separator) →
  syntactically invalid Ruby. Found when it broke a downstream project
  at parse time. Single-statement `begin x end` still converts.

> Note: 0.3.0 was released without a changelog entry; entries resume
> here rather than reconstruct unrecorded history.

## [0.2.0] - 2025-12-13

### Changed

- **BREAKING**: Renamed gem from `tablecop` to `rubocop-tablecop` for RuboCop plugin auto-discovery
- **BREAKING**: Minimum RuboCop version increased from 1.50 to 1.72 (required for plugin system)
- Migrated to RuboCop's plugin system using `lint_roller`
- Version module relocated to `RuboCop::Tablecop::Version::STRING` (backwards-compatible `VERSION` constant retained)

### Added

- `RuboCop::Tablecop::Plugin` class for native plugin integration
- Can now use `plugins: [rubocop-tablecop]` in `.rubocop.yml` instead of `require:`

### Fixed

- Removed unused variable warning in `AlignAssignments` cop

### Migration

Update your configuration:

```yaml
# Before (.rubocop.yml)
require:
  - tablecop

# After (.rubocop.yml)
plugins:
  - rubocop-tablecop
```

Update your Gemfile:

```ruby
# Before
gem "tablecop"

# After
gem "rubocop-tablecop", "~> 0.2"
```

## [0.1.0] - 2025-12-10

### Added

- `Tablecop/CondenseWhen` - Condenses multi-line `when` clauses to single lines and aligns `then` keywords
- `Tablecop/AlignMethods` - Aligns contiguous single-line method definitions on the `=` operator
- `Tablecop/AlignAssignments` - Aligns consecutive assignment statements on the `=` operator
- `Tablecop/SafeEndlessMethod` - Converts multi-line methods to endless or traditional one-liner form, avoiding RuboCop's known bugs
- Safe default configuration that disables known-buggy RuboCop cops:
  - `Style/EndlessMethod` (heredoc destruction, rescue orphaning, module_eval failures)
  - `Style/DoubleNegation` (semantically wrong: `!!false` ≠ `!false.nil?`)
  - `Style/HashExcept` (breaks mixed symbol/string key handling)
  - `Layout/ExtraSpacing` with `ForceEqualSignAlignment` (infinite loops with heredocs)
- Documentation of known RuboCop autocorrect bugs in `docs/known-issues.md`
