/**
 * Lucee native query listener - self-contained (no WireBox) because it's
 * instantiated in Application.cfc before ColdBox boots.
 *
 * IMPORTANT: Lucee 5.4's query listener is fragile - too much work in after()
 * can corrupt the queryExecute() return value. Keep after() minimal.
 */
component {

	function init() {
		variables.SKIP_WORDS = [ "jdbcMonitor", "Grammar", "coldbox" ];
		return this;
	}

	function before( caller, args ) {
		if ( !( application.__jdbcMonitorSettings.enabled ?: false ) ) return arguments;

		var fileName = "unknown";
		var line = 0;
		try {
			var stack = callStackGet();
			for ( var frame in stack ) {
				var tpl = frame.template ?: "";
				var skip = false;
				for ( var w in variables.SKIP_WORDS ) {
					if ( findNoCase( w, tpl ) ) { skip = true; break; }
				}
				if ( !skip && len( tpl ) ) {
					fileName = listLast( tpl, "\/" );
					line = frame.lineNumber ?: 0;
					break;
				}
			}
		} catch ( any e ) {
			fileName = listLast( arguments.caller.template ?: "", "\/" );
			line = arguments.caller.line ?: 0;
		}
		request.__jdbcMonitorCaller = fileName & ":" & line;
		return arguments;
	}

	function after( caller, args, result, meta ) {
		if ( !( application.__jdbcMonitorSettings.enabled ?: false ) ) return arguments;

		try {
			if ( !( request.__jdbcMonitorQBActive ?: false )
				&& structKeyExists( application, "__jdbcMonitorStore" ) ) {

				var record = _buildRecord( argumentCollection = arguments );
				if ( !isNull( record ) ) {
					if ( !isNull( result ) && isQuery( result ) ) {
						record["recordCount"] = result.recordCount;
					}
					application.__jdbcMonitorStore.addFirst( record );
					_trimStore();
				}
			}
		} catch ( any e ) {}
		return arguments;
	}

	function error( args, caller, meta, exception ) {
		request.__jdbcMonitorQBActive = false;

		try {
			if ( ( application.__jdbcMonitorSettings.enabled ?: false )
				&& structKeyExists( application, "__jdbcMonitorStore" ) ) {

				var record = _buildRecord( argumentCollection = arguments );
				if ( !isNull( record ) ) {
					record["error"] = true;
					record["errorMessage"] = arguments.exception.message ?: "";
					record["errorDetail"] = arguments.exception.detail ?: "";
					record["stackTrace"] = arguments.exception.stackTrace ?: "";
					application.__jdbcMonitorStore.addFirst( record );
					_trimStore();
				}
			}
		} catch ( any e ) {}
		throw( object = arguments.exception );
	}

	// --- Private helpers ---

	private any function _buildRecord( required struct args, any meta ) {
		var sqlText = arguments.args.sql ?: "";
		var ds = len( arguments.args.datasource ?: "" ) ? arguments.args.datasource : "default";

		var patterns = application.__jdbcMonitorSettings.excludePatterns ?: [];
		if ( isArray( patterns ) && arrayLen( patterns ) ) {
			for ( var p in patterns ) {
				if ( len( p ) && findNoCase( p, sqlText ) ) return;
			}
		}

		var excludeDS = application.__jdbcMonitorSettings.excludeDatasources ?: [];
		if ( isArray( excludeDS ) && arrayLen( excludeDS ) && len( ds ) && arrayFindNoCase( excludeDS, ds ) ) {
			return;
		}

		var maxLen = application.__jdbcMonitorSettings.maxSQLLength ?: 10000;
		if ( len( sqlText ) > maxLen ) {
			sqlText = left( sqlText, maxLen ) & "... [truncated]";
		}

		if ( !structKeyExists( application, "__jdbcMonitorIdCounter" ) ) {
			application.__jdbcMonitorIdCounter = createObject( "java", "java.util.concurrent.atomic.AtomicLong" ).init( 0 );
		}

		var execTime = 0;
		if ( !isNull( arguments.meta ) && isStruct( arguments.meta ) ) {
			execTime = arguments.meta.executionTime ?: 0;
		}

		var paramData = _extractParams( arguments.args );

		return {
			"id":             application.__jdbcMonitorIdCounter.incrementAndGet(),
			"sql":            sqlText,
			"executionTime":  execTime,
			"timestamp":      now().getTime(),
			"caller":         request.__jdbcMonitorCaller ?: "unknown:0",
			"datasource":     ds,
			"recordCount":    0,
			"queryType":      _detectQueryType( sqlText ),
			"bindings":       paramData.bindings,
			"namedBindings":  paramData.namedBindings,
			"error":          false,
			"errorMessage":   "",
			"errorDetail":    "",
			"stackTrace":     "",
			"source":         "listener"
		};
	}

	private struct function _extractParams( required struct args ) {
		var result = { "bindings": [], "namedBindings": {} };
		if ( !structKeyExists( arguments.args, "params" ) || isNull( arguments.args.params ) ) return result;

		var params = arguments.args.params;
		var maxValLen = application.__jdbcMonitorSettings.maxBindingValueLength ?: 500;

		if ( isArray( params ) ) {
			for ( var p in params ) {
				if ( isStruct( p ) && structKeyExists( p, "value" ) ) {
					arrayAppend( result.bindings, {
						"value": _truncateValue( p.value ?: "", maxValLen ),
						"cfsqltype": p.cfsqltype ?: p.type ?: "",
						"list": p.list ?: false,
						"null": p.null ?: false
					} );
				} else if ( isSimpleValue( p ) ) {
					arrayAppend( result.bindings, { "value": _truncateValue( p, maxValLen ), "cfsqltype": "" } );
				}
			}
		} else if ( isStruct( params ) ) {
			for ( var key in params ) {
				var val = params[ key ];
				if ( isStruct( val ) && structKeyExists( val, "value" ) ) {
					result.namedBindings[ key ] = {
						"value": _truncateValue( val.value ?: "", maxValLen ),
						"cfsqltype": val.cfsqltype ?: val.type ?: "",
						"list": val.list ?: false,
						"null": val.null ?: false
					};
				} else if ( isSimpleValue( val ) ) {
					result.namedBindings[ key ] = { "value": _truncateValue( val, maxValLen ), "cfsqltype": "" };
				} else {
					try {
						result.namedBindings[ key ] = { "value": _truncateValue( serializeJSON( val ), maxValLen ), "cfsqltype": "" };
					} catch ( any e ) {
						result.namedBindings[ key ] = { "value": "[complex]", "cfsqltype": "" };
					}
				}
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

	private string function _truncateValue( required any val, required numeric maxLen ) {
		var s = isSimpleValue( arguments.val ) ? arguments.val : "";
		if ( len( s ) > arguments.maxLen ) {
			return left( s, arguments.maxLen ) & "...";
		}
		return s;
	}

	private void function _trimStore() {
		var capacity = application.__jdbcMonitorSettings.historySize ?: 300;
		while ( application.__jdbcMonitorStore.size() > capacity ) {
			application.__jdbcMonitorStore.removeLast();
		}
	}

}
