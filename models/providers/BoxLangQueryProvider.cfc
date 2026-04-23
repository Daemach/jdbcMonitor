/**
 * BoxLang query provider stub.
 *
 * BoxLang's query interception API is still evolving. Currently, the QB
 * interceptor handles query capture for ColdBox/BoxLang apps. When BoxLang
 * exposes native query events, this provider will be wired up to capture
 * non-QB queries the same way LuceeQueryListener does for Lucee.
 */
component {

	function init() {
		return this;
	}

}
