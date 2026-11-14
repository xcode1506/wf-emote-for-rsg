(function () {
    'use strict';

    const state = {
        items: [],
        selectedIndex: 0,
        maxItems: 50,
        rows: [],
        menuItems: [],
        menuIndex: 0,
        menuTabs: [],
        activeTab: 'all',
        menuPageSize: 10,
        lastNavDir: 0,
    };

    const root = document.documentElement;
    const pickerEl = document.getElementById('picker');
    const titleEl = document.getElementById('picker-title');
    const listEl = document.getElementById('picker-list');
    const logoEl = document.getElementById('picker-logo');

    const emenuEl = document.getElementById('emote-menu');
    const emenuTabsEl = document.getElementById('emenu-tabs');
    const emenuCaptionEl = document.getElementById('emenu-caption');
    const emenuCountEl = document.getElementById('emenu-caption-count');
    const emenuListEl = document.getElementById('emenu-list');
    const emenuPagerEl = document.getElementById('emenu-pager');
    const emenuPageEl = document.getElementById('emenu-page');
    const emenuSelTitleEl = document.getElementById('emenu-sel-title');
    const emenuSelDescEl = document.getElementById('emenu-sel-desc');

    // GetParentResourceName is injected by CEF at runtime; fall back to the
    // page origin (cfx-nui-<resource>) when it is not available yet.
    function resourceName() {
        if (typeof GetParentResourceName === 'function') {
            try { return GetParentResourceName(); } catch (e) { /* fall through */ }
        }
        const host = (window.location && window.location.hostname) || '';
        if (host.startsWith('cfx-nui-')) return host.slice(8);
        return host || 'wf-emote';
    }

    function post(name, data) {
        return fetch(`https://${resourceName()}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data || {}),
        }).catch(() => {});
    }

    function applyTheme(theme) {
        if (!theme) return;

        const map = {
            backgroundColor:    '--picker-bg',
            titleBackground:    '--picker-title-bg',
            textColor:          '--picker-text',
            selectedBackground: '--picker-selected-bg',
            selectedTextColor:  '--picker-selected-text',
            accentColor:        '--picker-accent',
            borderRadius:       '--picker-radius',
            width:              '--picker-width',
            fontFamily:         '--picker-font-family',
            fontSize:           '--picker-font-size',
            titleFontSize:      '--picker-title-font-size',
            itemPadding:        '--picker-item-padding',
            logoSize:           '--picker-logo-size',
        };

        Object.keys(map).forEach((key) => {
            if (theme[key] !== undefined && theme[key] !== null) {
                root.style.setProperty(map[key], theme[key]);
            }
        });

        if (theme.position === 'left') {
            root.style.setProperty('--picker-position-right', 'auto');
            root.style.setProperty('--picker-position-left', '5%');
            root.style.setProperty('--picker-position-transform', 'translateY(-50%)');
        } else if (theme.position === 'center') {
            root.style.setProperty('--picker-position-right', 'auto');
            root.style.setProperty('--picker-position-left', '50%');
            root.style.setProperty('--picker-position-transform', 'translate(-50%, -50%)');
        } else {
            root.style.setProperty('--picker-position-right', '5%');
            root.style.setProperty('--picker-position-left', 'auto');
            root.style.setProperty('--picker-position-transform', 'translateY(-50%)');
        }

        if (theme.showCategoryDot === false) {
            root.style.setProperty('--picker-dot-display', 'none');
        } else {
            root.style.setProperty('--picker-dot-display', 'inline-block');
        }

        if (theme.showLogo !== false && theme.logoUrl) {
            logoEl.src = theme.logoUrl;
            root.style.setProperty('--picker-logo-display', 'block');
        } else {
            logoEl.removeAttribute('src');
            root.style.setProperty('--picker-logo-display', 'none');
        }

        if (theme.showTitle === false) {
            root.style.setProperty('--picker-title-display', 'none');
        } else {
            root.style.setProperty('--picker-title-display', 'block');
        }

        if (typeof theme.maxItems === 'number' && theme.maxItems > 0) {
            state.maxItems = theme.maxItems;
        }
    }


    function buildInteractionPayload(item) {
        if (!item || item.dataset.cancel === '1') {
            return item && item.dataset.cancel === '1' ? { cancel: 1 } : {};
        }

        const payload = {
            x:       parseFloat(item.dataset.x),
            y:       parseFloat(item.dataset.y),
            z:       parseFloat(item.dataset.z),
            heading: parseFloat(item.dataset.heading),
            object:  item.dataset.object ? parseInt(item.dataset.object, 10) : null,
            effect:  item.dataset.effect || null,
        };

        if (item.dataset.scenario) {
            payload.scenario = item.dataset.scenario;
        } else if (item.dataset.animationDict) {
            payload.animation = {
                dict: item.dataset.animationDict,
                name: item.dataset.animationName,
            };
        }

        return payload;
    }

    function notifyMarker(item) {
        const dir = state.lastNavDir || 1;
        if (!item || item.dataset.cancel === '1') {
            post('setInteractionMarker', { dir: dir });
            return;
        }

        if (item.dataset.object) {
            post('setInteractionMarker', { entity: parseInt(item.dataset.object, 10), dir: dir });
            return;
        }

        post('setInteractionMarker', {
            x: parseFloat(item.dataset.x),
            y: parseFloat(item.dataset.y),
            z: parseFloat(item.dataset.z),
            dir: dir,
        });
    }

    function notifyPreview(item) {
        post('setInteractionPreview', buildInteractionPayload(item));
    }

    function refreshSelection() {
        const rows = state.rows;
        for (let i = 0; i < rows.length; i++) {
            rows[i].classList.toggle('selected', i === state.selectedIndex);
        }
        const current = rows[state.selectedIndex];
        if (current && typeof current.scrollIntoView === 'function') {
            current.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
        }
        notifyMarker(current);
        notifyPreview(current);
    }

    function updateListFades() {
        const canUp = listEl.scrollTop > 2;
        const canDown = listEl.scrollTop + listEl.clientHeight < listEl.scrollHeight - 2;
        listEl.classList.toggle('fade-up', canUp);
        listEl.classList.toggle('fade-down', canDown);
    }

    listEl.addEventListener('scroll', updateListFades);
    window.addEventListener('resize', updateListFades);

    function renderPicker(payload) {
        applyTheme(payload.theme);
        titleEl.textContent = payload.title || 'Interactions';

        const interactions = JSON.parse(payload.interactions || '[]');
        listEl.innerHTML = '';

        const limit = Math.min(interactions.length, state.maxItems);
        let lastCategory = null;

        for (let i = 0; i < limit; i++) {
            const data = interactions[i];

            if (data.categoryLabel && data.categoryLabel !== lastCategory) {
                lastCategory = data.categoryLabel;
                const group = document.createElement('div');
                group.className = 'picker__group';
                group.textContent = data.categoryLabel;
                listEl.appendChild(group);
            }

            const div = document.createElement('div');
            div.className = 'picker__item';

            const caret = document.createElement('span');
            caret.className = 'picker__caret';
            div.appendChild(caret);

            const dot = document.createElement('span');
            dot.className = 'picker__dot';
            div.appendChild(dot);

            const text = document.createElement('span');
            text.textContent = data.displayLabel || '';
            div.appendChild(text);

            div.dataset.x = data.x;
            div.dataset.y = data.y;
            div.dataset.z = data.z;
            div.dataset.heading = data.heading;

            if (data.scenario) {
                div.dataset.scenario = data.scenario;
            } else if (data.animation) {
                div.dataset.animationDict = data.animation.dict;
                div.dataset.animationName = data.animation.name;
            }

            if (data.object) {
                div.dataset.object = data.object;
            }
            if (data.effect) {
                div.dataset.effect = data.effect;
            }

            listEl.appendChild(div);
        }

        const cancelDiv = document.createElement('div');
        cancelDiv.className = 'picker__item cancel';

        const cancelCaret = document.createElement('span');
        cancelCaret.className = 'picker__caret';
        cancelDiv.appendChild(cancelCaret);

        const cancelDot = document.createElement('span');
        cancelDot.className = 'picker__dot';
        cancelDiv.appendChild(cancelDot);

        const cancelText = document.createElement('span');
        cancelText.textContent = payload.cancelLabel || 'End Interaction';
        cancelDiv.appendChild(cancelText);

        cancelDiv.dataset.cancel = '1';
        listEl.appendChild(cancelDiv);

        state.rows = Array.prototype.slice.call(listEl.querySelectorAll('.picker__item'));
        state.selectedIndex = 0;
        refreshSelection();

        pickerEl.classList.remove('hidden');
        requestAnimationFrame(updateListFades);
    }

    function hidePicker() {
        pickerEl.classList.add('hidden');
        state.rows = [];
        state.selectedIndex = 0;
        post('setInteractionMarker', {});
        post('setInteractionPreview', {});
    }

    function moveSelection(delta) {
        const total = state.rows.length;
        if (total === 0) return;
        state.lastNavDir = delta;
        state.selectedIndex = ((state.selectedIndex + delta) % total + total) % total;
        refreshSelection();
    }

    function confirmSelection() {
        const selected = state.rows[state.selectedIndex];
        if (!selected) {
            hidePicker();
            return;
        }

        if (selected.dataset.cancel === '1') {
            post('stopInteraction', {});
            hidePicker();
            return;
        }

        post('startInteraction', buildInteractionPayload(selected));
        hidePicker();
    }

    listEl.addEventListener('click', function (event) {
        if (pickerEl.classList.contains('hidden')) return;
        const target = event.target;
        if (!target || typeof target.closest !== 'function') return;
        const row = target.closest('.picker__item');
        if (!row) return;
        const index = state.rows.indexOf(row);
        if (index < 0) return;
        state.selectedIndex = index;
        confirmSelection();
    });

    let lastPickerWheelAt = 0;
    pickerEl.addEventListener('wheel', function (event) {
        if (pickerEl.classList.contains('hidden')) return;
        event.preventDefault();
        const now = performance.now();
        if (now - lastPickerWheelAt < 55) return;
        lastPickerWheelAt = now;
        moveSelection(event.deltaY > 0 ? 1 : -1);
    }, { passive: false });

    /* ------------------------------------------------------------------ */
    /* Emote book (F7)                                                     */
    /* ------------------------------------------------------------------ */

    function currentMenuItem() {
        return state.menuItems[state.menuIndex] || null;
    }

    function iconEl(name) {
        const span = document.createElement('span');
        span.className = 'emenu__ico';
        span.style.setProperty('--ico', "url('assets/icons/" + (name || 'person') + ".png')");
        return span;
    }

    function renderTabs(tabs, activeKey) {
        state.menuTabs = Array.isArray(tabs) ? tabs : [];
        state.activeTab = activeKey || 'all';
        emenuTabsEl.innerHTML = '';

        state.menuTabs.forEach(function (tab) {
            const div = document.createElement('div');
            div.className = 'emenu__tab' + (tab.key === state.activeTab ? ' active' : '');
            div.appendChild(iconEl(tab.icon));

            const label = document.createElement('span');
            label.className = 'emenu__tab-label';
            label.textContent = tab.label || '';
            div.appendChild(label);

            div.addEventListener('click', function () {
                post('wfEmoteTab', { value: tab.value || '' });
            });            emenuTabsEl.appendChild(div);
        });
    }

    function moveTab(delta) {
        const tabs = state.menuTabs;
        if (tabs.length === 0) return;
        let index = tabs.findIndex(function (tab) { return tab.key === state.activeTab; });
        if (index < 0) index = 0;
        index = ((index + delta) % tabs.length + tabs.length) % tabs.length;
        post('wfEmoteTab', { value: tabs[index].value || '', dir: delta });
    }

    function updatePage() {
        const totalItems = state.menuItems.length;
        const size = Math.max(1, state.menuPageSize);
        const pages = Math.max(1, Math.ceil(totalItems / size));
        const page = Math.min(pages, Math.floor(state.menuIndex / size) + 1);
        emenuPageEl.textContent = page + ' / ' + pages;
        emenuPagerEl.classList.toggle('hidden', totalItems <= size);
    }

    function updateFooter() {
        const current = currentMenuItem();
        emenuSelTitleEl.textContent = current ? (current.label || '') : '';
        emenuSelDescEl.textContent = current ? (current.desc || '') : '';
    }

    function measurePageSize() {
        const first = emenuListEl.querySelector('.emenu__item');
        if (!first) return;
        const style = window.getComputedStyle(emenuListEl);
        const gap = parseFloat(style.rowGap) || 0;
        const height = first.getBoundingClientRect().height;
        const size = Math.floor(emenuListEl.clientHeight / (height + gap));
        state.menuPageSize = Math.max(1, size || 10);
        updatePage();
    }

    function refreshMenuSelection(scroll) {
        const items = emenuListEl.querySelectorAll('.emenu__item');
        for (let i = 0; i < items.length; i++) {
            items[i].classList.toggle('selected', i === state.menuIndex);
        }
        const current = items[state.menuIndex];
        if (scroll && current && typeof current.scrollIntoView === 'function') {
            current.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
        }
        updateFooter();
        updatePage();
    }

    function highlightMenuItem() {
        const current = currentMenuItem();
        const payload = { value: current ? String(current.value || '') : '' };
        if (state.lastNavDir) payload.dir = state.lastNavDir;
        post('wfEmoteHighlight', payload);
    }

    function menuItemElement(item) {
        const row = document.createElement('div');
        row.className = 'emenu__item' + (item.kind === 'stop' ? ' cancel' : '');
        row.dataset.value = item.value || '';

        row.appendChild(iconEl(item.icon));

        const label = document.createElement('span');
        label.className = 'emenu__item-label';
        label.textContent = item.label || '';
        row.appendChild(label);

        if (item.kind === 'anim') {
            const star = iconEl(item.fav ? 'star' : 'star-empty');
            star.classList.add('emenu__star');
            if (item.fav) star.classList.add('fav');
            row.appendChild(star);
        }

        return row;
    }

    function layoutEmoteMenu(withHighlight) {
        measurePageSize();
        refreshMenuSelection(true);
        if (withHighlight) highlightMenuItem();
    }

    function renderEmoteMenu(data) {
        const items = Array.isArray(data.items) ? data.items : [];
        state.menuItems = items;
        state.menuIndex = 0;
        state.lastNavDir = 0; // first highlight after a render is not a navigation

        renderTabs(data.tabs, data.activeTab);

        emenuCaptionEl.textContent = data.title || 'Emotes';
        emenuCountEl.textContent = data.subtitle || '';

        emenuListEl.innerHTML = '';
        if (items.length === 0) {
            const empty = document.createElement('div');
            empty.className = 'emenu__empty';
            empty.textContent = 'Nothing here yet';
            emenuListEl.appendChild(empty);
        } else {
            items.forEach(function (item) {
                emenuListEl.appendChild(menuItemElement(item));
            });
        }

        const requested = Number(data.index);
        state.menuIndex = Math.min(
            Math.max(Number.isFinite(requested) ? requested : 0, 0),
            Math.max(items.length - 1, 0)
        );

        emenuEl.classList.remove('hidden');
        emenuEl.setAttribute('aria-hidden', 'false');

        // highlight right away (rAF can be delayed while the game window is
        // busy) and re-measure once layout and fonts have settled
        layoutEmoteMenu(true);
        requestAnimationFrame(function () { layoutEmoteMenu(false); });
    }

    function hideEmoteMenu() {
        emenuEl.classList.add('hidden');
        emenuEl.setAttribute('aria-hidden', 'true');
        emenuTabsEl.innerHTML = '';
        emenuListEl.innerHTML = '';
        state.menuItems = [];
        state.menuTabs = [];
        state.menuIndex = 0;
    }

    function moveMenuItem(delta) {
        const total = state.menuItems.length;
        if (total === 0) return;
        state.lastNavDir = delta;
        state.menuIndex = ((state.menuIndex + delta) % total + total) % total;
        refreshMenuSelection(true);
        highlightMenuItem();
    }

    function confirmMenuItem() {
        const current = currentMenuItem();
        if (!current) return;
        post('wfEmotePick', { value: String(current.value || '') });
    }

    function toggleFavourite() {
        const current = currentMenuItem();
        if (!current || current.kind !== 'anim') return;
        const row = emenuListEl.querySelectorAll('.emenu__item')[state.menuIndex];
        const star = row && row.querySelector('.emenu__star');
        if (star) star.classList.toggle('fav');
        post('wfEmoteFav', {
            id: String(current.value || '').slice(5),
            index: state.menuIndex,
        });
    }

    function backMenuItem() {
        post('wfEmoteBack', {});
    }

    emenuListEl.addEventListener('click', function (event) {
        if (emenuEl.classList.contains('hidden')) return;
        const target = event.target;
        if (!target || typeof target.closest !== 'function') return;
        const row = target.closest('.emenu__item');
        if (!row) return;

        const rows = emenuListEl.querySelectorAll('.emenu__item');
        const index = Array.prototype.indexOf.call(rows, row);
        if (index < 0) return;

        state.menuIndex = index;
        refreshMenuSelection(false);

        if (target.closest('.emenu__star')) {
            toggleFavourite();
            return;
        }

        confirmMenuItem();
    });

    let lastWheelAt = 0;

    emenuEl.addEventListener('wheel', function (event) {
        if (emenuEl.classList.contains('hidden')) return;
        event.preventDefault();
        const now = performance.now();
        if (now - lastWheelAt < 55) return;
        lastWheelAt = now;
        moveMenuItem(event.deltaY > 0 ? 1 : -1);
    }, { passive: false });

    window.addEventListener('keydown', function (event) {
        if (emenuEl.classList.contains('hidden')) return;

        switch (event.key) {
            case 'ArrowDown':
                event.preventDefault();
                moveMenuItem(1);
                break;
            case 'ArrowUp':
                event.preventDefault();
                moveMenuItem(-1);
                break;
            case 'ArrowLeft':
                event.preventDefault();
                moveTab(-1);
                break;
            case 'ArrowRight':
                event.preventDefault();
                moveTab(1);
                break;
            case 'Enter':
                event.preventDefault();
                confirmMenuItem();
                break;
            case 'f':
            case 'F':
                event.preventDefault();
                toggleFavourite();
                break;
            case 'Backspace':
            case 'Escape':
                event.preventDefault();
                backMenuItem();
                break;
        }
    });

    window.addEventListener('message', function (event) {
        const data = event.data || {};

        switch (data.type) {
            case 'showInteractionPicker':
                renderPicker(data);
                break;
            case 'hideInteractionPicker':
                hidePicker();
                break;
            case 'moveSelectionUp':
                moveSelection(-1);
                break;
            case 'moveSelectionDown':
                moveSelection(1);
                break;
            case 'startInteraction':
                confirmSelection();
                break;
            case 'wfEmoteShow':
                renderEmoteMenu(data);
                break;
            case 'wfEmoteHide':
                hideEmoteMenu();
                break;
        }
    });
})();
