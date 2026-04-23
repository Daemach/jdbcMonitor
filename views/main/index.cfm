<style>
#q-app {
  font-family: "Segoe UI", "Noto Sans", "Roboto", "-apple-system", "Helvetica Neue", Helvetica, Arial, sans-serif;
}
.sql-text {
  font-family: "Consolas", "Monaco", "Courier New", monospace;
  font-size: 12px;
  white-space: pre-wrap;
  word-break: break-all;
}
.sql-text-truncated {
  font-family: "Consolas", "Monaco", "Courier New", monospace;
  font-size: 12px;
}
td.sql-cell {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 0;
}
.row-error {
  background-color: rgba(255, 0, 0, 0.08) !important;
}
.row-slow {
  background-color: rgba(255, 165, 0, 0.08) !important;
}
.stat-card {
  min-width: 150px;
}
.expanded-detail {
  padding: 12px 16px;
  background: rgba(0,0,0,0.03);
  border-left: 3px solid #1976d2;
}
.row-expanded {
  background-color: rgba(25, 118, 210, 0.15) !important;
}
.sticky-toolbar {
  position: sticky;
  top: 0;
  z-index: 100;
}
.sticky-tabs {
  position: sticky;
  top: 50px;
  z-index: 99;
}
.sticky-filter {
  position: sticky;
  top: 86px;
  z-index: 98;
}
.q-tab-panels .q-tab-panel {
  padding: 0 !important;
}
.q-table__container .q-table__middle {
  max-height: calc(100vh - 160px);
  overflow-y: auto;
}
</style>

<cfoutput>
<div id="q-app">

  <!-- Toolbar -->
  <div class="row no-wrap shadow-1 sticky-toolbar">
    <q-toolbar class="bg-primary text-white">
      <q-toolbar-title>
        <q-icon name="storage" class="q-mr-sm"></q-icon>
        JDBC Monitor
      </q-toolbar-title>
      <q-chip v-if="stats.totalErrors > 0" color="red" text-color="white" dense>
        {{ stats.totalErrors }} {{ stats.totalErrors === 1 ? 'error' : 'errors' }}
      </q-chip>
      <q-chip color="blue-grey" text-color="white" dense class="q-ml-sm">
        <q-icon name="inventory_2" size="xs" class="q-mr-xs"></q-icon>
        {{ stats.bufferUsed }} / {{ stats.bufferCapacity }} buffered
      </q-chip>
      <q-toggle v-model="enabled" color="green" label="Enabled" dark dense class="q-ml-md" @update:model-value="toggleEnabled"></q-toggle>
      <q-btn flat dense icon="delete_sweep" @click="clearBuffer" class="q-ml-sm">
        <q-tooltip>Clear buffer</q-tooltip>
      </q-btn>
      <q-btn flat dense icon="settings" @click="showSettings = true" class="q-ml-xs">
        <q-tooltip>Settings</q-tooltip>
      </q-btn>
      <q-separator vertical dark class="q-mx-sm"></q-separator>
      <q-select
        v-model="refreshInterval"
        :options="refreshOptions"
        dense outlined dark
        map-options emit-value
        label="Refresh"
        style="width: 120px"
        class="q-ml-sm"
      ></q-select>
      <q-btn
        flat dense round
        :icon="paused ? 'play_arrow' : 'pause'"
        :color="paused ? 'amber' : 'white'"
        @click="togglePause"
        class="q-ml-xs"
        v-if="refreshInterval > 0"
      >
        <q-tooltip>{{ paused ? 'Resume' : 'Pause' }} auto-refresh</q-tooltip>
      </q-btn>
    </q-toolbar>
  </div>

  <!-- Tabs -->
  <q-tabs v-model="activeTab" dense class="bg-grey-9 text-white sticky-tabs" active-color="blue-4" indicator-color="blue-4" align="left">
    <q-tab name="queries" label="All Queries">
      <q-badge v-if="stats.bufferUsed > 0" color="blue-grey" floating>{{ stats.bufferUsed }}</q-badge>
    </q-tab>
    <q-tab name="errors" label="Errors">
      <q-badge v-if="stats.totalErrors > 0" color="red" floating>{{ stats.totalErrors }}</q-badge>
    </q-tab>
    <q-tab name="slow" label="Slow Queries">
      <q-badge v-if="stats.slowQueryCount > 0" color="orange" floating>{{ stats.slowQueryCount }}</q-badge>
    </q-tab>
    <q-tab name="excluded" label="Excluded">
      <q-badge v-if="excludePatterns.length > 0" color="teal" floating>{{ excludePatterns.length }}</q-badge>
    </q-tab>
    <q-tab name="stats" label="Statistics"></q-tab>
  </q-tabs>

  <!-- Filter bar -->
  <div v-if="activeTab !== 'stats' && activeTab !== 'excluded'" class="row q-pa-sm q-gutter-sm items-center bg-dark sticky-filter">
    <q-select
      v-if="activeTab === 'queries'"
      v-model="filterDatasource"
      :options="datasourceOptions"
      dense outlined clearable
      map-options emit-value
      label="Datasource"
      style="width: 180px"
    ></q-select>
    <q-select
      v-if="activeTab === 'queries'"
      v-model="filterQueryType"
      :options="queryTypeOptions"
      dense outlined clearable
      map-options emit-value
      label="Type"
      style="width: 130px"
    ></q-select>
    <q-input
      v-model="filterSearch"
      dense outlined clearable
      placeholder="Search SQL, caller, error..."
      style="min-width: 250px"
      debounce="300"
    >
      <template v-slot:prepend><q-icon name="search"></q-icon></template>
    </q-input>
    <q-space></q-space>
    <span class="text-caption text-grey-5">{{ currentResultCount }} {{ currentResultCount === 1 ? 'result' : 'results' }}</span>
  </div>

  <!-- Tab Panels -->
  <q-tab-panels v-model="activeTab" animated>

    <!-- All Queries Panel -->
    <q-tab-panel name="queries" class="q-pa-none">
      <q-table
        dense flat
        :columns="columns"
        :rows="queries"
        row-key="id"
        :rows-per-page-options="[25, 50, 100]"
        v-model:pagination="pagination"
        @request="onRequest"
        :loading="loading"
        :row-class="rowClass"
      >
        <template v-slot:body="props">
          <q-tr :props="props" :class="[rowClass(props.row), expandedRowId === props.row.id ? 'row-expanded' : '']" @click="toggleRow(props.row.id)" style="cursor:pointer">
            <q-td key="id" :props="props">{{ props.row.id }}</q-td>
            <q-td key="timestamp" :props="props" style="white-space:nowrap">{{ formatTime(props.row.timestamp) }}</q-td>
            <q-td key="sql" :props="props" class="sql-cell">
              <span class="sql-text-truncated">{{ interpolateSQL(props.row) }}</span>
            </q-td>
            <q-td key="datasource" :props="props">{{ props.row.datasource }}</q-td>
            <q-td key="executionTime" :props="props">
              <q-badge :color="durationColor(props.row.executionTime)" :label="props.row.executionTime + 'ms'"></q-badge>
            </q-td>
            <q-td key="recordCount" :props="props">{{ props.row.recordCount }}</q-td>
            <q-td key="caller" :props="props" style="white-space:nowrap">{{ props.row.caller }}</q-td>
            <q-td key="source" :props="props">
              <q-badge :color="props.row.source === 'qb' ? 'purple' : 'blue-grey'" :label="props.row.source || 'listener'" outline dense></q-badge>
            </q-td>
          </q-tr>
          <q-tr v-if="expandedRowId === props.row.id" :props="props">
            <q-td colspan="100%">
              <div class="expanded-detail">
                <div class="row items-center q-mb-xs">
                  <div class="text-subtitle2">Full SQL:</div>
                  <q-space></q-space>
                  <q-btn flat dense size="sm" icon="content_copy" label="Copy" :disable="isTruncated(props.row)" @click.stop="copySQL(props.row)">
                    <q-tooltip>{{ isTruncated(props.row) ? 'SQL was truncated — copy disabled' : 'Copy interpolated SQL' }}</q-tooltip>
                  </q-btn>
                  <q-btn flat dense size="sm" icon="volume_off" label="Mute" color="orange" @click.stop="promptMute(props.row)">
                    <q-tooltip>Exclude queries matching this pattern</q-tooltip>
                  </q-btn>
                </div>
                <div class="sql-text q-mb-sm">{{ interpolateSQL(props.row) }}</div>
                <div v-if="hasNamedBindings(props.row)" class="q-mb-sm">
                  <div class="text-subtitle2 q-mb-xs">Bindings:</div>
                  <q-chip v-for="(b, key) in props.row.namedBindings" :key="key" dense size="sm" color="blue-grey-8" text-color="white">
                    :{{ key }} = {{ truncate(b.value, 24) }} <span v-if="b.cfsqltype" class="text-blue-grey-3 q-ml-xs">({{ b.cfsqltype }})</span>
                    <q-tooltip v-if="String(b.value).length > 24">{{ b.value }}</q-tooltip>
                  </q-chip>
                </div>
                <div v-else-if="nonEmptyBindings(props.row.bindings).length" class="q-mb-sm">
                  <div class="text-subtitle2 q-mb-xs">Bindings:</div>
                  <q-chip v-for="(b, i) in nonEmptyBindings(props.row.bindings)" :key="i" dense size="sm" color="blue-grey-8" text-color="white">
                    {{ truncate(b.value, 24) }} <span v-if="b.cfsqltype" class="text-blue-grey-3 q-ml-xs">({{ b.cfsqltype }})</span>
                    <q-tooltip v-if="String(b.value).length > 24">{{ b.value }}</q-tooltip>
                  </q-chip>
                </div>
                <div v-if="props.row.error" class="q-mb-sm" style="border-left: 3px solid ##c10015; padding-left: 10px;">
                  <div class="text-negative text-bold">{{ props.row.errorDetail || props.row.errorMessage }}</div>
                  <div v-if="props.row.errorDetail && props.row.errorMessage" class="text-caption text-grey-6 q-mt-xs">{{ props.row.errorMessage }}</div>
                  <div v-if="props.row.stackTrace" class="sql-text text-caption q-mt-sm" style="max-height:200px;overflow:auto;color:##999">{{ props.row.stackTrace }}</div>
                </div>
              </div>
            </q-td>
          </q-tr>
        </template>
      </q-table>
    </q-tab-panel>

    <!-- Errors Panel -->
    <q-tab-panel name="errors" class="q-pa-none">
      <q-table
        dense flat
        :columns="columns"
        :rows="filteredErrors"
        row-key="id"
        :rows-per-page-options="[25, 50, 100]"
        :row-class="() => 'row-error'"
      >
        <template v-slot:body="props">
          <q-tr :props="props" :class="['row-error', expandedRowId === props.row.id ? 'row-expanded' : '']" @click="toggleRow(props.row.id)" style="cursor:pointer">
            <q-td key="id" :props="props">{{ props.row.id }}</q-td>
            <q-td key="timestamp" :props="props" style="white-space:nowrap">{{ formatTime(props.row.timestamp) }}</q-td>
            <q-td key="sql" :props="props" class="sql-cell"><span class="sql-text-truncated">{{ interpolateSQL(props.row) }}</span></q-td>
            <q-td key="datasource" :props="props">{{ props.row.datasource }}</q-td>
            <q-td key="executionTime" :props="props">{{ props.row.executionTime }}ms</q-td>
            <q-td key="recordCount" :props="props">-</q-td>
            <q-td key="caller" :props="props" style="white-space:nowrap">{{ props.row.caller }}</q-td>
            <q-td key="source" :props="props">
              <q-badge :color="props.row.source === 'qb' ? 'purple' : 'blue-grey'" :label="props.row.source || 'listener'" outline dense></q-badge>
            </q-td>
          </q-tr>
          <q-tr v-if="expandedRowId === props.row.id" :props="props">
            <q-td colspan="100%">
              <div class="expanded-detail">
                <div class="row items-center q-mb-xs">
                  <div class="text-subtitle2">Full SQL:</div>
                  <q-space></q-space>
                  <q-btn flat dense size="sm" icon="content_copy" label="Copy" :disable="isTruncated(props.row)" @click.stop="copySQL(props.row)">
                    <q-tooltip>{{ isTruncated(props.row) ? 'SQL was truncated — copy disabled' : 'Copy interpolated SQL' }}</q-tooltip>
                  </q-btn>
                  <q-btn flat dense size="sm" icon="volume_off" label="Mute" color="orange" @click.stop="promptMute(props.row)">
                    <q-tooltip>Exclude queries matching this pattern</q-tooltip>
                  </q-btn>
                </div>
                <div class="sql-text q-mb-sm">{{ interpolateSQL(props.row) }}</div>
                <div style="border-left: 3px solid ##c10015; padding-left: 10px;">
                  <div class="text-negative text-bold">{{ props.row.errorDetail || props.row.errorMessage }}</div>
                  <div v-if="props.row.errorDetail && props.row.errorMessage" class="text-caption text-grey-6 q-mt-xs">{{ props.row.errorMessage }}</div>
                  <div v-if="props.row.stackTrace" class="sql-text text-caption q-mt-sm" style="max-height:300px;overflow:auto;color:##999">{{ props.row.stackTrace }}</div>
                </div>
              </div>
            </q-td>
          </q-tr>
        </template>
      </q-table>
    </q-tab-panel>

    <!-- Slow Queries Panel -->
    <q-tab-panel name="slow" class="q-pa-none">
      <q-table
        dense flat
        :columns="columns"
        :rows="filteredSlow"
        row-key="id"
        :rows-per-page-options="[25, 50, 100]"
        :row-class="() => 'row-slow'"
      >
        <template v-slot:body="props">
          <q-tr :props="props" :class="['row-slow', expandedRowId === props.row.id ? 'row-expanded' : '']" @click="toggleRow(props.row.id)" style="cursor:pointer">
            <q-td key="id" :props="props">{{ props.row.id }}</q-td>
            <q-td key="timestamp" :props="props" style="white-space:nowrap">{{ formatTime(props.row.timestamp) }}</q-td>
            <q-td key="sql" :props="props" class="sql-cell"><span class="sql-text-truncated">{{ interpolateSQL(props.row) }}</span></q-td>
            <q-td key="datasource" :props="props">{{ props.row.datasource }}</q-td>
            <q-td key="executionTime" :props="props">
              <q-badge color="orange" :label="props.row.executionTime + 'ms'"></q-badge>
            </q-td>
            <q-td key="recordCount" :props="props">{{ props.row.recordCount }}</q-td>
            <q-td key="caller" :props="props" style="white-space:nowrap">{{ props.row.caller }}</q-td>
            <q-td key="source" :props="props">
              <q-badge :color="props.row.source === 'qb' ? 'purple' : 'blue-grey'" :label="props.row.source || 'listener'" outline dense></q-badge>
            </q-td>
          </q-tr>
          <q-tr v-if="expandedRowId === props.row.id" :props="props">
            <q-td colspan="100%">
              <div class="expanded-detail">
                <div class="row items-center q-mb-xs">
                  <div class="text-subtitle2">Full SQL:</div>
                  <q-space></q-space>
                  <q-btn flat dense size="sm" icon="content_copy" label="Copy" :disable="isTruncated(props.row)" @click.stop="copySQL(props.row)">
                    <q-tooltip>{{ isTruncated(props.row) ? 'SQL was truncated — copy disabled' : 'Copy interpolated SQL' }}</q-tooltip>
                  </q-btn>
                  <q-btn flat dense size="sm" icon="volume_off" label="Mute" color="orange" @click.stop="promptMute(props.row)">
                    <q-tooltip>Exclude queries matching this pattern</q-tooltip>
                  </q-btn>
                </div>
                <div class="sql-text">{{ interpolateSQL(props.row) }}</div>
              </div>
            </q-td>
          </q-tr>
        </template>
      </q-table>
    </q-tab-panel>

    <!-- Excluded Patterns Panel -->
    <q-tab-panel name="excluded" class="q-pa-md">
      <div class="row q-gutter-sm q-mb-md items-end">
        <q-input
          v-model="newPattern"
          outlined dense
          label="SQL pattern to exclude"
          hint="Queries containing this text (case-insensitive) will be silently dropped"
          style="flex: 1"
          @keyup.enter="addPatternManual"
        ></q-input>
        <q-btn color="primary" label="Add" icon="add" dense @click="addPatternManual" :disable="!newPattern"></q-btn>
      </div>
      <q-list bordered separator v-if="excludePatterns.length > 0">
        <q-item v-for="(p, i) in excludePatterns" :key="i">
          <q-item-section>
            <q-item-label class="sql-text">{{ p }}</q-item-label>
          </q-item-section>
          <q-item-section side>
            <q-btn flat dense round icon="delete" color="negative" @click="removePattern(i + 1)">
              <q-tooltip>Remove pattern</q-tooltip>
            </q-btn>
          </q-item-section>
        </q-item>
      </q-list>
      <div v-else class="text-grey-5 text-center q-pa-lg">
        No exclusion patterns defined. Click "Mute" on any query row to add one, or type a pattern above.
      </div>
    </q-tab-panel>

    <!-- Statistics Panel -->
    <q-tab-panel name="stats" class="q-pa-md">
      <div class="row q-gutter-md q-mb-lg">
        <q-card class="stat-card" flat bordered>
          <q-card-section class="text-center">
            <div class="text-h4">{{ stats.totalQueries }}</div>
            <div class="text-caption text-grey">Total Queries</div>
          </q-card-section>
        </q-card>
        <q-card class="stat-card" flat bordered>
          <q-card-section class="text-center">
            <div class="text-h4 text-negative">{{ stats.totalErrors }}</div>
            <div class="text-caption text-grey">Errors</div>
          </q-card-section>
        </q-card>
        <q-card class="stat-card" flat bordered>
          <q-card-section class="text-center">
            <div class="text-h4">{{ stats.avgExecutionTime }}ms</div>
            <div class="text-caption text-grey">Avg Duration</div>
          </q-card-section>
        </q-card>
        <q-card class="stat-card" flat bordered>
          <q-card-section class="text-center">
            <div class="text-h4 text-warning">{{ stats.maxExecutionTime }}ms</div>
            <div class="text-caption text-grey">Max Duration</div>
          </q-card-section>
        </q-card>
        <q-card class="stat-card" flat bordered>
          <q-card-section class="text-center">
            <div class="text-h4 text-orange">{{ stats.slowQueryCount }}</div>
            <div class="text-caption text-grey">Slow Queries</div>
          </q-card-section>
        </q-card>
      </div>

      <div class="row q-gutter-md">
        <q-card flat bordered class="col">
          <q-card-section>
            <div class="text-subtitle1 q-mb-sm">Queries by Type</div>
            <canvas id="chartByType" height="200"></canvas>
          </q-card-section>
        </q-card>
        <q-card flat bordered class="col">
          <q-card-section>
            <div class="text-subtitle1 q-mb-sm">Queries by Datasource</div>
            <canvas id="chartByDatasource" height="200"></canvas>
          </q-card-section>
        </q-card>
      </div>

      <div class="row q-gutter-md q-mt-md">
        <q-card flat bordered class="col">
          <q-card-section>
            <div class="text-subtitle1 q-mb-sm">Avg Duration by Datasource (ms)</div>
            <canvas id="chartAvgDuration" height="200"></canvas>
          </q-card-section>
        </q-card>
        <q-card flat bordered class="col">
          <q-card-section>
            <div class="text-subtitle1 q-mb-sm">Avg Row Count by Datasource</div>
            <canvas id="chartAvgRowCount" height="200"></canvas>
          </q-card-section>
        </q-card>
      </div>
    </q-tab-panel>

  </q-tab-panels>

  <!-- Mute Dialog -->
  <q-dialog v-model="showMuteDialog">
    <q-card style="min-width: 500px">
      <q-card-section class="row items-center q-pb-none">
        <div class="text-h6">Mute Query Pattern</div>
        <q-space></q-space>
        <q-btn icon="close" flat round dense v-close-popup></q-btn>
      </q-card-section>
      <q-card-section>
        <div class="text-caption text-grey q-mb-sm">
          Edit the text below to the distinctive part of the SQL you want to exclude.
          All queries containing this text (case-insensitive) will be silently dropped.
        </div>
        <q-input
          v-model="mutePattern"
          outlined dense autofocus
          type="textarea"
          rows="3"
          class="sql-text"
        ></q-input>
      </q-card-section>
      <q-card-actions align="right">
        <q-btn flat label="Cancel" v-close-popup></q-btn>
        <q-btn color="orange" text-color="white" label="Mute" icon="volume_off" @click="confirmMute" :disable="!mutePattern"></q-btn>
      </q-card-actions>
    </q-card>
  </q-dialog>

  <!-- Settings Dialog -->
  <q-dialog v-model="showSettings">
    <q-card style="min-width: 400px">
      <q-card-section class="row items-center q-pb-none">
        <div class="text-h6">Settings</div>
        <q-space></q-space>
        <q-btn icon="close" flat round dense v-close-popup></q-btn>
      </q-card-section>
      <q-card-section class="q-gutter-md">
        <q-input
          v-model.number="settingsForm.historySize"
          type="number"
          label="Buffer Size"
          hint="Max queries kept in memory (FIFO ring buffer)"
          outlined dense
        ></q-input>
        <q-input
          v-model.number="settingsForm.slowQueryThreshold"
          type="number"
          step="100"
          label="Slow Query Threshold (ms)"
          hint="Queries slower than this are flagged"
          outlined dense
        ></q-input>
        <q-input
          v-model.number="settingsForm.maxSQLLength"
          type="number"
          label="Max SQL Length (chars)"
          hint="SQL text truncated beyond this length"
          outlined dense
        ></q-input>
        <q-input
          v-model.number="settingsForm.maxBindingValueLength"
          type="number"
          label="Max Binding Value Length (chars)"
          hint="Individual binding values truncated beyond this length"
          outlined dense
        ></q-input>
        <q-select
          v-model="settingsForm.excludeDatasources"
          :options="datasourceOptions"
          map-options emit-value multiple use-chips
          label="Excluded Datasources"
          hint="Queries from these datasources are silently dropped"
          outlined dense
        ></q-select>
        <q-toggle
          v-model="settingsForm.injectSourceComments"
          label="Inject Source Comments"
          hint="Prepend /* caller:file:line */ to SQL"
        ></q-toggle>
      </q-card-section>
      <q-card-actions align="right">
        <q-btn flat label="Cancel" v-close-popup></q-btn>
        <q-btn color="primary" label="Save" @click="saveSettings"></q-btn>
      </q-card-actions>
    </q-card>
  </q-dialog>

</div>
</cfoutput>

<script>
  const API_BASE = '<cfoutput>#event.buildLink( "jdbcMonitor/api" )#</cfoutput>';
</script>
<cfoutput>
<script src="#event.getModuleRoot('jdbcMonitor')#/assets/js/app.js"></script>
</cfoutput>
