component extends="tests.specs.BaseTest" {

	function beforeAll() {
		initAppScope();
		variables.listener = getLuceeListener();
	}

	function run() {
		describe( "LuceeQueryListener integration", function() {

			beforeEach( function() {
				resetStore();
				application.__jdbcMonitorSettings.enabled = true;
				application.__jdbcMonitorLastActivity = now().getTime();
				request.__jdbcMonitorQBActive = false;
			} );

			describe( "after() captures queries", function() {

				it( "captures a basic query with no params", function() {
					listener.after(
						{ "template": "test.cfc", "line": 1 },
						{ "sql": "SELECT * FROM users", "datasource": "main" },
						queryNew( "id", "integer" ),
						{ "executionTime": 42 }
					);
					var queries = storeToArray();
					expect( queries ).toHaveLength( 1 );
					expect( queries[ 1 ].sql ).toBe( "SELECT * FROM users" );
					expect( queries[ 1 ].datasource ).toBe( "main" );
					expect( queries[ 1 ].executionTime ).toBe( 42 );
					expect( queries[ 1 ].source ).toBe( "listener" );
					expect( queries[ 1 ].bindings ).toBeEmpty();
					expect( queries[ 1 ].namedBindings ).toBeEmpty();
				} );

				it( "captures positional params as bindings", function() {
					listener.after(
						{ "template": "test.cfc", "line": 1 },
						{
							"sql": "SELECT * FROM users WHERE id = ?",
							"datasource": "main",
							"params": [ { "value": 42, "cfsqltype": "cf_sql_integer" } ]
						},
						queryNew( "id", "integer" ),
						{ "executionTime": 10 }
					);
					var queries = storeToArray();
					expect( queries[ 1 ].bindings ).toHaveLength( 1 );
					expect( queries[ 1 ].bindings[ 1 ].value ).toBe( 42 );
					expect( queries[ 1 ].bindings[ 1 ].cfsqltype ).toBe( "cf_sql_integer" );
				} );

				it( "captures named params as namedBindings", function() {
					listener.after(
						{ "template": "test.cfc", "line": 1 },
						{
							"sql": "SELECT * FROM users WHERE name = :name",
							"datasource": "main",
							"params": { "name": { "value": "John", "cfsqltype": "cf_sql_varchar" } }
						},
						queryNew( "id", "integer" ),
						{ "executionTime": 10 }
					);
					var queries = storeToArray();
					expect( queries[ 1 ].namedBindings ).toHaveKey( "name" );
					expect( queries[ 1 ].namedBindings.name.value ).toBe( "John" );
				} );

				it( "captures simple named params", function() {
					listener.after(
						{ "template": "test.cfc", "line": 1 },
						{
							"sql": "SELECT * FROM users WHERE id = :id",
							"datasource": "main",
							"params": { "id": 42 }
						},
						queryNew( "id", "integer" ),
						{ "executionTime": 10 }
					);
					var queries = storeToArray();
					expect( queries[ 1 ].namedBindings ).toHaveKey( "id" );
					expect( queries[ 1 ].namedBindings.id.value ).toBe( 42 );
				} );

				it( "captures recordCount from query result", function() {
					var q = queryNew( "id,name", "integer,varchar", [ { "id": 1, "name": "a" }, { "id": 2, "name": "b" } ] );
					listener.after(
						{ "template": "test.cfc", "line": 1 },
						{ "sql": "SELECT * FROM users", "datasource": "main" },
						q,
						{ "executionTime": 10 }
					);
					var queries = storeToArray();
					expect( queries[ 1 ].recordCount ).toBe( 2 );
				} );

			} );

			describe( "query type detection", function() {

				it( "detects SELECT", function() {
					listener.after( {}, { "sql": "SELECT * FROM t" }, queryNew( "" ), { "executionTime": 1 } );
					expect( storeToArray()[ 1 ].queryType ).toBe( "SELECT" );
				} );

				it( "detects INSERT", function() {
					listener.after( {}, { "sql": "INSERT INTO t VALUES(1)" }, queryNew( "" ), { "executionTime": 1 } );
					expect( storeToArray()[ 1 ].queryType ).toBe( "INSERT" );
				} );

				it( "detects UPDATE", function() {
					listener.after( {}, { "sql": "UPDATE t SET x=1" }, queryNew( "" ), { "executionTime": 1 } );
					expect( storeToArray()[ 1 ].queryType ).toBe( "UPDATE" );
				} );

				it( "detects DELETE", function() {
					listener.after( {}, { "sql": "DELETE FROM t" }, queryNew( "" ), { "executionTime": 1 } );
					expect( storeToArray()[ 1 ].queryType ).toBe( "DELETE" );
				} );

				it( "detects EXEC", function() {
					listener.after( {}, { "sql": "EXEC sp_test" }, queryNew( "" ), { "executionTime": 1 } );
					expect( storeToArray()[ 1 ].queryType ).toBe( "EXEC" );
				} );

				it( "detects DDL", function() {
					listener.after( {}, { "sql": "CREATE TABLE t (id INT)" }, queryNew( "" ), { "executionTime": 1 } );
					expect( storeToArray()[ 1 ].queryType ).toBe( "DDL" );
				} );

			} );

			describe( "exclusion checks", function() {

				it( "skips queries matching exclude patterns", function() {
					application.__jdbcMonitorSettings.excludePatterns = [ "FROM sessions" ];
					listener.after( {}, { "sql": "SELECT * FROM sessions" }, queryNew( "" ), { "executionTime": 1 } );
					expect( storeToArray() ).toBeEmpty();
				} );

				it( "skips queries from excluded datasources", function() {
					application.__jdbcMonitorSettings.excludeDatasources = [ "cacheDS" ];
					listener.after( {}, { "sql": "SELECT 1", "datasource": "cacheDS" }, queryNew( "" ), { "executionTime": 1 } );
					expect( storeToArray() ).toBeEmpty();
				} );

			} );

			describe( "deduplication", function() {

				it( "skips when QB is active", function() {
					request.__jdbcMonitorQBActive = true;
					listener.after( {}, { "sql": "SELECT 1" }, queryNew( "" ), { "executionTime": 1 } );
					expect( storeToArray() ).toBeEmpty();
				} );

			} );

			describe( "error()", function() {

				it( "captures error details", function() {
					var ex = { "message": "Table not found", "detail": "dbo.missing", "stackTrace": "at line 1" };
					try {
						listener.error(
							{ "sql": "SELECT * FROM missing", "datasource": "main" },
							{ "template": "test.cfc", "line": 1 },
							{ "executionTime": 5 },
							ex
						);
					} catch ( any e ) {}
					var queries = storeToArray();
					expect( queries ).toHaveLength( 1 );
					expect( queries[ 1 ].error ).toBeTrue();
					expect( queries[ 1 ].errorMessage ).toBe( "Table not found" );
					expect( queries[ 1 ].errorDetail ).toBe( "dbo.missing" );
				} );

				it( "rethrows the exception", function() {
					expect( function() {
						listener.error(
							{ "sql": "SELECT 1" },
							{},
							{},
							{ "message": "boom", "detail": "", "stackTrace": "" }
						);
					} ).toThrow();
				} );

				it( "clears QB active flag", function() {
					request.__jdbcMonitorQBActive = true;
					try {
						listener.error(
							{ "sql": "SELECT 1" },
							{},
							{},
							{ "message": "boom", "detail": "", "stackTrace": "" }
						);
					} catch ( any e ) {}
					expect( request.__jdbcMonitorQBActive ).toBeFalse();
				} );

			} );

			describe( "SQL truncation", function() {

				it( "truncates SQL exceeding maxSQLLength", function() {
					application.__jdbcMonitorSettings.maxSQLLength = 20;
					listener.after( {}, { "sql": repeatString( "X", 50 ) }, queryNew( "" ), { "executionTime": 1 } );
					var queries = storeToArray();
					expect( queries[ 1 ].sql ).toEndWith( "... [truncated]" );
				} );

			} );

		} );
	}

	private array function storeToArray() {
		return arrayNew( 1 ).append( application.__jdbcMonitorStore.toArray(), true );
	}

}
