component {

	this.name = "jdbcMonitor-tests-" & hash( getCurrentTemplatePath() );

	this.datasources = {};

	variables.isBoxLang = structKeyExists( server, "boxlang" );
	variables.isCI      = false;
	if (
		structKeyExists( server, "system" ) &&
		structKeyExists( server.system, "environment" ) &&
		isStruct( server.system.environment )
	) {
		variables.isCI = (
			( structKeyExists( server.system.environment, "CI" ) && len( server.system.environment.CI ) ) ||
			( structKeyExists( server.system.environment, "GITHUB_ACTIONS" ) && len( server.system.environment.GITHUB_ACTIONS ) )
		);
	}

	if ( variables.isCI || variables.isBoxLang ) {
		this.datasources[ "jdbcMonitorTests" ] = {
			class            : "com.mysql.cj.jdbc.Driver",
			bundleName       : "com.mysql.cj",
			bundleVersion    : "8.0.33",
			connectionString : "jdbc:mysql://127.0.0.1:3306/jdbcmonitor_test?useUnicode=true&characterEncoding=UTF-8&useLegacyDatetimeCode=true",
			username         : "jdbcmonitor",
			password         : "jdbcmonitor_password"
		};
	} else {
		variables._envFile = expandPath( "./.env" );
		if ( fileExists( variables._envFile ) ) {
			variables._envVars = {};
			for ( variables._line in listToArray( fileRead( variables._envFile ), chr( 10 ) ) ) {
				variables._line = trim( variables._line );
				if ( !len( variables._line ) || left( variables._line, 1 ) == "##" ) continue;
				variables._eq = find( "=", variables._line );
				if ( variables._eq > 0 ) variables._envVars[ trim( left( variables._line, variables._eq - 1 ) ) ] = trim( mid( variables._line, variables._eq + 1, len( variables._line ) ) );
			}
			variables._dsConfig = { username : variables._envVars.DB_USER ?: "", password : variables._envVars.DB_PASSWORD ?: "" };
			if ( structKeyExists( variables._envVars, "DB_CLASS" ) ) variables._dsConfig.class = variables._envVars.DB_CLASS;
			if ( structKeyExists( variables._envVars, "DB_BUNDLENAME" ) ) variables._dsConfig.bundleName = variables._envVars.DB_BUNDLENAME;
			if ( structKeyExists( variables._envVars, "DB_BUNDLEVERSION" ) ) variables._dsConfig.bundleVersion = variables._envVars.DB_BUNDLEVERSION;
			if ( structKeyExists( variables._envVars, "DB_CONNECTIONSTRING" ) ) variables._dsConfig.connectionString = variables._envVars.DB_CONNECTIONSTRING;
			this.datasources[ "jdbcMonitorTests" ] = variables._dsConfig;
		}
	}

	this.defaultDatasource = "jdbcMonitorTests";

	this.mappings[ "/jdbcMonitor" ] = expandPath( "../" );
	this.mappings[ "/tests" ]      = expandPath( "./" );
	this.mappings[ "/testbox" ]    = expandPath( "../testbox" );

	function onRequestStart() {
		if ( url.reinit ?: false ) {
			structClear( application );
		}
	}

}
