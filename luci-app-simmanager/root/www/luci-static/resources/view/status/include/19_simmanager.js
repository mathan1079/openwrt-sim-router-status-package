'use strict';
'require baseclass';
'require request';

var modeNames = {
	'7': '4G', '8': '5G', '9': '5G', '10': '5G NSA', '11': '5G SA',
	'12': '5G SA', '13': '5G NSA', '14': '5G', '15': '5G', '16': '5G'
};

function present(value) {
	return value !== null && value !== undefined && value !== '';
}

function text(value, fallback) {
	return present(value) ? String(value) : (fallback || 'N/A');
}

function metric(value, unit) {
	return present(value) ? String(value) + (unit || '') : 'N/A';
}

function networkName(value) {
	return modeNames[String(value)] || text(value);
}

function bands(value, prefix) {
	if (!present(value)) return 'N/A';
	return String(value).split(':').map(function(band) {
		return prefix + band;
	}).join(', ');
}

function row(label, value) {
	return E('div', { 'class': 'sm-overview-row' }, [
		E('span', { 'class': 'sm-overview-label' }, [ label ]),
		E('span', { 'class': 'sm-overview-value' }, [ text(value) ])
	]);
}

function card(title, rows, extraClass, stateBadge) {
	var head = E('div', { 'class': 'sm-overview-card-head' }, [
		E('h4', {}, [ title ])
	]);
	if (stateBadge) head.appendChild(stateBadge);
	return E('section', { 'class': 'sm-overview-card ' + (extraClass || '') }, [ head ].concat(rows));
}

function makeBadge(label, active) {
	return E('span', { 'class': 'sm-overview-badge ' + (active ? 'active' : 'inactive') }, [ label ]);
}

function simCard(sim, key) {
	sim = sim || {};
	var active = sim.active === true;
	var waiting = sim.transitioning ? _('Refreshing active SIM data…') : _('Available when active');
	var state = active
		? (sim.transitioning ? _('Active — refreshing') : _('Active — live data'))
		: (sim.last_known ? _('Inactive — last known') : _('Inactive — profile data'));
	var configuredApn = sim.apn_auto === '1' ? _('Automatic') : text(sim.profile_apn);
	var preferredBands = sim.band_auto === '1' ? _('Automatic') : text(sim.bands);
	var observed = present(sim.last_seen)
		? new Date(Number(sim.last_seen) * 1000).toLocaleString()
		: null;

	var rows = [
		row(_('Profile'), sim.profile_name),
		row(_('Phone number'), sim.phone_number),
		row(_('Operator'), sim.operator || waiting),
		row('MCC / MNC', sim.mccmnc || waiting),
		row('ICCID', sim.iccid || waiting),
		row(_('SIM status'), sim.sim_status || waiting),
		row(_('Current APN'), sim.current_apn || waiting),
		row(_('Configured APN'), configuredApn),
		row(_('PDP type'), sim.pdp_type),
		row(_('Network type'), networkName(sim.network_type)),
		row(_('Preferred network'), sim.network_mode),
		row(_('Preferred bands'), preferredBands),
		row(active ? _('Live signal') : _('Last known signal'), present(sim.signal_percent) ? sim.signal_percent + '%' : waiting),
		row('RSRP', present(sim.rsrp) ? sim.rsrp + ' dBm' : waiting),
		row(active ? _('Current bands') : _('Last known bands'), sim.current_band || waiting)
	];
	if (!active && observed) rows.push(row(_('Last observed'), observed));

	return card(sim.title || key, rows, 'sm-overview-sim ' + (active ? 'active' : ''), makeBadge(state, active));
}

return baseclass.extend({
	title: _('SIM Manager'),

	load: function() {
		return request.get(L.url('admin/network/simmanager/status')).then(function(response) {
			return response.json();
		});
	},

	render: function(data) {
		data = data || {};
		if (!data.available) {
			return E('div', { 'class': 'alert-message warning' }, [
				_('Cellular status is not available yet.')
			]);
		}

		var refreshing = data.status_stable === false;
		var summary = E('section', { 'class': 'sm-overview-summary' }, [
			E('div', {}, [ E('span', {}, [ _('Active SIM') ]), E('strong', {}, [ text(data.active_sim_title || data.active_sim) ]) ]),
			E('div', {}, [ E('span', {}, [ _('Operator') ]), E('strong', {}, [ refreshing ? _('Refreshing…') : text(data.operator) ]) ]),
			E('div', {}, [ E('span', {}, [ _('Network') ]), E('strong', {}, [ refreshing ? _('Refreshing…') : networkName(data.network_mode) ]) ]),
			E('div', {}, [ E('span', {}, [ _('Signal') ]), E('strong', {}, [ refreshing ? _('Refreshing…') : metric(data.signal_percent, '%') ]) ]),
			E('div', {}, [ E('span', {}, [ _('Current bands') ]), E('strong', {}, [ refreshing ? _('Refreshing…') : text(data.current_band) ]) ]),
			E('div', {}, [ E('span', {}, [ _('APN') ]), E('strong', {}, [ refreshing ? _('Refreshing…') : text(data.apn) ]) ])
		]);

		var sims = data.sims || {};
		var simGrid = E('div', { 'class': 'sm-overview-grid two' }, [
			simCard(sims.sim1, 'SIM 1'),
			simCard(sims.sim2, 'SIM 2')
		]);

		var detailsGrid = E('div', { 'class': 'sm-overview-grid three' }, [
			card(_('Measured signal'), [
				row(_('Calculated signal'), metric(data.signal_percent, '%')),
				row(_('Quality'), data.signal_quality),
				row('RSRP', metric(data.rsrp, ' dBm')),
				row('RSRQ', metric(data.rsrq, ' dB')),
				row('RSSI', metric(data.rssi, ' dBm')),
				row('SINR', metric(data.sinr, ' dB')),
				row('NR RSRP', metric(data.nr_rsrp, ' dBm')),
				row('NR RSRQ', metric(data.nr_rsrq, ' dB')),
				row('NR SINR', metric(data.nr_sinr, ' dB'))
			]),
			card(_('Tower and radio'), [
				row('MCC / MNC', data.mccmnc),
				row(_('Registration'), data.registration),
				row(_('Cell ID'), data.cell_id),
				row('PCI', data.pci),
				row('EARFCN', data.frequency),
				row(_('LTE band'), present(data.lte_band) ? 'B' + data.lte_band : null),
				row('NR PCI', data.nr_pci),
				row('NR-ARFCN', data.nr_frequency),
				row(_('NR band'), present(data.nr_band) ? 'n' + data.nr_band : null)
			]),
			card(_('Modem information'), [
				row(_('Model'), data.device_model),
				row('IMEI', data.imei),
				row('ICCID', data.iccid),
				row(_('SIM status'), data.sim_status),
				row(_('Status port'), data.query_port),
				row(_('Scan mode'), data.scan_mode),
				row(_('Status updated'), present(data.updated_at) ? new Date(Number(data.updated_at) * 1000).toLocaleString() : null)
			])
		]);

		var supported = card(_('Supported bands'), [
			row('3G / WCDMA', bands(data.supported_wcdma_bands, 'B')),
			row('4G / LTE', bands(data.supported_lte_bands, 'B')),
			row('5G NSA', bands(data.supported_nsa_5g_bands, 'n')),
			row('5G SA', bands(data.supported_sa_5g_bands, 'n'))
		], 'sm-overview-supported');

		var style = E('style', {}, [
			'.sm-overview-wrap{display:grid;gap:16px}',
			'.sm-overview-summary{display:grid;grid-template-columns:repeat(6,minmax(120px,1fr));gap:1px;background:#d8dde5;border:1px solid #d8dde5;border-radius:6px;overflow:hidden}',
			'.sm-overview-summary>div{background:#fff;padding:12px 14px;min-width:0}',
			'.sm-overview-summary span{display:block;color:#65718a;font-size:.85em;margin-bottom:4px}',
			'.sm-overview-summary strong{display:block;overflow-wrap:anywhere}',
			'.sm-overview-grid{display:grid;gap:16px}',
			'.sm-overview-grid.two{grid-template-columns:repeat(2,minmax(0,1fr))}',
			'.sm-overview-grid.three{grid-template-columns:repeat(3,minmax(0,1fr))}',
			'.sm-overview-card{border:1px solid #d4d9e1;border-radius:6px;background:#fff;padding:0 14px 10px;min-width:0}',
			'.sm-overview-card.active{border:2px solid #24a45a;padding:0 13px 9px}',
			'.sm-overview-card-head{display:flex;align-items:center;justify-content:space-between;gap:10px;border-bottom:1px solid #e3e6eb;padding:12px 0 9px;margin-bottom:2px}',
			'.sm-overview-card-head h4{font-size:1.15em;margin:0}',
			'.sm-overview-badge{border-radius:999px;padding:4px 9px;font-size:.8em;white-space:nowrap;background:#e4e7ec;color:#4d5a70}',
			'.sm-overview-badge.active{background:#dff5e7;color:#087b39}',
			'.sm-overview-row{display:grid;grid-template-columns:minmax(115px,42%) minmax(0,58%);gap:10px;border-bottom:1px solid #edf0f3;padding:7px 0}',
			'.sm-overview-row:last-child{border-bottom:0}',
			'.sm-overview-label{color:#65718a}',
			'.sm-overview-value{text-align:right;overflow-wrap:anywhere}',
			'.sm-overview-supported .sm-overview-row{grid-template-columns:minmax(130px,18%) minmax(0,82%)}',
			'@media(max-width:1200px){.sm-overview-summary{grid-template-columns:repeat(3,minmax(120px,1fr))}.sm-overview-grid.three{grid-template-columns:1fr 1fr}.sm-overview-grid.three>.sm-overview-card:last-child{grid-column:1/-1}}',
			'@media(max-width:800px){.sm-overview-summary{grid-template-columns:repeat(2,minmax(0,1fr))}.sm-overview-grid.two,.sm-overview-grid.three{grid-template-columns:1fr}.sm-overview-grid.three>.sm-overview-card:last-child{grid-column:auto}}',
			'@media(max-width:480px){.sm-overview-summary{grid-template-columns:1fr}.sm-overview-row,.sm-overview-supported .sm-overview-row{grid-template-columns:1fr}.sm-overview-value{text-align:left}}'
		].join(''));

		return E('div', { 'class': 'sm-overview-wrap' }, [ style, summary, simGrid, detailsGrid, supported ]);
	}
});
