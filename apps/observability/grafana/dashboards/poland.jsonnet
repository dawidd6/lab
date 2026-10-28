// Poland: inflation and the NBP rate change monthly/weekly, so this dashboard refreshes once a day
local ds = { type: 'yesoreyeram-infinity-datasource', uid: 'markets' };

// Infinity only uses JSONata when gjson can't parse the selector, hence the leading "(";
// returning an array makes Infinity apply the column labels and types
local stat(title, description, x, url, params, headers, root, columns, decimals) = {
  type: 'stat',
  title: title,
  description: description,
  datasource: ds,
  gridPos: { h: 4, w: 6, x: x, y: 0 },
  targets: [{
    refId: 'A',
    datasource: ds,
    type: 'json',
    source: 'url',
    parser: 'backend',
    format: 'table',
    url: url,
    url_options: {
      method: 'GET',
      params: [{ key: k, value: params[k] } for k in std.objectFields(params)],
      headers: [{ key: k, value: headers[k] } for k in std.objectFields(headers)],
    },
    root_selector: root,
    columns: columns,
  }],
  fieldConfig: { defaults: { decimals: decimals, unit: 'percent', color: { mode: 'fixed', fixedColor: 'text' } }, overrides: [] },
  options: {
    reduceOptions: { calcs: ['lastNotNull'], fields: '/.*/', values: false },
    graphMode: 'none',
    colorMode: 'none',
    textMode: 'value_and_name',
    justifyMode: 'center',
    wideLayout: true,
  },
};

local panels = [
  stat(
    'Inflation y/y',
    'Eurostat HICP, annual rate of change, Poland (close to, not identical with, GUS CPI)',
    0,
    'https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/prc_hicp_minr',
    { geo: 'PL', unit: 'RCH_A', coicop18: 'TOTAL', lastTimePeriod: '1', format: 'JSON' },
    {},
    '([{"period": $keys(dimension.time.category.index)[0], "value": $lookup(value, "0")}])',
    [{ selector: 'period', text: 'Month', type: 'string' }, { selector: 'value', text: 'HICP', type: 'number' }],
    1,
  ),
  stat(
    'NBP reference rate',
    'Central bank policy rate for Poland, as published by BIS (weekly)',
    6,
    'https://stats.bis.org/api/v1/data/WS_CBPOL/D.PL/all',
    { lastNObservations: '1' },
    { Accept: 'application/vnd.sdmx.data+json;version=1.0.0' },
    '([{"date": data.structure.dimensions.observation[0].values[0].id, "rate": $number($lookup($lookup(data.dataSets[0].series, "0:0").observations, "0")[0])}])',
    [{ selector: 'date', text: 'As of', type: 'string' }, { selector: 'rate', text: 'Rate', type: 'number' }],
    2,
  ),
];

local dashboard = {
  uid: 'poland',
  title: 'Poland',
  tags: ['markets'],
  editable: false,
  refresh: '1d',
  schemaVersion: 41,
  time: { from: 'now-24h', to: 'now' },
  timepicker: { hidden: true, refresh_intervals: ['1d'] },
  templating: { list: [] },
  panels: [panels[i] { id: i + 1 } for i in std.range(0, std.length(panels) - 1)],
};

{
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: { name: 'grafana-dashboard-poland', labels: { grafana_dashboard: '1' } },
  data: { 'poland.json': std.manifestJsonEx(dashboard, '  ') },
}
