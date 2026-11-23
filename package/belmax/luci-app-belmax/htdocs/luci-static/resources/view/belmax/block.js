'use strict';
'require view';
'require form';
'require rpc';
'require ui';
'require dom';
'require fs';

return view.extend({
    map: null,
    
	render: function() {
		var m = new form.Map('belmax', _('Block mesh nodes'));

		var s = m.section(form.TypedSection, 'mesh');
		s.anonymous = true;

        var o = s.option(form.DynamicList, 'block_nodes', _('Blocked nodes list'));
        o.placeholder = _('Enter node MAC address');
        o.datatype = "macaddr"
        
        this.map = m

		return m.render();
	},

    handleSave: function() {
        return this.map.save().then(function() {
            return fs.exec('/usr/bin/block-node', ['apply']);
        }).then(function(res) {
            if (res.code !== 0) {
                ui.addNotification(null,
                    E('p', _('block-node apply failed: ') + res.stderr));
            } else {
                ui.addNotification(null,
                    E('p', _('block-node apply ok: ') + res.stdout));
            }
        });
    }
});
