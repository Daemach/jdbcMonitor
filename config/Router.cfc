component {

	function configure() {
		route( "/api/queries" ).withAction( { GET: "queries" } ).toHandler( "API" );
		route( "/api/errors" ).withAction( { GET: "errors" } ).toHandler( "API" );
		route( "/api/slow" ).withAction( { GET: "slow" } ).toHandler( "API" );
		route( "/api/stats" ).withAction( { GET: "stats" } ).toHandler( "API" );
		route( "/api/datasources" ).withAction( { GET: "datasources" } ).toHandler( "API" );
		route( "/api/clear" ).withAction( { POST: "clear" } ).toHandler( "API" );
		route( "/api/toggle" ).withAction( { POST: "toggle" } ).toHandler( "API" );
		route( "/api/settings" ).withAction( { GET: "getSettings", POST: "updateSettings" } ).toHandler( "API" );
		route( "/api/patterns" ).withAction( { GET: "getPatterns", POST: "addPattern", DELETE: "removePattern" } ).toHandler( "API" );
		route( "/" ).toHandler( "Main" ).toAction( "index" );
	}

}
