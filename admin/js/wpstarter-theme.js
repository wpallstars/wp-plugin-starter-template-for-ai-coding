/**
 * Header colour mode: save per person and sync wpallstars controls.
 * The PHP head script has already applied the initial mode before paint.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 Marcus Quinn
 * Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
 * Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.
 */
(function (wp, data) {
	'use strict';
	if (!wp || !wp.i18n || !data) {
		return;
	}
	var __ = wp.i18n.__;
	var sprintf = wp.i18n.sprintf;
	var EVENT = 'wpallstars-admin-theme';
	var SOURCE = 'wpstarter';
	var root = document.documentElement;
	var media = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
	var svgNs = 'http://www.w3.org/2000/svg';
	var modes = {
		light: {
			label: __('Light', 'wp-plugin-starter-template'),
			icon: 'M12 7.75a4.25 4.25 0 1 0 0 8.5 4.25 4.25 0 0 0 0-8.5zM11.25 2h1.5v3h-1.5zm0 17h1.5v3h-1.5zM2 11.25h3v1.5H2zm17 0h3v1.5h-3zM4.4 5.46 5.46 4.4l2.12 2.12-1.06 1.06zm12.02 12.02 1.06-1.06 2.12 2.12-1.06 1.06zM4.4 18.54l2.12-2.12 1.06 1.06-2.12 2.12zM16.42 6.52l2.12-2.12 1.06 1.06-2.12 2.12z'
		},
		dark: {
			label: __('Dark', 'wp-plugin-starter-template'),
			icon: 'M20.5 14.6A8.5 8.5 0 0 1 9.4 3.5a8.5 8.5 0 1 0 11.1 11.1z'
		},
		system: {
			label: __('System', 'wp-plugin-starter-template'),
			icon: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zm0 1.5v15a7.5 7.5 0 0 1 0-15z'
		}
	};
	var order = ['light', 'dark', 'system'];
	var mode = modes[data.mode] ? data.mode : 'light';
	var saving = false;
	var toggle;
	var menu;
	var items = [];

	function speak(message, politeness) {
		if (wp.a11y && wp.a11y.speak) {
			wp.a11y.speak(message, politeness || 'polite');
		}
	}

	function icon(path) {
		var svg = document.createElementNS(svgNs, 'svg');
		var shape = document.createElementNS(svgNs, 'path');
		svg.setAttribute('viewBox', '0 0 24 24');
		svg.setAttribute('aria-hidden', 'true');
		svg.setAttribute('focusable', 'false');
		shape.setAttribute('d', path);
		shape.setAttribute('fill-rule', 'evenodd');
		svg.appendChild(shape);
		return svg;
	}

	function name(which) {
		/* translators: %s: the colour mode, Light, Dark or System. */
		return sprintf(__('Colour mode: %s', 'wp-plugin-starter-template'), modes[which].label);
	}

	function apply(which) {
		mode = which;
		order.forEach(function (value) {
			root.classList.toggle('wps-theme-' + value, value === which);
		});
		root.classList.toggle('wps-dark', which === 'dark' || (which === 'system' && !!media && media.matches));
		if (toggle) {
			toggle.replaceChild(icon(modes[which].icon), toggle.firstChild);
			toggle.lastChild.textContent = name(which);
			toggle.title = name(which);
		}
		items.forEach(function (item) {
			item.setAttribute('aria-checked', item.getAttribute('data-wps-mode') === which ? 'true' : 'false');
		});
	}

	function save(which, previous) {
		var body = new URLSearchParams();
		body.append('action', data.action);
		body.append('nonce', data.nonce);
		body.append('mode', which);
		body.append('network', data.network ? '1' : '0');
		saving = true;
		toggle.disabled = true;
		window.fetch(data.ajaxUrl, { method: 'POST', credentials: 'same-origin', body: body })
			.then(function (response) {
				if (!response.ok) {
					throw new Error('not saved');
				}
				return response.json();
			})
			.then(function (answer) {
				if (!answer || !answer.success || !answer.data || answer.data.mode !== which) {
					throw new Error('not saved');
				}
				apply(which);
				document.dispatchEvent(new CustomEvent(EVENT, { detail: { mode: which, source: SOURCE } }));
			})
			.catch(function () {
				apply(previous);
				speak(__('The colour mode could not be saved. Please try again.', 'wp-plugin-starter-template'), 'assertive');
			})
			.then(function () {
				saving = false;
				toggle.disabled = false;
				toggle.focus();
			});
	}

	function close(focusToggle) {
		if (!menu || menu.hidden) {
			return;
		}
		menu.hidden = true;
		toggle.setAttribute('aria-expanded', 'false');
		if (focusToggle) {
			toggle.focus();
		}
	}

	function choose(which) {
		var previous = mode;
		close(true);
		if (saving || which === previous) {
			return;
		}
		apply(which);
		speak(name(which));
		save(which, previous);
	}

	function open() {
		menu.hidden = false;
		toggle.setAttribute('aria-expanded', 'true');
		var checked = items.filter(function (item) {
			return item.getAttribute('aria-checked') === 'true';
		})[0];
		(checked || items[0]).focus();
	}

	function move(step) {
		var at = items.indexOf(document.activeElement);
		items[(at + step + items.length) % items.length].focus();
	}

	function onMenuKey(event) {
		switch (event.key) {
			case 'Tab': close(false); return;
			case 'ArrowDown': move(1); break;
			case 'ArrowUp': move(-1); break;
			case 'Home': items[0].focus(); break;
			case 'End': items[items.length - 1].focus(); break;
			case 'Escape': close(true); break;
			default: return;
		}
		event.preventDefault();
	}

	function build() {
		var actions = document.querySelector('.wps-header__actions');
		if (!actions || actions.querySelector('.wps-theme')) {
			return;
		}
		var wrap = document.createElement('div');
		wrap.className = 'wps-theme';
		toggle = document.createElement('button');
		toggle.type = 'button';
		toggle.className = 'button wps-header__support wps-theme__toggle';
		toggle.setAttribute('aria-haspopup', 'menu');
		toggle.setAttribute('aria-expanded', 'false');
		toggle.setAttribute('aria-controls', 'wps-theme-menu');
		toggle.appendChild(icon(modes[mode].icon));
		var label = document.createElement('span');
		label.className = 'screen-reader-text';
		toggle.appendChild(label);
		menu = document.createElement('div');
		menu.id = 'wps-theme-menu';
		menu.className = 'wps-theme__menu';
		menu.setAttribute('role', 'menu');
		menu.setAttribute('aria-label', __('Colour mode', 'wp-plugin-starter-template'));
		menu.hidden = true;
		order.forEach(function (which) {
			var item = document.createElement('button');
			item.type = 'button';
			item.className = 'wps-theme__item';
			item.tabIndex = -1;
			item.setAttribute('role', 'menuitemradio');
			item.setAttribute('data-wps-mode', which);
			item.appendChild(icon(modes[which].icon));
			item.appendChild(document.createTextNode(modes[which].label));
			var check = document.createElement('span');
			check.className = 'dashicons dashicons-yes wps-theme__check';
			check.setAttribute('aria-hidden', 'true');
			item.appendChild(check);
			item.addEventListener('click', function () { choose(which); });
			items.push(item);
			menu.appendChild(item);
		});
		toggle.addEventListener('click', function () {
			if (menu.hidden) { open(); } else { close(true); }
		});
		toggle.addEventListener('keydown', function (event) {
			if ((event.key === 'ArrowDown' || event.key === 'ArrowUp') && menu.hidden) {
				event.preventDefault();
				open();
			}
		});
		menu.addEventListener('keydown', onMenuKey);
		wrap.addEventListener('focusout', function (event) {
			if (!wrap.contains(event.relatedTarget)) { close(false); }
		});
		document.addEventListener('click', function (event) {
			if (!wrap.contains(event.target)) { close(false); }
		});
		wrap.appendChild(toggle);
		wrap.appendChild(menu);
		var donate = actions.querySelector('.wps-header__donate');
		actions.insertBefore(wrap, donate ? donate.nextSibling : null);
		apply(mode);
	}

	if (media) {
		var follow = function () { if (mode === 'system') { apply('system'); } };
		if (media.addEventListener) { media.addEventListener('change', follow); }
		else if (media.addListener) { media.addListener(follow); }
	}
	document.addEventListener(EVENT, function (event) {
		var detail = event.detail;
		if (!detail || detail.source === SOURCE || order.indexOf(detail.mode) === -1) { return; }
		apply(detail.mode);
	});
	function start() {
		build();
	}
	if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', start); }
	else { start(); }
}(window.wp, window.wpstarterTheme));
