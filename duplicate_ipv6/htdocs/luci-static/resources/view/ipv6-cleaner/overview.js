'use strict';
'require view';
'require form';
'require rpc';
'require poll';
'require ui';

var getStatus = rpc.declare({ object: 'ipv6-cleaner', method: 'status', expect: {} });
var runScan = rpc.declare({ object: 'ipv6-cleaner', method: 'run', expect: {} });
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
  o.value('remove', _('Remove deprecated public IPv6 addresses'));
  o.description = _('Removing an address can interrupt connections still using it. Manual scans use the saved action even when scheduling is disabled.');
  o = s.option(form.Value, 'interval', _('Scan frequency (seconds)'));
  o.value('120', _('2 minutes (suggested)'));
  o.value('300', _('5 minutes'));
  o.datatype = 'range(60,86400)';
  o.rmempty = false;
  o.description = _('Select a suggestion or enter a custom interval from 60 to 86400 seconds. Save & Apply restarts the schedule.');
  var status = E('div', {}, _('Loading status…'));
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
   }).catch(function(err) {
    status.replaceChildren(E('p', {}, _('Unable to load status: ') + err.message));
   });
  }
  return m.render().then(function(node) {
   poll.add(refresh, 5);
   return E('div', {}, [E('h2', {}, _('Status')), status,
    E('div', { 'style': 'display: block !important; padding-top: 16px !important; padding-bottom: 8px !important;' }, [button]),
    E('p', {}, _('Times and results are kept in RAM and reset after reboot. The next time is a scan; removal happens only in removal mode when eligible addresses exist.')),
    node]);
  });
 }
});
