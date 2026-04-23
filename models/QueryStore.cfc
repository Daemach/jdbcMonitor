component singleton accessors="true" {

	property name="settings" type="struct";

	function init( struct settings = {} ) {
		variables.settings = arguments.settings;
		return this;
	}

	// -- Write ----------------------------------------------------------------

	void function record( required struct queryData ) {
		if ( !isEnabled() ) return;

		// Auto-disable after 15 min of no UI activity
		var lastActivity = application.__jdbcMonitorLastActivity ?: 0;
		if ( lastActivity > 0 && ( now().getTime() - lastActivity ) > 900000 ) {
			setEnabled( false );
			return;
		}

		var excludeDS = getAppSetting( "excludeDatasources", [] );
		if ( arrayLen( excludeDS ) && arrayFindNoCase( excludeDS, arguments.queryData.datasource ?: "" ) ) {
			return;
		}

		var patterns = getAppSetting( "excludePatterns", [] );
		if ( isArray( patterns ) && arrayLen( patterns ) ) {
			var sql = arguments.queryData.sql ?: "";
			for ( var p in patterns ) {
				if ( len( p ) && findNoCase( p, sql ) ) return;
			}
		}

		arguments.queryData.id = _nextId();

		var maxLen = getAppSetting( "maxSQLLength", 10000 );
		if ( len( arguments.queryData.sql ?: "" ) > maxLen ) {
			arguments.queryData.sql = left( arguments.queryData.sql, maxLen ) & "... [truncated]";
		}

		if ( !arguments.queryData.keyExists( "timestamp" ) ) {
			arguments.queryData.timestamp = now().getTime();
		}

		getStore().addFirst( arguments.queryData );

		var capacity = getAppSetting( "historySize", 300 );
		while ( getStore().size() > capacity ) {
			getStore().removeLast();
		}
	}

	// -- Read -----------------------------------------------------------------

	array function getQueries(
		numeric limit  = 50,
		numeric offset = 0,
		string datasource = "",
		string queryType  = "",
		string search     = ""
	) {
		var all = storeToArray();
		if ( len( arguments.datasource ) ) {
			all = all.filter( ( q ) => q.datasource == datasource );
		}
		if ( len( arguments.queryType ) ) {
			all = all.filter( ( q ) => q.queryType == queryType );
		}
		if ( len( arguments.search ) ) {
			var term = lCase( arguments.search );
			all = all.filter( ( q ) => findNoCase( term, q.sql ?: "" ) || findNoCase( term, q.caller ?: "" ) || findNoCase( term, q.errorMessage ?: "" ) );
		}
		var start = arguments.offset + 1;
		var end   = min( start + arguments.limit - 1, arrayLen( all ) );
		if ( start > arrayLen( all ) ) return [];
		return all.slice( start, end - start + 1 );
	}

	// Combined query + count in a single storeToArray() snapshot
	struct function getQueriesWithCount(
		numeric limit  = 50,
		numeric offset = 0,
		string datasource = "",
		string queryType  = "",
		string search     = ""
	) {
		var all = storeToArray();
		if ( len( arguments.datasource ) ) {
			all = all.filter( ( q ) => q.datasource == datasource );
		}
		if ( len( arguments.queryType ) ) {
			all = all.filter( ( q ) => q.queryType == queryType );
		}
		if ( len( arguments.search ) ) {
			var term = lCase( arguments.search );
			all = all.filter( ( q ) => findNoCase( term, q.sql ?: "" ) || findNoCase( term, q.caller ?: "" ) || findNoCase( term, q.errorMessage ?: "" ) );
		}
		var total = arrayLen( all );
		var start = arguments.offset + 1;
		var end   = min( start + arguments.limit - 1, total );
		var rows  = ( start > total ) ? [] : all.slice( start, end - start + 1 );
		return { queries: rows, total: total };
	}

	numeric function getQueryCount(
		string datasource = "",
		string queryType  = "",
		string search     = ""
	) {
		var all = storeToArray();
		if ( len( arguments.datasource ) ) {
			all = all.filter( ( q ) => q.datasource == datasource );
		}
		if ( len( arguments.queryType ) ) {
			all = all.filter( ( q ) => q.queryType == queryType );
		}
		if ( len( arguments.search ) ) {
			var term = lCase( arguments.search );
			all = all.filter( ( q ) => findNoCase( term, q.sql ?: "" ) || findNoCase( term, q.caller ?: "" ) || findNoCase( term, q.errorMessage ?: "" ) );
		}
		return arrayLen( all );
	}

	array function getErrors( numeric limit = 50 ) {
		var errors = storeToArray().filter( ( q ) => ( q.error ?: false ) );
		if ( !arrayLen( errors ) ) return [];
		return errors.slice( 1, min( arguments.limit, arrayLen( errors ) ) );
	}

	array function getSlowQueries( numeric limit = 50 ) {
		var threshold = getAppSetting( "slowQueryThreshold", 2000 );
		var slow = storeToArray().filter( ( q ) => ( q.executionTime ?: 0 ) >= threshold );
		if ( !arrayLen( slow ) ) return [];
		return slow.slice( 1, min( arguments.limit, arrayLen( slow ) ) );
	}

	struct function getStats() {
		var all           = storeToArray();
		var totalQueries  = arrayLen( all );
		var totalErrors   = 0;
		var totalTime     = 0;
		var maxTime       = 0;
		var threshold     = getAppSetting( "slowQueryThreshold", 2000 );
		var slowCount     = 0;
		var byType        = {};
		var byDatasource  = {};
		var dsByDuration   = {};
		var dsByRowCount   = {};

		for ( var q in all ) {
			var execTime = q.executionTime ?: 0;
			totalTime += execTime;
			if ( execTime > maxTime ) maxTime = execTime;
			if ( execTime >= threshold ) slowCount++;
			if ( q.error ?: false ) totalErrors++;
			var qt = q.queryType ?: "OTHER";
			byType[ qt ] = ( byType[ qt ] ?: 0 ) + 1;
			var ds = q.datasource ?: "unknown";
			byDatasource[ ds ] = ( byDatasource[ ds ] ?: 0 ) + 1;
			dsByDuration[ ds ] = ( dsByDuration[ ds ] ?: 0 ) + execTime;
			dsByRowCount[ ds ] = ( dsByRowCount[ ds ] ?: 0 ) + val( q.recordCount ?: 0 );
		}

		var avgDurationByDs  = {};
		var avgRowCountByDs  = {};
		for ( var ds in byDatasource ) {
			var count = byDatasource[ ds ];
			avgDurationByDs[ ds ]  = round( dsByDuration[ ds ] / count );
			avgRowCountByDs[ ds ]  = round( dsByRowCount[ ds ] / count );
		}

		return {
			enabled:                  isEnabled(),
			totalQueries:             totalQueries,
			totalErrors:              totalErrors,
			avgExecutionTime:         totalQueries > 0 ? round( totalTime / totalQueries ) : 0,
			maxExecutionTime:         maxTime,
			slowQueryCount:           slowCount,
			queriesByType:            byType,
			queriesByDatasource:      byDatasource,
			avgDurationByDatasource:  avgDurationByDs,
			avgRowCountByDatasource:  avgRowCountByDs,
			bufferUsed:               getStore().size(),
			bufferCapacity:           getAppSetting( "historySize", 300 )
		};
	}

	// -- Control --------------------------------------------------------------

	void function clear() {
		getStore().clear();
		if ( application.keyExists( "__jdbcMonitorIdCounter" ) ) {
			application.__jdbcMonitorIdCounter.set( 0 );
		}
	}

	boolean function isEnabled() {
		return getAppSetting( "enabled", false );
	}

	void function setEnabled( required boolean enabled ) {
		if ( application.keyExists( "__jdbcMonitorSettings" ) ) {
			application.__jdbcMonitorSettings.enabled = arguments.enabled;
		}
		_persist();
	}

	struct function getSettings() {
		return getAppSetting( "", {} );
	}

	void function updateSettings( required struct newSettings ) {
		if ( !application.keyExists( "__jdbcMonitorSettings" ) ) return;
		for ( var key in arguments.newSettings ) {
			if ( application.__jdbcMonitorSettings.keyExists( key ) ) {
				application.__jdbcMonitorSettings[ key ] = arguments.newSettings[ key ];
			}
		}
		_persist();
	}

	array function getDatasources() {
		var ds = {};
		for ( var q in storeToArray() ) {
			ds[ q.datasource ?: "unknown" ] = true;
		}
		return ds.keyArray().sort( "textnocase" );
	}

	// -- Exclusion Patterns ---------------------------------------------------

	array function getExcludePatterns() {
		var patterns = getAppSetting( "excludePatterns", [] );
		return isArray( patterns ) ? patterns : [];
	}

	void function addExcludePattern( required string pattern ) {
		if ( !len( trim( arguments.pattern ) ) ) return;
		if ( !application.keyExists( "__jdbcMonitorSettings" ) ) return;
		if ( !application.__jdbcMonitorSettings.keyExists( "excludePatterns" ) ) {
			application.__jdbcMonitorSettings.excludePatterns = [];
		}
		if ( !arrayFindNoCase( application.__jdbcMonitorSettings.excludePatterns, trim( arguments.pattern ) ) ) {
			arrayAppend( application.__jdbcMonitorSettings.excludePatterns, trim( arguments.pattern ) );
		}
		_persist();
	}

	void function removeExcludePattern( required numeric index ) {
		if ( !application.keyExists( "__jdbcMonitorSettings" ) ) return;
		var patterns = application.__jdbcMonitorSettings.excludePatterns ?: [];
		if ( arguments.index >= 1 && arguments.index <= arrayLen( patterns ) ) {
			arrayDeleteAt( patterns, arguments.index );
		}
		_persist();
	}

	// -- Internal -------------------------------------------------------------

	private any function getStore() {
		if ( !application.keyExists( "__jdbcMonitorStore" ) ) {
			application.__jdbcMonitorStore = createObject( "java", "java.util.concurrent.ConcurrentLinkedDeque" ).init();
		}
		return application.__jdbcMonitorStore;
	}

	private array function storeToArray() {
		var all = arrayNew( 1 ).append( getStore().toArray(), true );
		var patterns = getAppSetting( "excludePatterns", [] );
		if ( !isArray( patterns ) || !arrayLen( patterns ) ) return all;
		return all.filter( ( q ) => {
			var sql = q.sql ?: "";
			for ( var p in patterns ) {
				if ( len( p ) && findNoCase( p, sql ) ) return false;
			}
			return true;
		} );
	}

	private numeric function _nextId() {
		if ( !application.keyExists( "__jdbcMonitorIdCounter" ) ) {
			application.__jdbcMonitorIdCounter = createObject( "java", "java.util.concurrent.atomic.AtomicLong" ).init( 0 );
		}
		return application.__jdbcMonitorIdCounter.incrementAndGet();
	}

	private void function _persist() {
		try {
			var dataFile = application.__jdbcMonitorDataFile ?: "";
			if ( !len( dataFile ) ) return;

			var data = {
				enabled:              application.__jdbcMonitorSettings.enabled ?: false,
				excludePatterns:      application.__jdbcMonitorSettings.excludePatterns ?: [],
				historySize:          application.__jdbcMonitorSettings.historySize ?: 300,
				slowQueryThreshold:   application.__jdbcMonitorSettings.slowQueryThreshold ?: 2000,
				maxSQLLength:         application.__jdbcMonitorSettings.maxSQLLength ?: 10000,
				maxBindingValueLength: application.__jdbcMonitorSettings.maxBindingValueLength ?: 500
			};

			var dir = getDirectoryFromPath( dataFile );
			if ( !directoryExists( dir ) ) {
				directoryCreate( dir, true );
			}
			fileWrite( dataFile, serializeJSON( data ) );
		} catch ( any e ) {}
	}

	private any function getAppSetting( required string key, any defaultValue = "" ) {
		if ( !application.keyExists( "__jdbcMonitorSettings" ) ) {
			return arguments.defaultValue;
		}
		if ( !len( arguments.key ) ) {
			return application.__jdbcMonitorSettings;
		}
		return application.__jdbcMonitorSettings[ arguments.key ] ?: arguments.defaultValue;
	}

}
