# Changelog

This project follows [Semantic Versioning](https://semver.org). Install a release by its git tag.

## [0.2.0] - 2026-11-06

### Changed

- Works in any ActiveRecord app. `Fetchable` is now optional, and related records are loaded with `where` rather than an app-provided `in_list`.
- Allows `activerecord` 6.0 and newer.
- Related classes are looked up on first use, so resourcers can refer to each other.
- The test suite covers lists, indexes, relations, query counts and pass-through against a real database.

### Fixed

- `has_many` lookups no longer require the related resourcer to `index_by` the foreign key.
- The generated `*_lookup` methods return the lookup hash instead of raising.
- The gem loads without ActiveRecord being required first.

## [0.1.0] - 2024-08-01

- Initial release
