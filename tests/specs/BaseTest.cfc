component extends="testbox.system.BaseSpec" {

	function isCI() {
		return (
			( server.system.environment.CI ?: "" ) != "" ||
			( server.system.environment.GITHUB_ACTIONS ?: "" ) != ""
		);
	}

	function isBoxLang() {
		return structKeyExists( server, "boxlang" );
	}

	function initAppScope() {
		application.__jdbcMonitorStore = createObject( "java", "java.util.concurrent.ConcurrentLinkedDeque" ).init();
		application.__jdbcMonitorIdCounter = createObject( "java", "java.util.concurrent.atomic.AtomicLong" ).init( 0 );
		application.__jdbcMonitorLastActivity = now().getTime();
		application.__jdbcMonitorSettings = {
			"enabled":              true,
			"historySize":          300,
			"slowQueryThreshold":   2000,
			"maxSQLLength":         10000,
			"maxBindingValueLength": 500,
			"excludeDatasources":   [],
			"excludePatterns":      [],
			"injectSourceComments": false
		};
		application.__jdbcMonitorDataFile = expandPath( "/tests/" ) & "data/test-settings.json";
		application.__jdbcMonitorProvider = "lucee";
	}

	function getQueryStore() {
		return new jdbcMonitor.models.QueryStore( settings = application.__jdbcMonitorSettings );
	}

	function getLuceeListener() {
		return new jdbcMonitor.models.providers.LuceeQueryListener();
	}

	function resetStore() {
		application.__jdbcMonitorStore.clear();
		application.__jdbcMonitorIdCounter.set( 0 );
	}

	function makeQueryRecord( struct overrides = {} ) {
		var defaults = {
			"sql":            "SELECT 1",
			"executionTime":  10,
			"timestamp":      now().getTime(),
			"caller":         "test.cfc:1",
			"datasource":     "default",
			"recordCount":    1,
			"queryType":      "SELECT",
			"bindings":       [],
			"namedBindings":  {},
			"error":          false,
			"errorMessage":   "",
			"errorDetail":    "",
			"stackTrace":     "",
			"source":         "listener"
		};
		structAppend( defaults, arguments.overrides, true );
		return defaults;
	}

}
