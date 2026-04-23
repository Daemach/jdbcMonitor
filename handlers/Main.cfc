component extends="coldbox.system.EventHandler" {

	function index( event, rc, prc ) {
		if ( application.keyExists( "__jdbcMonitorSettings" ) ) {
			application.__jdbcMonitorSettings.enabled = true;
		}
		application.__jdbcMonitorLastActivity = now().getTime();

		prc.settings = controller.getConfigSettings().modules.jdbcMonitor.settings;
		event.setView( view = "main/index", layout = "Main" );
	}

}
