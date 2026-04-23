component extends="tests.specs.BaseTest" {

	function beforeAll() {
		initAppScope();
	}

	function afterAll() {}

	function run() {
		describe( "QueryStore", function() {

			beforeEach( function() {
				resetStore();
				initAppScope();
				variables.store = getQueryStore();
			} );

			describe( "record()", function() {

				it( "adds a query to the store and assigns an incremental id", function() {
					store.record( makeQueryRecord( { "sql": "SELECT 1" } ) );
					store.record( makeQueryRecord( { "sql": "SELECT 2" } ) );
					var queries = store.getQueries();
					expect( queries ).toHaveLength( 2 );
					expect( queries[ 1 ].id ).toBeGT( queries[ 2 ].id );
				} );

				it( "does not record when disabled", function() {
					application.__jdbcMonitorSettings.enabled = false;
					store.record( makeQueryRecord() );
					expect( store.getQueries() ).toBeEmpty();
				} );

				it( "trims buffer at capacity", function() {
					application.__jdbcMonitorSettings.historySize = 5;
					for ( var i = 1; i <= 10; i++ ) {
						store.record( makeQueryRecord( { "sql": "SELECT #i#" } ) );
					}
					expect( application.__jdbcMonitorStore.size() ).toBe( 5 );
				} );

				it( "truncates SQL exceeding maxSQLLength", function() {
					application.__jdbcMonitorSettings.maxSQLLength = 20;
					store.record( makeQueryRecord( { "sql": repeatString( "X", 50 ) } ) );
					var queries = store.getQueries();
					expect( queries[ 1 ].sql ).toEndWith( "... [truncated]" );
					expect( len( queries[ 1 ].sql ) ).toBeLT( 50 );
				} );

				it( "skips queries matching exclude patterns", function() {
					application.__jdbcMonitorSettings.excludePatterns = [ "sessionCache" ];
					store.record( makeQueryRecord( { "sql": "SELECT * FROM sessionCache" } ) );
					expect( store.getQueries() ).toBeEmpty();
				} );

				it( "skips queries from excluded datasources", function() {
					application.__jdbcMonitorSettings.excludeDatasources = [ "cacheDS" ];
					store.record( makeQueryRecord( { "datasource": "cacheDS" } ) );
					expect( store.getQueries() ).toBeEmpty();
				} );

				it( "auto-disables after 15 min of inactivity", function() {
					application.__jdbcMonitorLastActivity = now().getTime() - 1000000;
					store.record( makeQueryRecord() );
					expect( store.getQueries() ).toBeEmpty();
					expect( application.__jdbcMonitorSettings.enabled ).toBeFalse();
				} );

			} );

			describe( "getQueries()", function() {

				it( "filters by datasource", function() {
					store.record( makeQueryRecord( { "datasource": "main" } ) );
					store.record( makeQueryRecord( { "datasource": "cache" } ) );
					var results = store.getQueries( datasource = "main" );
					expect( results ).toHaveLength( 1 );
					expect( results[ 1 ].datasource ).toBe( "main" );
				} );

				it( "filters by queryType", function() {
					store.record( makeQueryRecord( { "queryType": "SELECT" } ) );
					store.record( makeQueryRecord( { "queryType": "INSERT" } ) );
					var results = store.getQueries( queryType = "SELECT" );
					expect( results ).toHaveLength( 1 );
				} );

				it( "filters by search term in SQL", function() {
					store.record( makeQueryRecord( { "sql": "SELECT * FROM users" } ) );
					store.record( makeQueryRecord( { "sql": "SELECT * FROM orders" } ) );
					var results = store.getQueries( search = "users" );
					expect( results ).toHaveLength( 1 );
				} );

				it( "paginates with limit and offset", function() {
					for ( var i = 1; i <= 10; i++ ) {
						store.record( makeQueryRecord( { "sql": "SELECT #i#" } ) );
					}
					var page1 = store.getQueries( limit = 3, offset = 0 );
					var page2 = store.getQueries( limit = 3, offset = 3 );
					expect( page1 ).toHaveLength( 3 );
					expect( page2 ).toHaveLength( 3 );
					expect( page1[ 1 ].id ).toNotBe( page2[ 1 ].id );
				} );

			} );

			describe( "getErrors()", function() {

				it( "returns only error queries", function() {
					store.record( makeQueryRecord( { "error": false } ) );
					store.record( makeQueryRecord( { "error": true, "errorMessage": "boom" } ) );
					var errors = store.getErrors();
					expect( errors ).toHaveLength( 1 );
					expect( errors[ 1 ].errorMessage ).toBe( "boom" );
				} );

			} );

			describe( "getSlowQueries()", function() {

				it( "returns queries exceeding threshold", function() {
					application.__jdbcMonitorSettings.slowQueryThreshold = 100;
					store.record( makeQueryRecord( { "executionTime": 50 } ) );
					store.record( makeQueryRecord( { "executionTime": 200 } ) );
					var slow = store.getSlowQueries();
					expect( slow ).toHaveLength( 1 );
					expect( slow[ 1 ].executionTime ).toBe( 200 );
				} );

			} );

			describe( "getStats()", function() {

				it( "returns correct aggregations", function() {
					store.record( makeQueryRecord( { "executionTime": 100, "queryType": "SELECT", "datasource": "main" } ) );
					store.record( makeQueryRecord( { "executionTime": 200, "queryType": "INSERT", "datasource": "main" } ) );
					store.record( makeQueryRecord( { "executionTime": 50, "queryType": "SELECT", "datasource": "cache", "error": true } ) );
					var stats = store.getStats();
					expect( stats.totalQueries ).toBe( 3 );
					expect( stats.totalErrors ).toBe( 1 );
					expect( stats.maxExecutionTime ).toBe( 200 );
					expect( stats.queriesByType ).toHaveKey( "SELECT" );
					expect( stats.queriesByType.SELECT ).toBe( 2 );
					expect( stats.queriesByDatasource ).toHaveKey( "main" );
					expect( stats.queriesByDatasource.main ).toBe( 2 );
				} );

			} );

			describe( "clear()", function() {

				it( "empties the store and resets the counter", function() {
					store.record( makeQueryRecord() );
					store.record( makeQueryRecord() );
					store.clear();
					expect( store.getQueries() ).toBeEmpty();
					expect( application.__jdbcMonitorIdCounter.get() ).toBe( 0 );
				} );

			} );

			describe( "settings management", function() {

				it( "getSettings returns current settings", function() {
					var s = store.getSettings();
					expect( s ).toHaveKey( "enabled" );
					expect( s ).toHaveKey( "historySize" );
					expect( s ).toHaveKey( "slowQueryThreshold" );
				} );

				it( "updateSettings merges new values", function() {
					store.updateSettings( { "historySize": 999 } );
					expect( application.__jdbcMonitorSettings.historySize ).toBe( 999 );
				} );

				it( "updateSettings ignores unknown keys", function() {
					store.updateSettings( { "bogus": true } );
					expect( application.__jdbcMonitorSettings ).notToHaveKey( "bogus" );
				} );

			} );

			describe( "exclude patterns", function() {

				it( "addExcludePattern adds a pattern", function() {
					store.addExcludePattern( "FROM sessions" );
					expect( store.getExcludePatterns() ).toInclude( "FROM sessions" );
				} );

				it( "addExcludePattern does not add duplicates", function() {
					store.addExcludePattern( "FROM sessions" );
					store.addExcludePattern( "FROM sessions" );
					expect( store.getExcludePatterns().len() ).toBe( 1 );
				} );

				it( "removeExcludePattern removes by index", function() {
					store.addExcludePattern( "pattern1" );
					store.addExcludePattern( "pattern2" );
					store.removeExcludePattern( 1 );
					var patterns = store.getExcludePatterns();
					expect( patterns ).toHaveLength( 1 );
					expect( patterns[ 1 ] ).toBe( "pattern2" );
				} );

			} );

			describe( "getDatasources()", function() {

				it( "returns unique sorted datasource names", function() {
					store.record( makeQueryRecord( { "datasource": "bravo" } ) );
					store.record( makeQueryRecord( { "datasource": "alpha" } ) );
					store.record( makeQueryRecord( { "datasource": "bravo" } ) );
					var ds = store.getDatasources();
					expect( ds ).toHaveLength( 2 );
					expect( ds[ 1 ] ).toBe( "alpha" );
				} );

			} );

		} );
	}

}
