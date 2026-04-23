component extends="tests.specs.BaseTest" {

	function beforeAll() {
		initAppScope();
		variables.listener = getLuceeListener();
	}

	function run() {
		describe( "Param extraction via LuceeQueryListener.after()", function() {

			beforeEach( function() {
				resetStore();
				application.__jdbcMonitorSettings.enabled = true;
				application.__jdbcMonitorLastActivity = now().getTime();
				request.__jdbcMonitorQBActive = false;
			} );

			describe( "array params (positional)", function() {

				it( "extracts simple value array", function() {
					callAfter( { "params": [ "John", 30 ] } );
					var q = getFirst();
					expect( q.bindings ).toHaveLength( 2 );
					expect( q.bindings[ 1 ].value ).toBe( "John" );
					expect( q.bindings[ 2 ].value ).toBe( 30 );
					expect( q.namedBindings ).toBeEmpty();
				} );

				it( "extracts typed struct array with cfsqltype", function() {
					callAfter( { "params": [ { "value": "John", "cfsqltype": "cf_sql_varchar" } ] } );
					var q = getFirst();
					expect( q.bindings[ 1 ].value ).toBe( "John" );
					expect( q.bindings[ 1 ].cfsqltype ).toBe( "cf_sql_varchar" );
				} );

				it( "extracts typed struct array with type key", function() {
					callAfter( { "params": [ { "value": 42, "type": "cf_sql_integer" } ] } );
					var q = getFirst();
					expect( q.bindings[ 1 ].cfsqltype ).toBe( "cf_sql_integer" );
				} );

				it( "handles mixed simple and typed values", function() {
					callAfter( { "params": [ "simple", { "value": 42, "cfsqltype": "cf_sql_integer" } ] } );
					var q = getFirst();
					expect( q.bindings ).toHaveLength( 2 );
					expect( q.bindings[ 1 ].value ).toBe( "simple" );
					expect( q.bindings[ 1 ].cfsqltype ).toBe( "" );
					expect( q.bindings[ 2 ].value ).toBe( 42 );
				} );

				it( "preserves list flag", function() {
					callAfter( { "params": [ { "value": "1,2,3", "cfsqltype": "cf_sql_integer", "list": true } ] } );
					var q = getFirst();
					expect( q.bindings[ 1 ].list ).toBeTrue();
				} );

				it( "preserves null flag", function() {
					callAfter( { "params": [ { "value": "", "cfsqltype": "cf_sql_varchar", "null": true } ] } );
					var q = getFirst();
					expect( q.bindings[ 1 ].null ).toBeTrue();
				} );

			} );

			describe( "struct params (named)", function() {

				it( "extracts simple named values", function() {
					callAfter( { "params": { "name": "John", "age": "30" } } );
					var q = getFirst();
					expect( q.namedBindings ).toHaveKey( "name" );
					expect( q.namedBindings.name.value ).toBe( "John" );
					expect( q.namedBindings ).toHaveKey( "age" );
					expect( q.bindings ).toBeEmpty();
				} );

				it( "extracts typed named values", function() {
					callAfter( { "params": { "id": { "value": 42, "cfsqltype": "cf_sql_integer" } } } );
					var q = getFirst();
					expect( q.namedBindings.id.value ).toBe( 42 );
					expect( q.namedBindings.id.cfsqltype ).toBe( "cf_sql_integer" );
				} );

				it( "handles complex value types via serialization", function() {
					callAfter( { "params": { "data": [ 1, 2, 3 ] } } );
					var q = getFirst();
					expect( q.namedBindings.data.value ).toInclude( "1" );
				} );

			} );

			describe( "edge cases", function() {

				it( "returns empty bindings when params key is missing", function() {
					callAfter( {} );
					var q = getFirst();
					expect( q.bindings ).toBeEmpty();
					expect( q.namedBindings ).toBeEmpty();
				} );

				it( "returns empty for empty array", function() {
					callAfter( { "params": [] } );
					var q = getFirst();
					expect( q.bindings ).toBeEmpty();
				} );

				it( "returns empty for empty struct", function() {
					callAfter( { "params": {} } );
					var q = getFirst();
					expect( q.namedBindings ).toBeEmpty();
				} );

				it( "truncates large binding values", function() {
					application.__jdbcMonitorSettings.maxBindingValueLength = 10;
					callAfter( { "params": [ repeatString( "X", 50 ) ] } );
					var q = getFirst();
					expect( len( q.bindings[ 1 ].value ) ).toBeLTE( 13 );
					expect( q.bindings[ 1 ].value ).toEndWith( "..." );
					application.__jdbcMonitorSettings.maxBindingValueLength = 500;
				} );

			} );

		} );
	}

	private void function callAfter( struct extraArgs = {} ) {
		var args = { "sql": "SELECT 1", "datasource": "test" };
		structAppend( args, arguments.extraArgs, true );
		listener.after(
			{ "template": "test.cfc", "line": 1 },
			args,
			queryNew( "id", "integer" ),
			{ "executionTime": 1 }
		);
	}

	private struct function getFirst() {
		var arr = arrayNew( 1 ).append( application.__jdbcMonitorStore.toArray(), true );
		return arr[ 1 ];
	}

}
