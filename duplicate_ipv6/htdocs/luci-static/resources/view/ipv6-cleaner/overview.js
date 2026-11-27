'use strict';
'require view';
'require form';
'require rpc';
'require poll';
'require ui';

var getStatus = rpc.declare({ object: 'ipv6-cleaner', method: 'status', expect: {} });
var runScan = rpc.declare({ object: 'ipv6-cleaner', method: 'run', expect: {} });
var inspect = rpc.declare({ object: 'ipv6-cleaner', method: 'inspect', expect: {} });
var removeStale = rpc.declare({ object: 'ipv6-cleaner', method: 'restart_stale', params: ['device', 'address', 'confirmed'], expect: {} });
function time(value) {
 return value ? new Date(value * 1000).toLocaleString() : _('Never / not scheduled');
}
return view.extend({
 render: function() {
  var m = new form.Map('ipv6_cleaner', _('IPv6 Cleaner'),
   _('Discovers all IPv6 devices, including multiple WANs. Only explicitly deprecated global unicast addresses in 2000::/3 qualify. ULA, link-local, tentative and failed addresses are excluded.'));
  var s = m.section(form.NamedSection, 'main', 'cleaner', _('Settings'));
  var o = s.option(form.Flag, 'enabled', _('Enable scheduled scans'));
  o.rmempty = false;
  o = s.option(form.ListValue, 'mode', _('Action'));
  o.value('monitor', _('Monitor only (safe default)'));
  o.value('remove', _('Remove deprecated addresses / restart stale IPv6 interface'));
  o.description = _('Removing an address can interrupt connections still using it. Manual scans use the saved action even when scheduling is disabled.');
  o = s.option(form.Flag, 'stale_detection', _('Check for stale ISP addresses'));
  o.rmempty = false;
  o.description = _('Runs bounded connectivity checks for public /64 addresses with infinite lifetimes on WAN devices with multiple such addresses. In Remove mode, repeated failures with a working alternative trigger automatic IPv6-only interface restart in about one minute. Monitor mode never removes them.');
  o = s.option(form.Value, 'interval', _('Scan frequency (seconds)'));
  o.value('120', _('2 minutes (suggested)'));
  o.value('300', _('5 minutes'));
  o.datatype = 'range(60,86400)';
  o.rmempty = false;
  o.description = _('Select a suggestion or enter a custom interval from 60 to 86400 seconds. Save & Apply restarts the schedule.');
  var status = E('div', {}, _('Loading status…'));
  var diagnosticStatus = E('div');
  var inspectButton = E('button', { 'class': 'cbi-button cbi-button-action',
   'click': ui.createHandlerFn(this, function() {
    return inspect().then(function() {
     ui.addNotification(null, E('p', {}, _('WAN checks started. Results will refresh automatically.')));
    }).catch(function(err) { ui.addNotification(null, E('p', {}, err.message)); });
   }) }, _('Check WAN addresses now'));
  function confirmRemoval(addr) {
   ui.showModal(_('Restart this IPv6 interface?'), [
    E('p', {}, addr.device + ': ' + addr.address),
    E('p', {}, _('This address failed both targets repeatedly for at least 30 seconds while another address on this WAN reached both. Only the owning logical DHCPv6 interface will restart. Its parent IPv4 interface and other WANs stay running. Both addresses will be rechecked first.')),
    E('div', { 'class': 'right' }, [
     E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, _('Cancel')), ' ',
     E('button', { 'class': 'cbi-button cbi-button-negative', 'click': ui.createHandlerFn(this, function() {
      return removeStale(addr.device, addr.address, true).then(function(result) {
       if (result.error) throw new Error(result.error);
       ui.hideModal();
       ui.addNotification(null, E('p', {}, _('The logical IPv6 interface was restarted. Its IPv4 parent was not restarted.')));
       return refresh();
      }).catch(function(err) { ui.addNotification(null, E('p', {}, err.message)); });
     }) }, _('Confirm IPv6 restart'))
    ])
   ]);
  }
  var button = E('button', { 'class': 'cbi-button cbi-button-action',
   'click': ui.createHandlerFn(this, function() {
    button.disabled = true;
    return runScan().then(function(result) {
     if (result.error) throw new Error(result.error);
     if (result.failed) ui.addNotification(null, E('p', {}, _('Some addresses could not be removed. Check the results and system log.')));
    }).then(refresh).catch(function(err) {
     ui.addNotification(null, E('p', {}, err.message));
    }).finally(function() { button.disabled = false; });
   }) }, _('Run saved action now'));
  function refresh() {
   return getStatus().then(function(data) {
    var rows = [
     [_('Status'), data.enabled ? (data.running ? _('Scheduled') : _('Enabled, service stopped')) : _('Scheduling disabled')],
     [_('Saved action'), data.mode === 'remove' ? _('Remove') : _('Monitor only')],
     [_('Last scan'), time(data.last_scan)],
     [_('Last cleared time'), time(data.last_clear)],
     [_('Last IPv6-only restart'), time(data.last_ipv6_restart) + (data.last_restart_interface ? ' (' + data.last_restart_interface + ')' : '')],
     [_('Next scan / clearing attempt'), time(data.next_scan)],
     [_('Last scan action'), data.scan_mode === 'remove' ? _('Remove') : _('Monitor only')],
     [_('Candidates / removed / failures'), [data.found || 0, data.removed || 0, data.failed || 0].join(' / ')]
    ];
    var table = E('table', { 'class': 'table' }, rows.map(function(row) {
     return E('tr', { 'class': 'tr' }, [E('td', { 'class': 'td' }, row[0]), E('td', { 'class': 'td' }, row[1])]);
    }));
    var addresses = E('table', { 'class': 'table' }, [E('tr', { 'class': 'tr' },
     [_('Device'), _('Deprecated public IPv6'), _('Result')].map(function(label) { return E('th', { 'class': 'th' }, label); }))]);
    (data.addresses || []).forEach(function(addr) {
     addresses.appendChild(E('tr', { 'class': 'tr' }, [addr.device, addr.address, addr.result].map(function(value) {
      return E('td', { 'class': 'td' }, value);
     })));
    });
    status.replaceChildren(table, addresses);
    var labels = { reachable: _('Responded'), checking: _('Repeated checks pending'), suspected_stale: _('Suspected stale ISP address'), unverified: _('Inconclusive / WAN unavailable') };
    var diagnosticTable = E('table', { 'class': 'table' }, [E('tr', { 'class': 'tr' },
     [_('Device'), _('Preferred address (infinite lifetime)'), _('Targets reached'), _('Finding'), _('Failed rounds'), _('First seen'), _('Action')].map(function(label) { return E('th', { 'class': 'th' }, label); }))]);
    (data.diagnostics || []).forEach(function(addr) {
     var row = E('tr', { 'class': 'tr' }, [addr.device, addr.address,
      addr.successes < 0 ? _('Unknown') : addr.successes + '/' + addr.targets,
      labels[addr.verdict] || addr.verdict, String(addr.failures), time(addr.first_seen)].map(function(value) { return E('td', { 'class': 'td' }, value); }));
     row.appendChild(E('td', { 'class': 'td' }, addr.verdict === 'suspected_stale' ?
      E('button', { 'class': 'cbi-button cbi-button-negative', 'click': function() { confirmRemoval(addr); } }, _('Restart IPv6 only')) : '—'));
     diagnosticTable.appendChild(row);
    });
    inspectButton.disabled = !!data.diagnostic_running;
    diagnosticStatus.replaceChildren(
     E('p', {}, (data.diagnostic_running ? _('Checking WAN addresses… ') : '') + _('Last WAN check: ') + time(data.last_diagnostic)),
     diagnosticTable,
     E('p', {}, _('Suspected stale requires at least 3 failed rounds over 30 seconds and an alternative on the same WAN that reaches both independent targets. Checks bind the exact source and device; older curl versions require matching routes. With curl 8.9+, Remove mode automatically rechecks and restarts only the owning DHCPv6 interface, targeting about one minute. Monitor mode only reports them. An outage affecting all addresses never qualifies. History resets after reboot.')));

   }).catch(function(err) {
    status.replaceChildren(E('p', {}, _('Unable to load status: ') + err.message));
   });
  }
  return m.render().then(function(node) {
   poll.add(refresh, 5);
   return E('div', {}, [E('h2', {}, _('Status')), status,
    E('div', { 'style': 'display: block !important; padding-top: 16px !important; padding-bottom: 8px !important;' }, [button]),
    E('p', {}, _('Times and results are kept in RAM and reset after reboot. The next time is a scan; removal happens only in removal mode when eligible addresses exist.')),
    E('h3', {}, _('Stale ISP address diagnostics')), diagnosticStatus,
    E('div', { 'style': 'padding-top: 16px; padding-bottom: 16px;' }, [inspectButton]),
    node]);
  });
 }
});
