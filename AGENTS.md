# Repository Guidelines

## Project Structure & Module Organization

This is a Rails 7.2 geospatial administration application. Application code lives in `app/`: ActiveRecord and Mongoid models are in `app/models`, HTML/API controllers in `app/controllers`, templates in `app/views`, browser code in `app/javascript`, and styles in `app/assets/stylesheets`. Routes and environment settings belong under `config/`. PostgreSQL/PostGIS migrations and seed data are under `db/`. Container setup is defined by `Dockerfile` and `compose.yaml`.

Keep domain responsibilities distinct: `Province` and `Subdistrict` use PostgreSQL/PostGIS, while flexible sensor, event, and metadata records use the Mongoid-backed `DynamicLayer`.

## Build, Test, and Development Commands

- `docker compose build` builds the Ruby 3.3.6/Rails application image.
- `docker compose up` starts Rails, PostGIS, and MongoDB; browse to `http://localhost:3000`.
- `docker compose run --rm web bin/rails db:migrate` applies schema changes.
- `docker compose run --rm web bin/rails db:seed` loads development sample data.
- `docker compose run --rm web bin/rails console` opens a Rails console with both data stores configured.
- `docker compose run --rm web bin/rails test` runs the Rails test suite once tests are added.
- `docker compose down` stops the development services without deleting volumes.

Copy `.env.example` to `.env` for local settings. Never commit `.env`.

## Coding Style & Naming Conventions

Follow standard Rails conventions: two-space indentation, `snake_case` for files and methods, `CamelCase` for classes, and plural table/resource names. Keep controllers thin and move reusable domain logic into models or focused service objects. Name migrations descriptively, for example `AddStatusToDynamicLayers`. Preserve EPSG:4326 for imported geometry and validate geometry before persistence.

## Testing Guidelines

No test directory or coverage threshold is currently committed. Add tests under Rails-standard `test/` paths, using names such as `test/models/province_test.rb` and `test/controllers/api/provinces_controller_test.rb`. Cover authentication, API response shape, spatial queries, invalid geometry, and MongoDB/PostGIS integration. Run migrations and the full test command before opening a pull request.

## Commit & Pull Request Guidelines

Use short, imperative commit subjects such as `Add province boundary endpoint`; keep unrelated changes separate. Pull requests should explain the problem and solution, list verification commands, note migrations or environment changes, and link relevant issues. Include screenshots for dashboard or map changes and sample JSON for API changes.

## Security & Configuration

Do not commit credentials, MapTiler keys, or production connection strings. Replace seeded credentials before deployment. Production changes should use a secret manager, HTTPS, restricted CORS/CSP rules, and explicit role-based authorization.
