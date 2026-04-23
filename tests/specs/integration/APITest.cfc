component extends="tests.specs.BaseTest" {

	function beforeAll() {
		initAppScope();
	}

	function run() {
		describe( "QueryStore API surface", function() {

			beforeEach( function() {
				resetStore();
				application.__jdbcMonitorSettings.enabled = true;
				application.__jdbcMonitorSettings.excludePatterns = [];
				application.__jdbcMonitorLastActivity = now().getTime();
				variables.store = getQueryStore();
			} );

			describe( "queries endpoint", function() {

				it( "returns paginated results with correct structure", function() {
					for ( var i = 1; i <= 10; i++ ) {
						store.record( makeQueryRecord( { "sql": "SELECT #i#" } ) );
					}
					var result = store.getQueriesWithCount( limit = 3, offset = 0 );
					expect( result ).toHaveKey( "queries" );
					expect( result ).toHaveKey( "total" );
					expect( result.total ).toBe( 10 );
					expect( result.queries ).toHaveLength( 3 );
				} );

				it( "applies filters in getQueriesWithCount", function() {
					store.record( makeQueryRecord( { "sql": "SELECT 1", "datasource": "main" } ) );
					store.record( makeQueryRecord( { "sql": "INSERT INTO t", "datasource": "main", "queryType": "INSERT" } ) );
					store.record( makeQueryRecord( { "sql": "SELECT 2", "datasource": "cache" } ) );
					var result = store.getQueriesWithCount( datasource = "main" );
					expect( result.total ).toBe( 2 );
				} );

			} );

			describe( "stats endpoint", function() {

				it( "returns complete stats struct", function() {
					store.record( makeQueryRecord( { "executionTime": 100, "queryType": "SELECT" } ) );
					var stats = store.getStats();
					expect( stats ).toHaveKey( "totalQueries" );
					expect( stats ).toHaveKey( "totalErrors" );
					expect( stats ).toHaveKey( "avgExecutionTime" );
					expect( stats ).toHaveKey( "maxExecutionTime" );
					expect( stats ).toHaveKey( "slowQueryCount" );
					expect( stats ).toHaveKey( "queriesByType" );
					expect( stats ).toHaveKey( "queriesByDatasource" );
					expect( stats ).toHaveKey( "bufferUsed" );
					expect( stats ).toHaveKey( "bufferCapacity" );
					expect( stats ).toHaveKey( "enabled" );
				} );

			} );

			describe( "toggle endpoint", function() {

				it( "toggles enabled state", function() {
					expect( store.isEnabled() ).toBeTrue();
					store.setEnabled( false );
					expect( store.isEnabled() ).toBeFalse();
					store.setEnabled( true );
					expect( store.isEnabled() ).toBeTrue();
				} );

			} );

			describe( "clear endpoint", function() {

				it( "empties the buffer", function() {
					store.record( makeQueryRecord() );
					store.record( makeQueryRecord() );
					store.clear();
					expect( store.getQueries() ).toBeEmpty();
				} );

			} );

			describe( "patterns CRUD", function() {

				it( "add, list, remove pattern lifecycle", function() {
					expect( store.getExcludePatterns() ).toBeEmpty();
					store.addExcludePattern( "FROM sessions" );
					store.addExcludePattern( "cbq_jobs" );
					expect( store.getExcludePatterns() ).toHaveLength( 2 );
					store.removeExcludePattern( 1 );
					var remaining = store.getExcludePatterns();
					expect( remaining ).toHaveLength( 1 );
					expect( remaining[ 1 ] ).toBe( "cbq_jobs" );
				} );

			} );

			describe( "settings endpoint", function() {

				it( "reads current settings", function() {
					var s = store.getSettings();
					expect( s ).toHaveKey( "enabled" );
					expect( s ).toHaveKey( "historySize" );
					expect( s ).toHaveKey( "maxBindingValueLength" );
				} );

				it( "updates settings", function() {
					store.updateSettings( { "slowQueryThreshold": 5000 } );
					expect( application.__jdbcMonitorSettings.slowQueryThreshold ).toBe( 5000 );
				} );

			} );

		} );
	}

}
