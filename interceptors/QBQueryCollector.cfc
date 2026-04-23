component extends="coldbox.system.Interceptor" {

	property name="queryStore" inject="QueryStore@jdbcMonitor";

	function preQBExecute( event, interceptData ) {
		request.__jdbcMonitorQBActive = true;
	}

	function postQBExecute( event, interceptData ) {
		request.__jdbcMonitorQBActive = false;

		if ( isNull( variables.queryStore ) || !variables.queryStore.isEnabled() ) return;

		try {
			var data = arguments.interceptData;
			if ( data.pretend ?: false ) return;

			var ds = "default";
			if ( isStruct( data.options ?: "" ) && data.options.keyExists( "datasource" ) && len( data.options.datasource ) ) {
				ds = data.options.datasource;
			}

			var rowCount = 0;
			if ( !isNull( data.query ) && isQuery( data.query ) ) {
				rowCount = data.query.recordCount;
			}

			variables.queryStore.record( {
				sql:            data.sql ?: "",
				executionTime:  data.executionTime ?: 0,
				timestamp:      now().getTime(),
				caller:         _findCaller(),
				datasource:     ds,
				recordCount:    rowCount,
				queryType:      _detectQueryType( data.sql ?: "" ),
				bindings:       _extractBindings( data.bindings ?: [] ),
				namedBindings:  {},
				error:          false,
				errorMessage:   "",
				errorDetail:    "",
				stackTrace:     "",
				source:         "qb"
			} );
		} catch ( any e ) {}
	}

	private string function _findCaller() {
		var stack = callStackGet();
		var skipPatterns = [ "jdbcMonitor", "qb/models", "coldbox/system", "Grammar" ];

		for ( var frame in stack ) {
			var template = replace( frame.template ?: "", "\", "/", "all" );
			var shouldSkip = false;
			for ( var pattern in skipPatterns ) {
				if ( findNoCase( pattern, template ) ) {
					shouldSkip = true;
					break;
				}
			}
			if ( !shouldSkip && len( template ) ) {
				return "#listLast( template, '/' )#:#frame.lineNumber ?: 0#";
			}
		}
		return "unknown:0";
	}

	private array function _extractBindings( required any bindings ) {
		var result = [];
		if ( !isArray( arguments.bindings ) ) return result;
		for ( var binding in arguments.bindings ) {
			if ( isStruct( binding ) ) {
				arrayAppend( result, { value: binding.value ?: "", cfsqltype: binding.cfsqltype ?: binding.sqltype ?: "" } );
			} else {
				arrayAppend( result, { value: binding, cfsqltype: "" } );
			}
		}
		return result;
	}

	private string function _detectQueryType( required string sql ) {
		var trimmed = trim( reReplace( arguments.sql, "^/\*.*?\*/\s*", "" ) );
		var firstWord = uCase( listFirst( trimmed, " " & chr( 9 ) & chr( 10 ) & chr( 13 ) ) );
		switch ( firstWord ) {
			case "SELECT": return "SELECT";
			case "INSERT": return "INSERT";
			case "UPDATE": return "UPDATE";
			case "DELETE": return "DELETE";
			case "EXEC": case "EXECUTE": return "EXEC";
			case "CREATE": case "ALTER": case "DROP": return "DDL";
			default: return "OTHER";
		}
	}

}
