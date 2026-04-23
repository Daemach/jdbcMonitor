component extends="tests.specs.BaseTest" {

	function beforeAll() {
		initAppScope();
		variables.listener = getLuceeListener();
	}

	function run() {
		describe( "Deduplication", function() {

			beforeEach( function() {
				resetStore();
				application.__jdbcMonitorSettings.enabled = true;
				application.__jdbcMonitorLastActivity = now().getTime();
				request.__jdbcMonitorQBActive = false;
			} );

			it( "listener skips when QB flag is active", function() {
				request.__jdbcMonitorQBActive = true;
				listener.after( {}, { "sql": "SELECT 1" }, queryNew( "" ), { "executionTime": 1 } );
				expect( storeToArray() ).toBeEmpty();
			} );

			it( "listener captures when QB flag is not active", function() {
				request.__jdbcMonitorQBActive = false;
				listener.after( {}, { "sql": "SELECT 1" }, queryNew( "" ), { "executionTime": 1 } );
				expect( storeToArray() ).toHaveLength( 1 );
			} );

			it( "simulates QB then native: produces exactly 2 records with correct sources", function() {
				var store = getQueryStore();

				request.__jdbcMonitorQBActive = true;
				listener.after( {}, { "sql": "SELECT qb_query" }, queryNew( "" ), { "executionTime": 1 } );
				store.record( makeQueryRecord( { "sql": "SELECT qb_query", "source": "qb" } ) );
				request.__jdbcMonitorQBActive = false;

				listener.after( {}, { "sql": "SELECT native_query" }, queryNew( "" ), { "executionTime": 1 } );

				var queries = storeToArray();
				expect( queries ).toHaveLength( 2 );

				var sources = queries.map( function( q ) { return q.source; } );
				expect( sources ).toInclude( "qb" );
				expect( sources ).toInclude( "listener" );
			} );

			it( "error() clears QB flag so subsequent native queries are captured", function() {
				request.__jdbcMonitorQBActive = true;
				try {
					listener.error(
						{ "sql": "SELECT 1" }, {}, {},
						{ "message": "boom", "detail": "", "stackTrace": "" }
					);
				} catch ( any e ) {}
				expect( request.__jdbcMonitorQBActive ).toBeFalse();

				listener.after( {}, { "sql": "SELECT 2" }, queryNew( "" ), { "executionTime": 1 } );
				var queries = storeToArray();
				var nonError = queries.filter( function( q ) { return !q.error; } );
				expect( nonError ).toHaveLength( 1 );
			} );

		} );
	}

	private array function storeToArray() {
		return arrayNew( 1 ).append( application.__jdbcMonitorStore.toArray(), true );
	}

}
