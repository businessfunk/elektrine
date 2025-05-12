# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Elektrine is a Phoenix web application built with Elixir. It uses PostgreSQL for database storage, Tailwind CSS for styling, and esbuild for JavaScript bundling. The project follows the standard Phoenix framework structure and conventions.

## Common Commands

### Setup and Installation

```bash
# Install and setup all dependencies
mix setup
```

### Database Commands

```bash
# Create and migrate database
mix ecto.setup

# Reset database (drop, create, migrate)
mix ecto.reset

# Run migrations
mix ecto.migrate
```

### Development

```bash
# Start Phoenix server in development mode
mix phx.server

# Start Phoenix server with interactive Elixir shell
iex -S mix phx.server

# Compile the project
mix compile

# Install dependencies
mix deps.get
```

### Asset Management

```bash
# Setup assets (install Tailwind and esbuild if missing)
mix assets.setup

# Build assets (Tailwind CSS and JavaScript)
mix assets.build

# Build and minify assets for production
mix assets.deploy
```

### Testing

```bash
# Run all tests
mix test

# Run a specific test file
mix test path/to/test_file.exs

# Run a specific test (line number)
mix test path/to/test_file.exs:42
```

## Architecture

Elektrine follows the standard Phoenix application architecture:

1. **Context Modules** - Business logic is organized into context modules within `lib/elektrine/`
2. **Web Layer** - Web-related code is in `lib/elektrine_web/`
   - **Controllers** - Handle HTTP requests and responses
   - **Templates** - Render HTML using HEEx templates
   - **Components** - Reusable UI components
   - **Router** - Defines application routes

3. **Database Layer** - Uses Ecto with PostgreSQL
   - Schema definitions are in context modules
   - Migrations are in `priv/repo/migrations/`

4. **Assets** - Frontend assets managed through esbuild and Tailwind
   - JS in `assets/js/`
   - CSS in `assets/css/`
   - Tailwind configuration in `assets/tailwind.config.js`

The application uses the following key dependencies:
- Phoenix 1.7.21 (web framework)
- Phoenix LiveView (for interactive features)
- Ecto (database interactions)
- Swoosh (email handling)
- Bandit (HTTP server)
- Tailwind CSS (styling)
- esbuild (JavaScript bundling)
- DaisyUI