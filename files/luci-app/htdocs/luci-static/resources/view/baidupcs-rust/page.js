'use strict';
'require view';
'require dom';
'require ui';

/*
 * BaiduPCS-Rust LuCI 页面：内嵌展示其自带 Web 管理界面。
 * 功能配置（登录、下载、上传、转存、分享同步、备份、加密、通知等）
 * 全部在 BaiduPCS-Rust 自带界面内完成，本页仅做入口与状态提示。
 */
return view.extend({
	handleSetPort: function(ev) {
		var port = document.getElementById('bpr-port').value || '18888';
		try {
			window.localStorage.setItem('baidupcs-rust.port', port);
		} catch (e) {}
		window.location.reload();
		return false;
	},

	render: function() {
		var port = '18888';
		try {
			port = window.localStorage.getItem('baidupcs-rust.port') || '18888';
		} catch (e) {}

		var host = window.location.hostname;
		var url = 'http://' + host + ':' + port + '/';

		var body = E([], [
			E('div', { 'class': 'cbi-map' }, [
				E('h2', {}, _('BaiduPCS-Rust — 百度网盘管理')),
				E('div', { 'class': 'cbi-map-descr' }, [
					_('后端 Web 管理界面地址：'),
					E('a', { 'href': url, 'target': '_blank' }, url),
					E('br'),
					_('首次使用请在打开的界面中完成百度网盘登录（二维码或 Cookie）。' +
					  '若设置了 Web 访问密码 / TOTP，请先在内嵌界面完成认证。'),
					E('br'),
					E('br'),
					_('Web 端口（默认 18888，与 /etc/config/baidupcs-rust 中 port 一致）：'),
					E('input', {
						'id': 'bpr-port', 'type': 'text', 'value': port,
						'style': 'width:8em;margin:0 .5em;'
					}),
					E('button', {
						'class': 'btn cbi-button',
						'click': ui.createHandlerFn(this, 'handleSetPort')
					}, _('刷新'))
				]),
				E('iframe', {
					'src': url,
					'style': 'width:100%;height:calc(100vh - 260px);min-height:480px;' +
						 'border:1px solid var(--border-color, #ccc);border-radius:4px;'
				})
			])
		]);

		return body;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
