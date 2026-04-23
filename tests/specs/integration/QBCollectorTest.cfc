component extends="tests.specs.BaseTest" {

	function beforeAll() {
		initAppScope();
	}

	function run() {
		describe( "QBQueryCollector", function() {

			beforeEach( function() {
				resetStore();
				application.__jdbcMonitorSettings.enabled = true;
				application.__jdbcMonitorLastActivity = now().getTime();
				request.__jdbcMonitorQBActive = false;
				variables.store = getQueryStore();
			} );

			it( "records a QB query with source=qb and bindings", function() {
				store.record( makeQueryRecord( {
					"sql": "SELECT * FROM users WHERE id = ?",
					"source": "qb",
					"bindings": [
						{ "value": 42, "cfsqltype": "cf_sql_integer" }
					]
				} ) );
				var queries = store.getQueries();
				expect( queries ).toHaveLength( 1 );
				expect( queries[ 1 ].source ).toBe( "qb" );
				expect( queries[ 1 ].bindings ).toHaveLength( 1 );
				expect( queries[ 1 ].bindings[ 1 ].value ).toBe( 42 );
			} );

			it( "preQBExecute sets the QB active flag", function() {
				request.__jdbcMonitorQBActive = true;
				expect( request.__jdbcMonitorQBActive ).toBeTrue();
			} );

			it( "postQBExecute clears the QB active flag", function() {
				request.__jdbcMonitorQBActive = true;
				request.__jdbcMonitorQBActive = false;
				expect( request.__jdbcMonitorQBActive ).toBeFalse();
			} );

		} );
	}

}
