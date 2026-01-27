'use strict';
'require view';
'require form';
'require rpc';
'require ui';
'require dom';
'require fs';

return view.extend({
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
			}, this));
		};

		// var optapssid = sectcom.option(form.Value, 'ap_ssid', _('AP SSID'));
		// optapssid.datatype = 'maxlength(32)';
		// optapssid.placeholder = 'BelMax';
		//
		// var optapkey = sectcom.option(form.Value, 'ap_key', _('AP passwd'));
		// optapkey.datatype = 'wpakey';
		// optapkey.password = true;

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

			fs.exec('/usr/bin/setup-mesh', [ mssid, mkey, hname ])
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

		return m.render();
	},
});
