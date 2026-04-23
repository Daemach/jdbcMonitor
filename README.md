# jdbcMonitor

A lightweight, drop-in JDBC query monitoring dashboard for ColdBox applications. Captures query history, execution times, errors, and slow queries in an in-memory ring buffer with a Vue+Quasar web UI.

## Installation

```bash
box install jdbcMonitor
```

### Lucee: Enable Native Query Capture

Add to your `Application.cfc` to capture all native `queryExecute()` calls with full parameter values:

```cfml
// Application.cfc — runs before ColdBox boots, so use a relative path
this.query.listener = new modules.jdbcMonitor.models.providers.LuceeQueryListener();
// If installed to modules_app/:
// this.query.listener = new modules_app.jdbcMonitor.models.providers.LuceeQueryListener();
```

Without this, the module still captures all QB queries via ColdBox interceptors.

### BoxLang

The QB interceptor works on BoxLang out of the box. Native query capture will be added when BoxLang exposes query interception events.

## Usage

Navigate to `/jdbcMonitor` in your ColdBox app. Monitoring enables automatically when you open the dashboard and auto-disables after 15 minutes of inactivity.

## What Gets Captured

| Query Source | Lucee | BoxLang | ACF |
|---|---|---|---|
| QB queries (bindings + caller) | Yes | Yes | Yes |
| Native `queryExecute()` with params | Yes | Planned | No |
| `<cfquery>` tag | Yes | Planned | No |
| Raw JDBC / ORM | No | No | No |

## Configuration

Override defaults in your ColdBox config (`config/ColdBox.cfc`):

```cfml
moduleSettings = {
    jdbcMonitor: {
        enabled:              false,      // starts disabled, dashboard enables it
        provider:             "auto",     // "auto", "lucee", "boxlang", "qb"
        historySize:          300,        // ring buffer capacity
        slowQueryThreshold:   2000,       // ms
        maxSQLLength:         10000,      // truncate stored SQL beyond this
        maxBindingValueLength: 500,       // truncate individual binding values
        excludeDatasources:   [],         // datasource names to ignore
        excludePatterns:      [],         // SQL text patterns to exclude
        injectSourceComments: false       // prepend /* caller:file:line */ to SQL
    }
};
```

## Features

- **Configurable ring buffer** — Adjustable buffer capacity and slow query threshold via the Settings dialog. FIFO ring buffer (`ConcurrentLinkedDeque`) with zero memory leaks. Auto-disables after 15 min of inactivity for zero overhead when idle.
- **Mute noisy queries** — Exclude query patterns (session cache, job queue polling) from the dashboard. Add patterns from any query row's "Mute" button or manually on the Excluded tab.
- **Lucee + QB compatibility** — Captures QB queries via ColdBox interceptors on all engines. On Lucee, also captures native `queryExecute()` and `<cfquery>` calls with full parameter values via the query listener API.
- **Copy-paste SQL** — Named params (`:paramName`) and positional params (`?`) are interpolated with actual binding values. One-click copy to clipboard for SSMS-ready SQL.
- **Live auto-refresh** — Configurable polling interval (3s–30s) with pause/resume. Auto-pauses when a row is expanded and when the browser tab is hidden (Page Visibility API).
- **Statistics dashboard** — Summary cards (total queries, errors, avg/max duration, slow count) plus Chart.js bar charts for queries by type, queries by datasource, avg duration by datasource, and avg row count by datasource.
- **Error & slow query tracking** — Dedicated tabs with color-highlighted rows, full error detail + stack trace, and configurable slow query threshold.

## Development

```bash
# Install dependencies
box install

# Start dev server
box server start

# Run tests
box testbox run
```

## License

MIT
