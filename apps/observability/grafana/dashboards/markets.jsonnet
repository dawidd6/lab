// Markets: per group a row of price tiles (value + today's change) with a "today" chart under each tile.
// Symbols are Yahoo Finance tickers as "Name : SYMBOL"; tiles and charts repeat over them.
local groups = [
  { title: 'Crypto', var: 'crypto', decimals: 2, symbols: [
    'Bitcoin : BTC-USD',
    'Ethereum : ETH-USD',
    'Solana : SOL-USD',
  ] },
  { title: 'FX', var: 'fx', decimals: 4, symbols: [
    'EUR/PLN : EURPLN=X',
    'USD/PLN : USDPLN=X',
    'GBP/PLN : GBPPLN=X',
  ] },
  { title: 'Commodities', var: 'commodities', decimals: 2, symbols: [
    'Gold : GC=F',
    'Silver : SI=F',
    'Crude oil (WTI) : CL=F',
    'Brent oil : BZ=F',
  ] },
  { title: 'ETFs', var: 'etfs', decimals: 2, symbols: [
    'Avantis Global Small Cap Value : AVWS.DE',
    'iShares MSCI ACWI : ISAC.L',
    'iShares Physical Silver : ISLN.L',
    'VanEck Space Innovators : JEDI.L',
  ] },
];

local ds = { type: 'yesoreyeram-infinity-datasource', uid: 'markets' };

// JSONata over Yahoo's chart API; Infinity only uses JSONata when gjson can't parse the selector, hence the leading "("
local series(extra) = '$map($r.timestamp, function($t, $i) {{"time": $t, "price": $r.indicators.quote[0].close[$i]' + extra + '}})';
// previous close first, so the tile's "percent change" (first -> last) is today's change
local tileRoot = '($r := chart.result[0]; $append([{"time": $r.timestamp[0] - 300, "price": $r.meta.chartPreviousClose}], ' + series('') + '))';
local chartRoot = '($r := chart.result[0]; ' + series(', "previous close": $r.meta.chartPreviousClose') + ')';

local column(name, type) = { selector: name, text: name, type: type };
local yahoo(var, root, columns) = [{
  refId: 'A',
  datasource: ds,
  type: 'json',
  source: 'url',
  parser: 'backend',
  format: 'timeseries',
  url: 'https://query1.finance.yahoo.com/v8/finance/chart/${' + var + '}',
  url_options: { method: 'GET', params: [{ key: 'range', value: '1d' }, { key: 'interval', value: '5m' }] },
  root_selector: root,
  columns: [column('time', 'timestamp_epoch_s'), column('price', 'number')] + columns,
}];

local repeated(g, y, h) = {
  datasource: ds,
  repeat: g.var,
  repeatDirection: 'h',
  maxPerRow: 4,
  gridPos: { h: h, w: 6, x: 0, y: y },
};

local tile(g, y) = repeated(g, y, 3) {
  type: 'stat',
  title: '${' + g.var + ':text}',
  links: [{ title: 'Yahoo Finance', url: 'https://finance.yahoo.com/quote/${' + g.var + ':raw}/', targetBlank: true }],
  targets: yahoo(g.var, tileRoot, []),
  fieldConfig: { defaults: { decimals: g.decimals, color: { mode: 'fixed', fixedColor: 'text' } }, overrides: [] },
  options: {
    reduceOptions: { calcs: ['lastNotNull'], fields: '', values: false },
    graphMode: 'none',
    colorMode: 'none',
    textMode: 'value',
    justifyMode: 'center',
    showPercentChange: true,
    percentChangeColorMode: 'standard',
    wideLayout: true,
  },
};

local chart(g, y) = repeated(g, y, 6) {
  type: 'timeseries',
  title: '',
  timeFrom: 'now/d',  // today: every chart shares the same time axis
  hideTimeOverride: false,
  targets: yahoo(g.var, chartRoot, [column('previous close', 'number')]),
  fieldConfig: {
    defaults: {
      decimals: g.decimals,
      color: { mode: 'fixed', fixedColor: 'blue' },
      custom: {
        drawStyle: 'line',
        lineWidth: 1,
        fillOpacity: 15,
        gradientMode: 'opacity',
        showPoints: 'never',
        insertNulls: 7200000,  // break the line over market closures
        spanNulls: false,
        axisPlacement: 'right',
      },
    },
    overrides: [{
      matcher: { id: 'byName', options: 'previous close' },
      properties: [
        { id: 'color', value: { mode: 'fixed', fixedColor: 'text' } },
        { id: 'custom.lineStyle', value: { fill: 'dash', dash: [6, 6] } },
        { id: 'custom.fillOpacity', value: 0 },
        { id: 'custom.insertNulls', value: false },
      ],
    }],
  },
  options: {
    legend: { showLegend: false, displayMode: 'hidden', placement: 'bottom', calcs: [] },
    tooltip: { mode: 'multi', sort: 'none' },
  },
};

// each group takes 10 grid rows: row header (1) + tiles (3) + charts (6)
local panels = std.flattenArrays([
  local y = 10 * i;
  local g = groups[i];
  [
    { type: 'row', title: g.title, collapsed: false, gridPos: { h: 1, w: 24, x: 0, y: y }, panels: [] },
    tile(g, y + 1),
    chart(g, y + 4),
  ]
  for i in std.range(0, std.length(groups) - 1)
]);

local dashboard = {
  uid: 'markets',
  title: 'Markets',
  tags: ['markets'],
  editable: false,
  refresh: '1m',
  schemaVersion: 41,
  time: { from: 'now-24h', to: 'now' },
  timepicker: { hidden: true },
  templating: { list: [
    {
      name: g.var,
      label: g.title,
      type: 'custom',
      hide: 2,
      query: std.join(', ', g.symbols),
      multi: true,
      includeAll: true,
      current: { selected: true, text: ['All'], value: ['$__all'] },
    }
    for g in groups
  ] },
  panels: [panels[i] { id: i + 1 } for i in std.range(0, std.length(panels) - 1)],
};

{
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: { name: 'grafana-dashboard-markets', labels: { grafana_dashboard: '1' } },
  data: { 'markets.json': std.manifestJsonEx(dashboard, '  ') },
}
