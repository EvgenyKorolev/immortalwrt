'use strict';
'require view';
'require form';
'require rpc';
'require ui';
'require dom';
'require fs';
'require uci';

return view.extend({
	load: function() {
    	return uci.load('belmax').then(function() {
        	if (uci.sections('belmax', 'mesh_collector').length === 0) {
            	uci.add('belmax', 'mesh_collector', 'mesh_collector');
            	uci.set('belmax', 'mesh_collector', 'enabled', '0');
            	uci.set('belmax', 'mesh_collector', 'port', '8080');
            	uci.set('belmax', 'mesh_collector', 'stale_after', '90');
        	}
        	if (uci.sections('belmax', 'mesh_monitor').length === 0) {
            	uci.add('belmax', 'mesh_monitor', 'mesh_monitor');
            	uci.set('belmax', 'mesh_monitor', 'enabled', '1');
            	uci.set('belmax', 'mesh_monitor', 'interval', '30');
            	uci.set('belmax', 'mesh_monitor', 'collector_url',
                    'http://192.168.1.3:8080/api/mesh-data');
        	}
    	});
	},

	render: function() {
		var m = new form.Map('belmax', _('Simple device setup'));

		var sectcom = m.section(form.TypedSection, 'common', _('Common params'));
		sectcom.anonymous = true;

		var opthname = sectcom.option(form.Value, 'hostname', _('Hostname'), 'Оставьте пустым, чтобы не менять имя хоста');
		opthname.datatype = 'hostname';
		opthname.placeholder = 'BelMax';
		opthname.load = function(section_id) {
			return fs.trimmed('/proc/sys/kernel/hostname')
				.then(L.bind(function(hostname) {
					this.placeholder = hostname;
					return form.Value.prototype.load.apply(this, [section_id]);
				}, this))
				.catch(L.bind(function() {
					return form.Value.prototype.load.apply(this, [section_id]);
				}, this));
		};

		var sectmesh = m.section(form.TypedSection, 'mesh', _('Mesh params'));
		sectmesh.anonymous = true;

		var optmssid = sectmesh.option(form.Value, 'mesh_ssid', _('Mesh SSID'));
		optmssid.datatype = 'maxlength(32)';
		optmssid.placeholder = 'BelMax';

		var optmkey = sectmesh.option(form.Value, 'mesh_key', _('Mesh passwd'));
		optmkey.password = true;
		optmkey.datatype = 'wpakey';
		optmkey.placeholder = 'mesh key';

		var butmesh = sectmesh.option(form.Button, 'setup_mesh', _('    '));
		butmesh.inputstyle = 'action important';
		butmesh.inputtitle = _('Setup mesh');
		butmesh.onclick = function(ev) {
			var btn = ev.target;
			btn.firstChild.data = _('Setting up mesh ...');
			btn.disabled = true;

			var hname = opthname.formvalue('common')
			var mssid = optmssid.formvalue('mesh')
			var mkey = optmkey.formvalue('mesh')

			fs.exec('/usr/bin/setup-mesh-main', [ mssid, mkey, hname ])
				.then(function(res){
					ui.addNotification(null, E('p', `${res.stdout.trim().replace(/\n/g, '<br>')}`));
				})
				.catch(function(e) {
					ui.addNotification(null, E('p', e.message), 'error');
				})
				.finally(function() {
					btn.firstChild.data = _('Setup mesh');
					btn.disabled = false;
				});
		};

		var sectmon = m.section(form.TypedSection, 'mesh_monitor', _('Mesh Monitor Agent'));
		sectmon.anonymous = true;
		sectmon.addremove = false;

		var optenabled = sectmon.option(form.Flag, 'enabled', _('Enable Agent'), _('Автоматически запускать агент мониторинга'));
		optenabled.rmempty = false;
		optenabled.default = '1';

		var opturl = sectmon.option(form.Value, 'collector_url', _('Collector URL'), _('Полный URL коллектора (включая http://)'));
		opturl.datatype = 'string';
		opturl.placeholder = 'http://192.168.1.3:8080/api/mesh-data';
		opturl.rmempty = false;

		var optinterval = sectmon.option(form.Value, 'interval', _('Interval (sec)'), _('Интервал отправки данных в секундах'));
		optinterval.datatype = 'and(uinteger, min(5), max(3600))';
		optinterval.placeholder = '30';
		optinterval.rmempty = false;

		var sectcol = m.section(form.TypedSection, 'mesh_collector', _('Mesh Collector'),
			_('Сервер визуализации топологии. Включайте только на ОДНОМ устройстве сети.'));
		sectcol.anonymous = true;
		sectcol.addremove = false;

		var optcolen = sectcol.option(form.Flag, 'enabled', _('Enable Collector'), _('Запускать коллектор на этом устройстве'));
		optcolen.rmempty = false;
		optcolen.default = '0';

		var optcolport = sectcol.option(form.Value, 'port', _('Listen port'), _('TCP-порт веб-интерфейса и API. Применяется после перезагрузки устройства'));
		optcolport.datatype = 'port';
		optcolport.placeholder = '8080';
		optcolport.rmempty = false;

		var optcolstale = sectcol.option(form.Value, 'stale_after', _('Stale after (sec)'), _('Через сколько секунд без данных считать ноду неактивной'));
		optcolstale.datatype = 'and(uinteger, min(10), max(3600))';
		optcolstale.placeholder = '90';
		optcolstale.rmempty = false;

		var optcolstate = sectcol.option(form.DummyValue, '_state', _('Service state'));
		optcolstate.load = function() {
			return fs.exec('/etc/init.d/mesh-collector', [ 'status' ])
				.then(function(res) {
					return ((res.stdout || '') + (res.stderr || '')).trim() || 'unknown';
				})
				.catch(function() { return 'unknown'; });
		};

		var optcolurl = sectcol.option(form.DummyValue, '_webui', _('Web UI'));
		optcolurl.rawhtml = true;
		optcolurl.depends('enabled', '1');
		optcolurl.cfgvalue = function(section_id) {
			var port = this.map.data.get('belmax', section_id, 'port') || '8080';
			var url = 'http://' + window.location.hostname + ':' + port + '/';
			return '<a href="' + url + '" target="_blank" rel="noopener">' + url + '</a>';
		};

		m.applyOnSave = true;

		return m.render();
	}
});