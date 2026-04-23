component extends="coldbox.system.RestHandler" {

	property name="queryStore" inject="QueryStore@jdbcMonitor";

	function preHandler( event, rc, prc, action, eventArguments ) {
		application.__jdbcMonitorLastActivity = now().getTime();
		if ( application.keyExists( "__jdbcMonitorSettings" ) && !application.__jdbcMonitorSettings.enabled ) {
			application.__jdbcMonitorSettings.enabled = true;
		}
	}

	function queries( event, rc, prc ) {
		event.paramValue( "limit", 50 );
		event.paramValue( "offset", 0 );
		event.paramValue( "datasource", "" );
		event.paramValue( "queryType", "" );
		event.paramValue( "search", "" );

		var result = queryStore.getQueriesWithCount(
			limit      = val( rc.limit ),
			offset     = val( rc.offset ),
			datasource = rc.datasource,
			queryType  = rc.queryType,
			search     = rc.search
		);
		result.limit  = val( rc.limit );
		result.offset = val( rc.offset );
		event.getResponse().setData( result );
	}

	function errors( event, rc, prc ) {
		event.paramValue( "limit", 50 );
		event.getResponse().setData( queryStore.getErrors( val( rc.limit ) ) );
	}

	function slow( event, rc, prc ) {
		event.paramValue( "limit", 50 );
		event.getResponse().setData( queryStore.getSlowQueries( val( rc.limit ) ) );
	}

	function stats( event, rc, prc ) {
		event.getResponse().setData( queryStore.getStats() );
	}

	function datasources( event, rc, prc ) {
		event.getResponse().setData( queryStore.getDatasources() );
	}

	function clear( event, rc, prc ) {
		queryStore.clear();
		event.getResponse().setData( { cleared: true } );
	}

	function toggle( event, rc, prc ) {
		var newState = !queryStore.isEnabled();
		queryStore.setEnabled( newState );
		event.getResponse().setData( { enabled: newState } );
	}

	function getSettings( event, rc, prc ) {
		event.getResponse().setData( queryStore.getSettings() );
	}

	function updateSettings( event, rc, prc ) {
		queryStore.updateSettings( event.getHTTPContent( json = true ) );
		event.getResponse().setData( queryStore.getSettings() );
	}

	function getPatterns( event, rc, prc ) {
		event.getResponse().setData( queryStore.getExcludePatterns() );
	}

	function addPattern( event, rc, prc ) {
		var body = event.getHTTPContent( json = true );
		queryStore.addExcludePattern( body.pattern ?: "" );
		event.getResponse().setData( queryStore.getExcludePatterns() );
	}

	function removePattern( event, rc, prc ) {
		var body = event.getHTTPContent( json = true );
		queryStore.removeExcludePattern( val( body.index ?: 0 ) );
		event.getResponse().setData( queryStore.getExcludePatterns() );
	}

}
