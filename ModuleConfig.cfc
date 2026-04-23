component {

	this.name         = "jdbcMonitor";
	this.author       = "John Wilson";
	this.webUrl       = "https://github.com/Daemach/jdbcMonitor";
	this.version      = "1.0.0";
	this.cfmapping    = "jdbcMonitor";
	this.entryPoint   = "jdbcMonitor";
	this.autoMapModels = false;
	this.modelNamespace = "jdbcMonitor";
	this.dependencies = [];

	function configure() {
		settings = {
			enabled:              false,
			provider:             "auto",
			historySize:          300,
			slowQueryThreshold:   2000,
			maxSQLLength:         10000,
			maxBindingValueLength: 500,
			excludeDatasources:   [],
			excludePatterns:      [],
			injectSourceComments: false
		};
		interceptors = [];
	}

	function onLoad() {
		if ( !application.keyExists( "__jdbcMonitorStore" ) ) {
			application.__jdbcMonitorStore = createObject( "java", "java.util.concurrent.ConcurrentLinkedDeque" ).init();
		}
		if ( !application.keyExists( "__jdbcMonitorIdCounter" ) ) {
			application.__jdbcMonitorIdCounter = createObject( "java", "java.util.concurrent.atomic.AtomicLong" ).init( 0 );
		}

		syncSettingsToAppScope( settings );

		if ( structKeyExists( server, "boxlang" ) ) {
			application.__jdbcMonitorProvider = "boxlang";
		} else if ( structKeyExists( server, "lucee" ) ) {
			application.__jdbcMonitorProvider = "lucee";
		} else {
			application.__jdbcMonitorProvider = "qb-only";
		}

		application.__jdbcMonitorDataFile = expandPath( moduleMapping & "/data/persisted-settings.json" );
		application.__jdbcMonitorLastActivity = 0;
		loadPersistedSettings();

		binder
			.map( "QueryStore@jdbcMonitor" )
			.to( "#moduleMapping#.models.QueryStore" )
			.asSingleton()
			.initWith( settings = settings );

		var useQBInterceptor = ( settings.provider == "auto" || settings.provider == "qb" );
		if ( useQBInterceptor ) {
			controller.getInterceptorService().registerInterceptor(
				interceptorClass = "#moduleMapping#.interceptors.QBQueryCollector",
				interceptorName  = "QBQueryCollector@jdbcMonitor"
			);
		}
	}

	function onUnload() {
		application.delete( "__jdbcMonitorStore" );
		application.delete( "__jdbcMonitorSettings" );
		application.delete( "__jdbcMonitorIdCounter" );
		application.delete( "__jdbcMonitorDataFile" );
		application.delete( "__jdbcMonitorLastActivity" );
		application.delete( "__jdbcMonitorProvider" );
	}

	private void function syncSettingsToAppScope( required struct settings ) {
		application.__jdbcMonitorSettings = {
			enabled:              arguments.settings.enabled,
			historySize:          arguments.settings.historySize,
			slowQueryThreshold:   arguments.settings.slowQueryThreshold,
			maxSQLLength:         arguments.settings.maxSQLLength,
			maxBindingValueLength: arguments.settings.maxBindingValueLength,
			excludeDatasources:   arguments.settings.excludeDatasources,
			excludePatterns:      arguments.settings.excludePatterns,
			injectSourceComments: arguments.settings.injectSourceComments
		};
	}

	private void function loadPersistedSettings() {
		try {
			var dataFile = application.__jdbcMonitorDataFile ?: "";
			if ( !len( dataFile ) || !fileExists( dataFile ) ) return;

			var saved = deserializeJSON( fileRead( dataFile ) );
			if ( !isStruct( saved ) ) return;

			for ( var key in saved ) {
				if ( key == "enabled" ) continue;
				if ( application.__jdbcMonitorSettings.keyExists( key ) ) {
					application.__jdbcMonitorSettings[ key ] = saved[ key ];
				}
			}
			writeLog( text="jdbcMonitor: loaded #arrayLen( application.__jdbcMonitorSettings.excludePatterns ?: [] )# exclude patterns", file="jdbcMonitor" );
		} catch ( any e ) {
			writeLog( text="jdbcMonitor: loadPersistedSettings error: #e.message#", type="error", file="jdbcMonitor" );
		}
	}

}
