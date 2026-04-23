const { ref, reactive, computed, watch, onMounted, onBeforeUnmount, nextTick } = Vue;

const app = Vue.createApp({
  setup() {
    const $q = Quasar.useQuasar();

    // --- State ---

    const activeTab = ref('queries');
    const enabled = ref(false);
    const loading = ref(false);
    const paused = ref(false);
    const refreshInterval = ref(3);
    const refreshTimer = ref(null);

    const refreshOptions = [
      { label: 'Off', value: 0 },
      { label: '3s', value: 3 },
      { label: '5s', value: 5 },
      { label: '10s', value: 10 },
      { label: '30s', value: 30 }
    ];

    const queries = ref([]);
    const queryTotal = ref(0);
    const pagination = reactive({ page: 1, rowsPerPage: 50, rowsNumber: 0 });
    const filterDatasource = ref(null);
    const filterQueryType = ref(null);
    const filterSearch = ref('');
    const datasourceOptions = ref([]);

    const queryTypeOptions = [
      { label: 'SELECT', value: 'SELECT' },
      { label: 'INSERT', value: 'INSERT' },
      { label: 'UPDATE', value: 'UPDATE' },
      { label: 'DELETE', value: 'DELETE' },
      { label: 'EXEC', value: 'EXEC' },
      { label: 'DDL', value: 'DDL' },
      { label: 'OTHER', value: 'OTHER' }
    ];

    const errorQueries = ref([]);
    const slowQueries = ref([]);

    const stats = reactive({
      totalQueries: 0, totalErrors: 0, avgExecutionTime: 0,
      maxExecutionTime: 0, slowQueryCount: 0,
      queriesByType: {}, queriesByDatasource: {},
      avgDurationByDatasource: {}, avgRowCountByDatasource: {},
      bufferUsed: 0, bufferCapacity: 100
    });

    const showSettings = ref(false);
    const settingsForm = reactive({
      historySize: 300, slowQueryThreshold: 2000, maxSQLLength: 10000,
      maxBindingValueLength: 500, excludeDatasources: [], injectSourceComments: false
    });

    const excludePatterns = ref([]);
    const newPattern = ref('');
    const showMuteDialog = ref(false);
    const mutePattern = ref('');

    const expandedRowId = ref(null);
    const pausedBeforeExpand = ref(false);

    const chartByType = ref(null);
    const chartByDatasource = ref(null);
    const chartAvgDuration = ref(null);
    const chartAvgRowCount = ref(null);

    const columns = [
      { name: 'id', label: '#', field: 'id', align: 'left', sortable: true, style: 'width: 50px' },
      { name: 'timestamp', label: 'Time', field: 'timestamp', align: 'left', sortable: true, style: 'width: 150px' },
      { name: 'sql', label: 'SQL', field: 'sql', align: 'left', headerStyle: 'width: 100%' },
      { name: 'datasource', label: 'Datasource', field: 'datasource', align: 'left', style: 'width: 120px' },
      { name: 'executionTime', label: 'Duration', field: 'executionTime', align: 'left', sortable: true, style: 'width: 90px' },
      { name: 'recordCount', label: 'Rows', field: 'recordCount', align: 'left', sortable: true, style: 'width: 60px' },
      { name: 'caller', label: 'Caller', field: 'caller', align: 'left', style: 'width: 180px' },
      { name: 'source', label: 'Source', field: 'source', align: 'center', style: 'width: 70px' }
    ];

    // --- Computed ---

    const filteredErrors = computed(() => {
      if (!filterSearch.value) return errorQueries.value;
      const term = filterSearch.value.toLowerCase();
      return errorQueries.value.filter(q =>
        (q.sql || '').toLowerCase().includes(term) ||
        (q.caller || '').toLowerCase().includes(term) ||
        (q.errorMessage || '').toLowerCase().includes(term)
      );
    });

    const filteredSlow = computed(() => {
      if (!filterSearch.value) return slowQueries.value;
      const term = filterSearch.value.toLowerCase();
      return slowQueries.value.filter(q =>
        (q.sql || '').toLowerCase().includes(term) ||
        (q.caller || '').toLowerCase().includes(term)
      );
    });

    const currentResultCount = computed(() => {
      if (activeTab.value === 'queries') return queryTotal.value;
      if (activeTab.value === 'errors') return filteredErrors.value.length;
      if (activeTab.value === 'slow') return filteredSlow.value.length;
      return 0;
    });

    // --- Private Functions ---

    async function fetchJSON(path) {
      const resp = await fetch(API_BASE + path);
      const json = await resp.json();
      return json.data !== undefined ? json.data : json;
    }

    async function postJSON(path, body) {
      const resp = await fetch(API_BASE + path, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: body ? JSON.stringify(body) : '{}'
      });
      const json = await resp.json();
      return json.data !== undefined ? json.data : json;
    }

    async function refreshData() {
      const promises = [refreshStats()];
      if (activeTab.value === 'queries') {
        promises.push(refreshQueries(), refreshDatasources());
      } else if (activeTab.value === 'errors') {
        promises.push(refreshErrors());
      } else if (activeTab.value === 'slow') {
        promises.push(refreshSlow());
      } else if (activeTab.value === 'excluded') {
        promises.push(refreshPatterns());
      }
      await Promise.all(promises);
    }

    async function refreshQueries() {
      loading.value = true;
      try {
        const offset = (pagination.page - 1) * pagination.rowsPerPage;
        const params = new URLSearchParams({
          limit: pagination.rowsPerPage,
          offset: offset,
          datasource: filterDatasource.value || '',
          queryType: filterQueryType.value || '',
          search: filterSearch.value || ''
        });
        const data = await fetchJSON('/queries?' + params.toString());
        queries.value = data.queries || [];
        queryTotal.value = data.total || 0;
        pagination.rowsNumber = queryTotal.value;
      } finally {
        loading.value = false;
      }
    }

    async function refreshStats() {
      const s = await fetchJSON('/stats');
      if (s) {
        enabled.value = !!s.enabled;
        Object.assign(stats, s);
      }
      if (activeTab.value === 'stats') {
        nextTick(() => renderCharts());
      }
    }

    async function refreshErrors() {
      errorQueries.value = await fetchJSON('/errors?limit=100');
    }

    async function refreshSlow() {
      slowQueries.value = await fetchJSON('/slow?limit=100');
    }

    async function refreshDatasources() {
      const ds = await fetchJSON('/datasources');
      datasourceOptions.value = (ds || []).map(d => ({ label: d, value: d }));
    }

    async function loadSettings() {
      const s = await fetchJSON('/settings');
      if (s) {
        Object.assign(settingsForm, {
          historySize: s.historySize || 300,
          slowQueryThreshold: s.slowQueryThreshold || 2000,
          maxSQLLength: s.maxSQLLength || 10000,
          maxBindingValueLength: s.maxBindingValueLength || 500,
          excludeDatasources: s.excludeDatasources || [],
          injectSourceComments: !!s.injectSourceComments
        });
        enabled.value = !!s.enabled;
      }
    }

    async function refreshPatterns() {
      excludePatterns.value = await fetchJSON('/patterns') || [];
    }

    function collapseRow() {
      expandedRowId.value = null;
      if (!pausedBeforeExpand.value) paused.value = false;
    }

    function setupAutoRefresh() {
      if (refreshTimer.value) clearInterval(refreshTimer.value);
      paused.value = false;
      if (refreshInterval.value > 0) {
        refreshTimer.value = setInterval(() => {
          if (!paused.value) refreshData();
        }, refreshInterval.value * 1000);
      }
    }

    function savePrefs() {
      try {
        localStorage.setItem('jdbcMonitor_prefs', JSON.stringify({
          activeTab: activeTab.value,
          refreshInterval: refreshInterval.value,
          rowsPerPage: pagination.rowsPerPage
        }));
      } catch (e) { /* quota exceeded or private browsing */ }
    }

    function loadPrefs() {
      try {
        const saved = JSON.parse(localStorage.getItem('jdbcMonitor_prefs') || '{}');
        if (saved.activeTab) activeTab.value = saved.activeTab;
        if (saved.refreshInterval !== undefined) refreshInterval.value = saved.refreshInterval;
        if (saved.rowsPerPage) pagination.rowsPerPage = saved.rowsPerPage;
      } catch (e) { /* corrupt data */ }
    }

    function formatBindingValue(b) {
      const val = b.value;
      const type = (b.cfsqltype || '').toLowerCase();
      if (b.null || val === null || val === undefined) return 'NULL';
      if (val === '' && !type) return 'NULL';
      if (type.includes('integer') || type.includes('numeric') || type.includes('decimal')
              || type.includes('float') || type.includes('double') || type.includes('money')
              || type.includes('bigint') || type.includes('smallint') || type.includes('tinyint') || type.includes('bit')) {
        return String(val);
      }
      return "'" + String(val).replace(/'/g, "''") + "'";
    }

    const chartColors = ['#42A5F5', '#66BB6A', '#FFA726', '#EF5350', '#AB47BC', '#78909C', '#8D6E63'];

    function renderChart(canvasId, chartRef, label, dataObj, options) {
      const ctx = document.getElementById(canvasId);
      if (!ctx) return;
      if (chartRef.value) chartRef.value.destroy();
      chartRef.value = new Chart(ctx.getContext('2d'), {
        type: 'bar',
        data: {
          labels: Object.keys(dataObj),
          datasets: [{
            label: label,
            data: Object.values(dataObj),
            backgroundColor: chartColors
          }]
        },
        options: Object.assign({ responsive: true, plugins: { legend: { display: false } } }, options || {})
      });
    }

    const integerTicks = { scales: { y: { ticks: { precision: 0 } } } };

    function renderCharts() {
      renderChart('chartByType', chartByType, 'Queries', stats.queriesByType || {}, integerTicks);
      renderChart('chartByDatasource', chartByDatasource, 'Queries', stats.queriesByDatasource || {}, integerTicks);
      renderChart('chartAvgDuration', chartAvgDuration, 'Avg ms', stats.avgDurationByDatasource || {}, integerTicks);
      renderChart('chartAvgRowCount', chartAvgRowCount, 'Avg Rows', stats.avgRowCountByDatasource || {}, integerTicks);
    }

    // --- Public Functions (template-bound) ---

    function onRequest(props) {
      Object.assign(pagination, props.pagination);
      refreshQueries();
    }

    async function toggleEnabled() {
      const result = await postJSON('/toggle');
      enabled.value = result.enabled;
    }

    async function clearBuffer() {
      await postJSON('/clear');
      refreshData();
    }

    function togglePause() {
      paused.value = !paused.value;
    }

    function toggleRow(id) {
      if (expandedRowId.value === id) {
        expandedRowId.value = null;
        if (!pausedBeforeExpand.value) paused.value = false;
      } else {
        pausedBeforeExpand.value = paused.value;
        paused.value = true;
        expandedRowId.value = id;
      }
    }

    function nonEmptyBindings(bindings) {
      if (!bindings || !Array.isArray(bindings)) return [];
      return bindings.filter(b => b.value !== null && b.value !== undefined && String(b.value) !== '');
    }

    function hasNamedBindings(row) {
      return row.namedBindings && typeof row.namedBindings === 'object' && Object.keys(row.namedBindings).length > 0;
    }

    function isTruncated(row) {
      return (row.sql || '').endsWith('... [truncated]');
    }

    function truncate(val, max) {
      const s = String(val ?? '');
      return s.length > max ? s.substring(0, max) + '…' : s;
    }

    function interpolateSQL(row) {
      const nb = row.namedBindings || {};
      const namedKeys = Object.keys(nb);
      if (namedKeys.length > 0) {
        let sql = row.sql;
        namedKeys.sort((a, b) => b.length - a.length);
        for (const key of namedKeys) {
          const replacement = formatBindingValue(nb[key]);
          sql = sql.replace(new RegExp(':' + key + '\\b', 'gi'), replacement);
        }
        return sql;
      }
      if (!row.bindings || !row.bindings.length) return row.sql;
      let sql = row.sql;
      for (const b of row.bindings) {
        sql = sql.replace('?', formatBindingValue(b));
      }
      return sql;
    }

    function copySQL(row) {
      const text = interpolateSQL(row);
      navigator.clipboard.writeText(text).then(() => {
        $q.notify({ message: 'SQL copied to clipboard', color: 'positive', position: 'top', timeout: 1500 });
        collapseRow();
      });
    }

    function promptMute(row) {
      const sql = (row.sql || '').trim();
      mutePattern.value = sql.length > 150 ? sql.substring(0, 150) : sql;
      showMuteDialog.value = true;
    }

    async function confirmMute() {
      if (!mutePattern.value) return;
      await postJSON('/patterns', { pattern: mutePattern.value });
      showMuteDialog.value = false;
      collapseRow();
      $q.notify({ message: 'Pattern added — matching queries will be excluded', color: 'orange', textColor: 'white', position: 'top', timeout: 2000 });
      refreshPatterns();
    }

    async function addPatternManual() {
      if (!newPattern.value) return;
      await postJSON('/patterns', { pattern: newPattern.value });
      newPattern.value = '';
      $q.notify({ message: 'Pattern added', color: 'positive', position: 'top', timeout: 1500 });
      refreshPatterns();
    }

    async function removePattern(index) {
      await fetch(API_BASE + '/patterns', {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ index: index })
      });
      refreshPatterns();
    }

    async function saveSettings() {
      await postJSON('/settings', { ...settingsForm });
      showSettings.value = false;
      $q.notify({ message: 'Settings saved', color: 'positive', position: 'top', timeout: 1500 });
      refreshStats();
    }

    function formatTime(ts) {
      if (!ts) return '';
      const d = new Date(ts);
      return d.toLocaleTimeString('en-US', { hour12: false }) + '.' + String(d.getMilliseconds()).padStart(3, '0');
    }

    function durationColor(ms) {
      var threshold = settingsForm.slowQueryThreshold || 2000;
      if (ms >= threshold * 2) return 'red';
      if (ms >= threshold) return 'orange';
      if (ms >= threshold / 2) return 'amber';
      return 'green';
    }

    function rowClass(row) {
      if (row.error) return 'row-error';
      if (row.executionTime >= (settingsForm.slowQueryThreshold || 2000)) return 'row-slow';
      return '';
    }

    // --- Watchers ---

    watch(refreshInterval, () => { setupAutoRefresh(); savePrefs(); });
    watch(activeTab, () => { refreshData(); savePrefs(); });
    watch(() => pagination.rowsPerPage, () => { savePrefs(); });
    watch(filterDatasource, () => { refreshQueries(); });
    watch(filterQueryType, () => { refreshQueries(); });
    watch(filterSearch, () => { refreshQueries(); });

    // --- Lifecycle ---

    let onVisibilityChange;

    onMounted(() => {
      Quasar.Dark.set(true);
      loadPrefs();
      loadSettings();
      refreshData();
      refreshDatasources();
      refreshPatterns();
      setupAutoRefresh();
      onVisibilityChange = () => {
        if (document.hidden) {
          if (refreshTimer.value) { clearInterval(refreshTimer.value); refreshTimer.value = null; }
        } else {
          refreshData();
          setupAutoRefresh();
        }
      };
      document.addEventListener('visibilitychange', onVisibilityChange);
    });

    onBeforeUnmount(() => {
      if (refreshTimer.value) clearInterval(refreshTimer.value);
      document.removeEventListener('visibilitychange', onVisibilityChange);
    });

    // --- Return ---

    return {
      activeTab, enabled, loading, paused,
      refreshInterval, refreshOptions,
      queries, queryTotal, pagination,
      filterDatasource, filterQueryType, filterSearch,
      datasourceOptions, queryTypeOptions,
      errorQueries, slowQueries,
      stats, showSettings, settingsForm,
      excludePatterns, newPattern, showMuteDialog, mutePattern,
      expandedRowId, columns,
      filteredErrors, filteredSlow, currentResultCount,
      toggleEnabled, clearBuffer, togglePause,
      onRequest, toggleRow, copySQL, promptMute,
      confirmMute, addPatternManual, removePattern,
      saveSettings,
      formatTime, interpolateSQL, durationColor, rowClass,
      truncate, nonEmptyBindings, hasNamedBindings, isTruncated
    };
  }
});

app.use(Quasar);
app.mount('#q-app');
