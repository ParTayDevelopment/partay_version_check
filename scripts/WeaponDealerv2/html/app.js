const state = {
    resource: 'qbx_weapondealer',
    visible: false,
    mode: 'sales',
    store: null,
    employeeName: null,
    buyers: [],
    weapons: [],
    orders: [],
    assemblyOrders: [],
    partsOrdering: { allowed: false, catalog: [], weaponKits: [], orders: [], paymentSources: {}, balances: {} },
    activeOrders: [],
    profile: null,
    quote: null,
    cart: {},
    accessoryCart: {},
    meleeCart: {},
    partsCart: {},
    paymentMethod: null,
    accessoryPaymentMethod: null,
    meleePaymentMethod: null,
    partsPaymentSource: null,
    selectedTradeIn: null,
    selected: {
        scan: null,
        order: null,
        active: null,
        profile: null
    },
    pickerQuery: {
        scan: '',
        order: '',
        active: '',
        profile: ''
    },
    selectedWeapon: null,
    lastScan: null,
    scanning: false,
    verifiedBuyer: null,
    activeTab: 'scan',
    consentResolved: false,
    consentCloseTimer: null,
    stockWeaponFilter: 'all'
};

const el = (id) => document.getElementById(id);
const app = el('app');
const consentPrompt = el('consentPrompt');
const confirmPrompt = el('confirmPrompt');
let confirmResolver = null;

function post(action, data = {}) {
    return fetch(`https://${state.resource}/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).then((response) => response.json()).catch(() => null);
}

function setVisible(visible) {
    state.visible = visible;
    app.classList.toggle('hidden', !visible);
    document.body.classList.toggle('nui-visible', visible);
}

function showConfirmPrompt(options) {
    if (confirmResolver) {
        confirmResolver(false);
        confirmResolver = null;
    }

    setText('confirmEyebrow', options.eyebrow || 'Action Confirmation');
    setText('confirmTitle', options.title || 'Legal Firearm Registry');
    setText('confirmPrimary', options.primary || '-');
    setText('confirmSecondary', options.secondary || '-');
    setText('confirmSecure', options.secure || 'Confirm');

    const message = el('confirmMessage');
    if (message) {
        message.innerHTML = options.html || '';
    }

    app?.classList.add('modal-blur');
    confirmPrompt?.classList.remove('hidden');

    return new Promise((resolve) => {
        confirmResolver = resolve;
    });
}

function resolveConfirmPrompt(value) {
    if (!confirmResolver) return;
    const resolve = confirmResolver;
    confirmResolver = null;
    app?.classList.remove('modal-blur');
    confirmPrompt?.classList.add('hidden');
    resolve(value);
}

function allowedTabs() {
    if (state.mode === 'order') return ['order', 'accessories', 'melee'];
    if (state.mode === 'pickup') return ['pickup'];
    if (state.mode === 'assembly') return state.partsOrdering?.allowed ? ['assembly', 'stock'] : ['assembly'];
    const tabs = ['scan', 'active', 'profile'];
    return tabs;
}

function setTab(tab) {
    const allowed = allowedTabs();
    if (!allowed.includes(tab)) {
        tab = allowed[0] || 'scan';
    }

    state.activeTab = tab;

    document.querySelectorAll('.tab').forEach((button) => {
        button.classList.toggle('active', button.dataset.tab === tab);
    });

    document.querySelectorAll('.panel').forEach((panel) => {
        panel.classList.toggle('active', panel.dataset.panel === tab);
    });

    if (tab !== 'order' && tab !== 'melee') {
        post('previewWeapon', { model: null });
    } else if (tab === 'melee') {
        const first = meleeItems()[0];
        if (first) {
            const item = (state.quote?.melee || []).find((candidate) => candidate.item === first.item);
            post('previewWeapon', { model: item?.previewModel || first.item });
        }
    }
}

function updateTabLocks() {
    const allowed = allowedTabs();

    document.querySelectorAll('.tab').forEach((tab) => {
        const locked = !allowed.includes(tab.dataset.tab);
        tab.disabled = locked;
        tab.classList.toggle('locked', locked);
    });
}

function getBuyer(value) {
    return state.buyers.find((buyer) => String(buyer.value) === String(value));
}

function mergeBuyers(buyers) {
    const merged = [];
    const seen = new Set();

    [...(buyers || []), ...state.buyers].forEach((buyer) => {
        if (!buyer?.value || seen.has(String(buyer.value))) return;
        seen.add(String(buyer.value));
        merged.push(buyer);
    });

    state.buyers = merged;
}

function filteredBuyers(key) {
    const query = (state.pickerQuery[key] || '').trim().toLowerCase();
    if (!query) return state.buyers;

    return state.buyers.filter((buyer) => {
        return String(buyer.value).includes(query) || String(buyer.label).toLowerCase().includes(query);
    });
}

function renderCustomerPicker(key, label) {
    const container = document.querySelector(`[data-picker="${key}"]`);
    if (!container) return;

    const selected = getBuyer(state.selected[key]);
    const query = state.pickerQuery[key];
    const displayValue = query || selected?.label || '';

    container.className = 'customer-picker';
    container.innerHTML = `
        <label class="field">
            <span>${label}</span>
            <input class="customer-picker__input" type="text" value="${escapeHtml(displayValue)}" placeholder="Search by server ID or label">
        </label>
        <div class="customer-picker__list"></div>
    `;

    const input = container.querySelector('input');
    renderPickerOptions(container, key);

    input.addEventListener('focus', () => container.classList.add('open'));
    input.addEventListener('input', (event) => {
        state.pickerQuery[key] = event.target.value;
        container.classList.add('open');
        renderPickerOptions(container, key);
    });
    input.addEventListener('blur', () => {
        setTimeout(() => container.classList.remove('open'), 120);
    });
}

function renderPickerOptions(container, key) {
    const list = container.querySelector('.customer-picker__list');
    const buyers = filteredBuyers(key);
    list.innerHTML = '';

    if (!buyers.length) {
        list.innerHTML = '<button class="customer-option" type="button">No matching players</button>';
        return;
    }

    buyers.forEach((buyer) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = `customer-option ${String(state.selected[key]) === String(buyer.value) ? 'active' : ''}`;
        button.textContent = buyer.label;
        button.addEventListener('mousedown', (event) => {
            event.preventDefault();
            state.selected[key] = buyer.value;
            state.pickerQuery[key] = '';

            if (key === 'scan') {
                state.selected.order = buyer.value;
                state.selected.active = buyer.value;
                state.selected.profile = buyer.value;
            }

            render();

            if (key === 'active') {
                loadActiveOrders();
            }

            if (key === 'profile') {
                loadProfile();
            }
        });
        list.appendChild(button);
    });
}

function escapeHtml(value) {
    return String(value || '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
}

function formatMoney(value) {
    return Number(value || 0).toLocaleString();
}

function inventoryImage(item, image) {
    const filename = image || (item ? `${item}.png` : 'WEAPON_PISTOL.png');
    return `nui://ox_inventory/web/images/${escapeHtml(filename)}`;
}

function quoteFor(item) {
    return state.quote?.weapons?.find((weapon) => weapon.item === item);
}

function cartItems() {
    return Object.values(state.cart);
}

function accessoryItems() {
    return Object.values(state.accessoryCart);
}

function meleeItems() {
    return Object.values(state.meleeCart);
}

function partsItems() {
    return Object.values(state.partsCart);
}

function stockPackageOptions(part) {
    return Array.isArray(part?.packageOptions) && part.packageOptions.length
        ? part.packageOptions
        : [{ units: Number(part?.pack || 1), price: Number(part?.price || 0), label: `${Number(part?.pack || 1)} Units` }];
}

function selectedStockPackage(part, entry) {
    const options = stockPackageOptions(part);
    const requested = Number(entry?.packageUnits || entry?.pack || 0);
    const defaultUnits = Number(part?.pack || 0);
    return options.find((option) => Number(option.units) === requested)
        || options.find((option) => Number(option.units) === defaultUnits)
        || options[options.length - 1];
}

function cartTotal() {
    return firearmTotal() + accessoryTotal() + meleeTotal();
}

function firearmTotal() {
    return cartItems().reduce((total, entry) => {
        const weapon = state.weapons.find((candidate) => candidate.item === entry.weapon);
        const ammoCfg = state.quote?.ammo?.[weapon?.ammo];
        return total
            + Number(weapon?.price || 0)
            + (Number(entry.ammoPackages || 0) * Number(ammoCfg?.price || 0))
            + attachmentTotal(weapon, entry);
    }, 0);
}

function selectedTradeIn() {
    if (!state.selectedTradeIn || !state.quote?.tradeIns) return null;
    return state.quote.tradeIns.find((trade) => String(trade.slot) === String(state.selectedTradeIn)) || null;
}

function tradeInCredit() {
    const trade = selectedTradeIn();
    if (!trade) return 0;

    const total = cartItems().length > 0 ? firearmTotal() : meleeTotal();
    const maxPercent = Number(state.quote?.tradeIn?.maxCreditPercent || 100);
    return Math.min(Number(trade.value || 0), Math.floor(total * (maxPercent / 100)), total);
}

function orderAmountDue() {
    return Math.max(cartTotal() - tradeInCredit(), 0);
}

function meleeTradeInCredit() {
    const trade = selectedTradeIn();
    if (!trade) return 0;

    const total = meleeTotal();
    const maxPercent = Number(state.quote?.tradeIn?.maxCreditPercent || 100);
    return Math.min(Number(trade.value || 0), Math.floor(total * (maxPercent / 100)), total);
}

function meleeAmountDue() {
    return Math.max(meleeTotal() - meleeTradeInCredit(), 0);
}

function packageFor(weapon, packageId) {
    return (weapon?.packages || []).find((candidate) => candidate.id === packageId) || null;
}

function attachmentFor(weapon, attachmentId) {
    return (weapon?.attachments || []).find((candidate) => candidate.id === attachmentId) || null;
}

function packageAttachmentIds(weapon, entry) {
    const selectedPackage = packageFor(weapon, entry?.package);
    return new Set((selectedPackage?.attachments || []).map(String));
}

function attachmentTotal(weapon, entry) {
    if (!weapon || !entry) return 0;

    const included = packageAttachmentIds(weapon, entry);
    const selectedPackage = packageFor(weapon, entry.package);
    const selected = Array.isArray(entry.attachments) ? entry.attachments.map(String) : [];
    let total = Number(selectedPackage?.price || 0);

    selected.forEach((id) => {
        if (included.has(id)) return;
        total += Number(attachmentFor(weapon, id)?.price || 0);
    });

    return total;
}

function canUsePayment(method) {
    const total = orderAmountDue();
    return cartTotal() > 0 && (total <= 0 || Number(state.quote?.balances?.[method] || 0) >= total);
}

function accessoryTotal() {
    return accessoryItems().reduce((total, entry) => {
        if (entry.type === 'attachment') {
            const attachment = (state.quote?.attachments || []).find((candidate) => candidate.item === entry.item);
            return total + Number(attachment?.price || 0);
        }

        const ammo = state.quote?.ammo?.[entry.item];
        return total + (Number(entry.packages || 0) * Number(ammo?.price || 0));
    }, 0);
}

function canUseAccessoryPayment(method) {
    return canUsePayment(method);
}

function meleeTotal() {
    return meleeItems().reduce((total, entry) => {
        const melee = (state.quote?.melee || []).find((candidate) => candidate.item === entry.item);
        return total + Number(melee?.price || 0);
    }, 0);
}

function canUseMeleePayment(method) {
    return canUsePayment(method);
}

function partsTotal() {
    return partsItems().reduce((total, entry) => {
        const part = state.partsOrdering?.catalog?.find((candidate) => candidate.item === entry.item);
        const option = selectedStockPackage(part, entry);
        return total + (Number(entry.packages || 0) * Number(option?.price || 0));
    }, 0);
}

function canUsePartsPayment(source) {
    const total = partsTotal();
    return total > 0 && state.partsOrdering?.paymentSources?.[source] === true && Number(state.partsOrdering?.balances?.[source] || 0) >= total;
}

function refreshQuote() {
    return post('getOrderQuote').then((quote) => {
        state.quote = quote || null;
        if (quote?.buyer) {
            state.verifiedBuyer = quote.buyer;
            state.selected.order = quote.buyer;
        }
        if (state.selectedTradeIn && !(quote?.tradeIns || []).some((trade) => String(trade.slot) === String(state.selectedTradeIn))) {
            state.selectedTradeIn = null;
        }
        render();
    });
}

function formatRemaining(seconds, status) {
    if (status === 'pending_assembly') return 'Awaiting assembly';
    if (status === 'ready' || Number(seconds || 0) <= 0) return 'Ready for pickup';

    const total = Number(seconds || 0);
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const secs = total % 60;

    if (hours > 0) return `${hours}h ${minutes}m`;
    if (minutes > 0) return `${minutes}m ${secs}s`;
    return `${secs}s`;
}

function waitLabel(seconds) {
    seconds = Number(seconds || 0);
    if (seconds < 60) return `${seconds}s`;
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes}m`;
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    return rest > 0 ? `${hours}h ${rest}m` : `${hours}h`;
}

function formatDateTime(value) {
    if (!value) return 'Not saved';

    let date = null;
    if (typeof value === 'number' || /^\d+$/.test(String(value))) {
        const numeric = Number(value);
        date = new Date(numeric > 100000000000 ? numeric : numeric * 1000);
    } else {
        date = new Date(String(value).replace(' ', 'T'));
    }

    if (!date || Number.isNaN(date.getTime())) return String(value);

    return new Intl.DateTimeFormat(undefined, {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
        hour: 'numeric',
        minute: '2-digit'
    }).format(date);
}

function formatStatus(value) {
    const raw = String(value || 'unknown').trim();
    if (!raw) return 'Unknown';

    return raw.replace(/[_-]+/g, ' ').replace(/\w\S*/g, (word) => {
        return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
    });
}

function scanBadgeReason(rows, hasError, allSuccess, processing, activeIndex) {
    if (allSuccess) return 'Customer Verified';

    const errorIndex = rows.findIndex((row) => row.status === 'error');
    if (hasError) {
        const reasons = {
            0: 'Employee Not Authorized',
            1: 'Consent Declined',
            2: 'Missing Government ID',
            3: 'ID Holder Mismatch',
            4: 'Missing Weapon License',
            5: 'ID And License Mismatch',
            6: 'License Not Valid',
            7: 'License Expired',
            8: 'Registry Record Invalid',
            9: 'Profile Save Failed'
        };

        return reasons[errorIndex] || rows[errorIndex]?.label || 'Verification Rejected';
    }

    if (processing) {
        const labels = {
            0: 'Checking Employee',
            1: 'Awaiting Consent',
            2: 'Reading ID',
            3: 'Matching Customer',
            4: 'Reading License',
            5: 'Matching Documents',
            6: 'Checking Status',
            7: 'Checking Expiration',
            8: 'Checking Registry',
            9: 'Saving Profile'
        };

        return labels[activeIndex] || 'Processing';
    }

    return 'Waiting';
}

function statusClass(value) {
    const normalized = String(value || '').toLowerCase();
    if (['valid', 'active', 'approved'].includes(normalized)) return 'good';
    if (['revoked', 'expired', 'invalid', 'denied', 'rejected', 'suspended'].includes(normalized)) return 'bad';
    return 'warn';
}

function orderAttachmentLabels(order) {
    if (!order?.attachments) return [];

    let decoded = order.attachments;
    if (typeof decoded === 'string') {
        try {
            decoded = JSON.parse(decoded);
        } catch (_) {
            return [];
        }
    }

    if (!Array.isArray(decoded?.items)) return [];
    return decoded.items.map((attachment) => attachment.label || attachment.item).filter(Boolean);
}

function setText(id, value) {
    const node = el(id);
    if (node) node.textContent = value;
}

function resetScanDocuments() {
    ['idCard', 'licCard'].forEach((id) => {
        const card = el(id);
        if (card) card.classList.remove('scanning', 'verified', 'rejected');
    });

    ['idStamp', 'licStamp'].forEach((id) => {
        const stamp = el(id);
        if (stamp) stamp.classList.remove('show', 'rejected');
    });

    setText('idCitizen', 'Awaiting scan');
    setText('idHolder', 'Not loaded');
    setText('idDob', '--');
    setText('licId', 'Awaiting scan');
    setText('licStatus', 'Not loaded');
    setText('licRegistry', 'Pending');
}

function updateScanVisuals(rows, hasError, allSuccess, activeIndex, completed) {
    const total = rows.length || 10;
    const completeCount = allSuccess ? total : completed;
    const pct = Math.min(100, Math.round((completeCount / total) * 100));
    const activeRow = rows[activeIndex] || rows[completed] || rows[0];
    const idCard = el('idCard');
    const licCard = el('licCard');
    const idStamp = el('idStamp');
    const licStamp = el('licStamp');

    setText('scanOp', activeRow?.label || 'Waiting for document swipe');
    setText('scanStepCounter', `${completeCount} / ${total} checks complete`);
    if (el('scanFill')) el('scanFill').style.width = `${pct}%`;

    if (!state.lastScan) {
        resetScanDocuments();
        return;
    }

    idCard?.classList.remove('scanning', 'verified', 'rejected');
    licCard?.classList.remove('scanning', 'verified', 'rejected');
    idStamp?.classList.remove('show', 'rejected');
    licStamp?.classList.remove('show', 'rejected');

    if (hasError) {
        const idOk = rows[2]?.status === 'success' && rows[3]?.status === 'success';
        const idBad = rows[2]?.status === 'error' || rows[3]?.status === 'error';
        const licenseOk = rows[4]?.status === 'success' && rows[5]?.status === 'success' && rows[6]?.status === 'success' && rows[7]?.status === 'success' && rows[8]?.status === 'success';
        const licenseBad = rows[4]?.status === 'error' || rows[5]?.status === 'error' || rows[6]?.status === 'error' || rows[7]?.status === 'error' || rows[8]?.status === 'error';

        if (idOk) {
            idCard?.classList.add('verified');
            if (idStamp) idStamp.textContent = 'Approved';
            idStamp?.classList.add('show');
        } else if (idBad) {
            idCard?.classList.add('rejected');
            if (idStamp) idStamp.textContent = 'Rejected';
            idStamp?.classList.add('show', 'rejected');
        }

        if (licenseOk) {
            licCard?.classList.add('verified');
            if (licStamp) licStamp.textContent = 'Approved';
            licStamp?.classList.add('show');
        } else if (licenseBad) {
            licCard?.classList.add('rejected');
            if (licStamp) licStamp.textContent = 'Rejected';
            licStamp?.classList.add('show', 'rejected');
        }

        setText('scanOp', activeRow?.label || 'Verification rejected');
        return;
    }

    if (allSuccess) {
        idCard?.classList.add('verified');
        licCard?.classList.add('verified');
        if (idStamp) idStamp.textContent = 'Approved';
        if (licStamp) licStamp.textContent = 'Approved';
        idStamp?.classList.add('show');
        licStamp?.classList.add('show');
        setText('scanOp', 'All checks passed - customer verified');
        return;
    }

    if (activeIndex <= 3) {
        idCard?.classList.add('scanning');
    } else {
        licCard?.classList.add('scanning');
    }
}

function updateScanDocumentText(result) {
    if (!result?.buyer) return;

    setText('idCitizen', result.citizenid || result.buyer);
    setText('idHolder', result.buyerName || `Player ${result.buyer}`);
    setText('idDob', result.dob || 'On file');
    setText('licId', result.licenseId || 'weaponlicense');
    setText('licStatus', 'Valid');
    setText('licRegistry', result.citizenid || 'Registered');
}

function defaultScanChecks(firstStatus = 'pending') {
    return [
        { label: 'Authenticating employee credentials', status: firstStatus },
        { label: 'Requesting customer consent', status: 'pending' },
        { label: 'Reading government ID metadata', status: 'pending' },
        { label: 'Matching ID holder to selected customer', status: 'pending' },
        { label: 'Reading weapon license certificate', status: 'pending' },
        { label: 'Verifying ID and license citizen match', status: 'pending' },
        { label: 'Checking license status flags', status: 'pending' },
        { label: 'Checking license expiration window', status: 'pending' },
        { label: 'Querying cs_license registry record', status: 'pending' },
        { label: 'Saving customer registry profile', status: 'pending' }
    ];
}

function renderChecklist() {
    const checklist = el('scanChecklist');
    const badge = el('scanBadge');
    checklist.innerHTML = '';

    const rows = state.lastScan?.checks || defaultScanChecks();

    let hasError = false;
    let allSuccess = true;
    let activeIndex = rows.findIndex((row) => row.status === 'processing');

    rows.forEach((row) => {
        if (row.status === 'error') hasError = true;
        if (row.status !== 'success') allSuccess = false;
    });

    if (activeIndex === -1) {
        activeIndex = rows.findIndex((row) => row.status === 'error');
    }

    if (activeIndex === -1) {
        activeIndex = rows.findIndex((row) => row.status !== 'success');
    }

    if (activeIndex === -1) {
        activeIndex = rows.length - 1;
    }

    const completed = rows.filter((row) => row.status === 'success').length;

    const processing = rows.some((row) => row.status === 'processing');
    badge.className = `badge ${hasError ? 'error badge-error' : allSuccess ? 'success badge-success' : processing ? 'warning badge-warning' : 'muted badge-muted'}`;
    badge.textContent = scanBadgeReason(rows, hasError, allSuccess, processing, activeIndex);

    updateScanVisuals(rows, hasError, allSuccess, activeIndex, completed);
}

function renderCatalog(target) {
    const container = el(target);
    container.innerHTML = '';

    const list = state.weapons;
    if (!state.quote) {
        container.innerHTML = '<div class="empty">No active verified session. Complete document verification before ordering a firearm.</div>';
        return;
    }

    if (!list.length) {
        container.innerHTML = '<div class="empty">No weapons configured</div>';
        return;
    }

    list.forEach((weapon) => {
        const q = quoteFor(weapon.item);
        const inCart = state.cart[weapon.item] !== null && state.cart[weapon.item] !== undefined;
        const selected = inCart;
        const disabled = !state.quote || !q?.canOrder;
        const limitReached = !inCart && cartItems().length >= Number(state.quote?.limits?.remaining || 0);
        const row = document.createElement('div');
        row.className = `weapon-row ${selected ? 'active' : ''} ${disabled || limitReached ? 'disabled' : ''}`;
        const imagePath = inventoryImage(weapon.item, weapon.image);

        row.innerHTML = `
            <div class="weapon-card__image">
                <img src="${imagePath}" alt="" onerror="this.onerror=null;this.src='nui://ox_inventory/web/images/WEAPON_PISTOL.png';">
            </div>
            <div class="weapon-card__body">
                <div class="weapon-card__top">
                    <div>
                        <strong>${escapeHtml(weapon.label)}</strong>
                        <span class="muted-line">${escapeHtml(weapon.item)}</span>
                    </div>
                    <span class="price">$${formatMoney(weapon.price)}</span>
                </div>
                <p>${escapeHtml(weapon.description || 'Licensed firearm available for regulated purchase and registration.')}</p>
                <div class="weapon-card__meta">
                    <span>Ammo: ${escapeHtml(weapon.ammo || 'Unknown')}</span>
                    <span>Processing: ${escapeHtml(weapon.waitLabel || waitLabel(weapon.waitSeconds))}</span>
                    ${q?.reasons?.length ? `<span>${escapeHtml(q.reasons.join(', '))}</span>` : ''}
                </div>
                ${inCart ? renderOrderOptions(weapon) : ''}
            </div>
        `;

        row.addEventListener('click', () => {
            if (disabled || limitReached) return;
            state.selectedWeapon = weapon.item;
            if (inCart) {
                delete state.cart[weapon.item];
                if (state.selectedWeapon === weapon.item) {
                    state.selectedWeapon = null;
                }
                post('previewWeapon', { model: null });
            } else {
                state.selectedWeapon = weapon.item;
                state.cart[weapon.item] = { weapon: weapon.item, ammoPackages: 0, package: 'standard', attachments: [] };
                if (state.activeTab === 'order') {
                    post('previewWeapon', { model: weapon.previewModel || weapon.item });
                }
            }
            renderCatalog('weaponCatalog');
            renderCheckout();
            updateActionButtons();
        });
        container.appendChild(row);
    });
}

function renderAmmoSelect(weapon) {
    const ammoCfg = state.quote?.ammo?.[weapon.ammo];
    if (!ammoCfg) return '';

    const current = Number(state.cart[weapon.item]?.ammoPackages || 0);
    let options = '';
    for (let i = 0; i <= Number(ammoCfg.maxPackages || 0); i++) {
        const label = i === 0 ? 'No ammo' : `${i} x ${ammoCfg.label} (${i * ammoCfg.count} rounds) +$${formatMoney(i * ammoCfg.price)}`;
        options += `<option value="${i}" ${i === current ? 'selected' : ''}>${escapeHtml(label)}</option>`;
    }

    return `
        <label class="ammo-select">
            <span>Ammo Package</span>
            <select data-ammo-for="${escapeHtml(weapon.item)}">${options}</select>
        </label>
    `;
}

function renderOrderOptions(weapon) {
    return `
        ${renderAmmoSelect(weapon)}
        ${renderPackageSelect(weapon)}
        ${renderAttachmentOptions(weapon)}
    `;
}

function renderPackageSelect(weapon) {
    if (!weapon.packages?.length) return '';

    const current = state.cart[weapon.item]?.package || weapon.packages[0]?.id || 'standard';
    const options = weapon.packages.map((pkg) => {
        const suffix = Number(pkg.price || 0) > 0 ? ` +$${formatMoney(pkg.price)}` : '';
        return `<option value="${escapeHtml(pkg.id)}" ${pkg.id === current ? 'selected' : ''}>${escapeHtml(pkg.label + suffix)}</option>`;
    }).join('');

    return `
        <label class="ammo-select">
            <span>Weapon Package</span>
            <select data-package-for="${escapeHtml(weapon.item)}">${options}</select>
        </label>
    `;
}

function renderAttachmentOptions(weapon) {
    if (!weapon.attachments?.length) return '';

    const entry = state.cart[weapon.item] || {};
    const included = packageAttachmentIds(weapon, entry);
    const selected = new Set((entry.attachments || []).map(String));
    const rows = weapon.attachments.map((attachment) => {
        const id = String(attachment.id);
        const isIncluded = included.has(id);
        const checked = isIncluded || selected.has(id);
        const price = isIncluded ? 'Included' : `+$${formatMoney(attachment.price)}`;

        return `
            <label class="attachment-row ${isIncluded ? 'included' : checked ? 'checked' : ''}">
                <input type="checkbox" data-attachment-for="${escapeHtml(weapon.item)}" value="${escapeHtml(id)}" ${checked ? 'checked' : ''} ${isIncluded ? 'disabled' : ''}>
                <span>
                    <strong>${escapeHtml(attachment.label)}</strong>
                    <small>${escapeHtml(attachment.description || attachment.item || '')}</small>
                </span>
                <b>${escapeHtml(price)}</b>
            </label>
        `;
    }).join('');

    return `
        <div class="attachment-options">
            <div class="attachment-options__title">Attachments</div>
            ${rows}
        </div>
    `;
}

function renderTradeInSelect() {
    const tradeIns = state.quote?.tradeIns || [];
    if (!tradeIns.length) return '';

    const options = [
        '<option value="">No trade-in credit</option>',
        ...tradeIns.map((trade) => {
            const selected = String(state.selectedTradeIn || '') === String(trade.slot);
            const serial = trade.serial ? ` | Serial ${trade.serial}` : '';
            const label = `${trade.label || trade.item}${serial} | $${formatMoney(trade.value)} credit`;
            return `<option value="${escapeHtml(trade.slot)}" ${selected ? 'selected' : ''}>${escapeHtml(label)}</option>`;
        })
    ].join('');

    const current = selectedTradeIn();

    return `
        <label class="ammo-select trade-in-select">
            <span>Trade-In Credit</span>
            <select data-trade-in>${options}</select>
            ${current ? `<small>${escapeHtml(current.reason || 'Trade credit selected')}</small>` : '<small>Optional. Credit is applied only if this order is submitted.</small>'}
        </label>
    `;
}

function renderCheckout() {
    const panel = el('checkoutPanel');
    const total = cartTotal();
    const weaponCount = cartItems().length;
    const accessoryCount = accessoryItems().length;
    const meleeCount = meleeItems().length;
    const remaining = Number(state.quote?.limits?.remaining || 0);

    if (!state.quote) {
        panel.innerHTML = state.mode === 'order'
            ? '<div class="empty">Verification required before firearm orders.</div>'
            : '<div class="empty">Use an order station after document verification to place an order.</div>';
        return;
    }

    panel.innerHTML = `
        <div class="checkout__summary">
            <strong>${escapeHtml(state.quote.buyerName || 'Verified Customer')}</strong>
            <span class="muted-line">Weapons: ${weaponCount}/${remaining} | Accessories: ${accessoryCount} | Melee: ${meleeCount}</span>
            <span class="muted-line">Bank: $${formatMoney(state.quote.balances?.bank)} | Cash: $${formatMoney(state.quote.balances?.cash)}</span>
            <span class="muted-line">Order total: $${formatMoney(total)}${tradeInCredit() > 0 ? ` | Trade credit: -$${formatMoney(tradeInCredit())}` : ''}</span>
            <span class="muted-line">Amount due: $${formatMoney(orderAmountDue())}</span>
        </div>
        ${renderTradeInSelect()}
        <div class="payment-options">
            <button class="${state.paymentMethod === 'bank' ? 'active' : ''}" data-payment="bank" ${canUsePayment('bank') ? '' : 'disabled'}>Bank</button>
            <button class="${state.paymentMethod === 'cash' ? 'active' : ''}" data-payment="cash" ${canUsePayment('cash') ? '' : 'disabled'}>Cash</button>
        </div>
    `;

    panel.querySelectorAll('[data-payment]').forEach((button) => {
        button.addEventListener('click', () => {
            state.paymentMethod = button.dataset.payment;
            renderCheckout();
            updateActionButtons();
        });
    });

    panel.querySelector('[data-trade-in]')?.addEventListener('change', (event) => {
        state.selectedTradeIn = event.target.value || null;
        if (state.paymentMethod && !canUsePayment(state.paymentMethod)) {
            state.paymentMethod = null;
        }
        renderCheckout();
        updateActionButtons();
    });

    document.querySelectorAll('.ammo-select, .attachment-options').forEach((control) => {
        control.addEventListener('click', (event) => event.stopPropagation());
    });

    document.querySelectorAll('[data-ammo-for]').forEach((select) => {
        select.addEventListener('click', (event) => event.stopPropagation());
        select.addEventListener('change', (event) => {
            const item = event.target.dataset.ammoFor;
            if (state.cart[item]) {
                state.cart[item].ammoPackages = Number(event.target.value || 0);
                if (state.paymentMethod && !canUsePayment(state.paymentMethod)) {
                    state.paymentMethod = null;
                }
                renderCheckout();
                updateActionButtons();
            }
        });
    });

    document.querySelectorAll('[data-package-for]').forEach((select) => {
        select.addEventListener('click', (event) => event.stopPropagation());
        select.addEventListener('change', (event) => {
            const item = event.target.dataset.packageFor;
            if (state.cart[item]) {
                state.cart[item].package = event.target.value;
                if (state.paymentMethod && !canUsePayment(state.paymentMethod)) {
                    state.paymentMethod = null;
                }
                renderCatalog('weaponCatalog', false);
                renderCheckout();
                updateActionButtons();
            }
        });
    });

    document.querySelectorAll('[data-attachment-for]').forEach((checkbox) => {
        checkbox.addEventListener('click', (event) => event.stopPropagation());
        checkbox.addEventListener('change', (event) => {
            const item = event.target.dataset.attachmentFor;
            const value = event.target.value;
            if (!state.cart[item]) return;

            const selected = new Set((state.cart[item].attachments || []).map(String));
            if (event.target.checked) {
                selected.add(value);
            } else {
                selected.delete(value);
            }
            state.cart[item].attachments = Array.from(selected);

            if (state.paymentMethod && !canUsePayment(state.paymentMethod)) {
                state.paymentMethod = null;
            }
            renderCatalog('weaponCatalog', false);
            renderCheckout();
            updateActionButtons();
        });
    });
}

function renderAccessoryCatalog() {
    const container = el('accessoryCatalog');
    if (!container) return;

    container.innerHTML = '';

    if (!state.quote) {
        container.innerHTML = '<div class="empty">No active verified session. Complete document verification before buying accessories.</div>';
        return;
    }

    const ammo = state.quote.ammo || {};
    const attachments = state.quote.attachments || [];
    const entries = Object.entries(ammo);
    if (!entries.length && !attachments.length) {
        container.innerHTML = '<div class="empty">No accessory items configured</div>';
        return;
    }

    if (entries.length) {
        const heading = document.createElement('div');
        heading.className = 'catalog-heading';
        heading.textContent = 'Ammunition';
        container.appendChild(heading);
    }

    entries.forEach(([item, cfg]) => {
        const current = Number(state.accessoryCart[`ammo:${item}`]?.packages || 0);
        const row = document.createElement('div');
        row.className = `weapon-row accessory-card ${current > 0 ? 'active' : ''}`;
        const imagePath = inventoryImage(item, cfg.image);
        let options = '';

        for (let i = 0; i <= Number(cfg.maxPackages || 0); i++) {
            const label = i === 0 ? 'None' : `${i} package${i > 1 ? 's' : ''} (${i * Number(cfg.count || 0)} rounds) - $${formatMoney(i * Number(cfg.price || 0))}`;
            options += `<option value="${i}" ${i === current ? 'selected' : ''}>${escapeHtml(label)}</option>`;
        }

        row.innerHTML = `
            <div class="weapon-card__image">
                <img src="${imagePath}" alt="" onerror="this.onerror=null;this.src='nui://ox_inventory/web/images/WEAPON_PISTOL.png';">
            </div>
            <div class="weapon-card__body">
                <div class="weapon-card__top">
                    <div>
                        <strong>${escapeHtml(cfg.label || item)}</strong>
                        <span class="muted-line">${escapeHtml(item)}</span>
                    </div>
                    <span class="price">$${formatMoney(cfg.price)}</span>
                </div>
                <p>${escapeHtml(cfg.description || 'Verified ammunition available for licensed firearm customers.')}</p>
                <div class="weapon-card__meta">
                    <span>Ammo</span>
                    <span>${escapeHtml(cfg.count || 0)} rounds/package</span>
                    <span>Max ${escapeHtml(cfg.maxPackages || 0)} packages</span>
                </div>
                <label class="ammo-select">
                    <span>Quantity</span>
                    <select data-accessory-ammo="${escapeHtml(item)}">${options}</select>
                </label>
            </div>
        `;

        container.appendChild(row);
    });

    if (attachments.length) {
        const heading = document.createElement('div');
        heading.className = 'catalog-heading';
        heading.textContent = 'Weapon Attachments';
        container.appendChild(heading);
    }

    attachments.forEach((attachment) => {
        const key = `attachment:${attachment.item}`;
        const selected = Boolean(state.accessoryCart[key]);
        const compatibleWeapons = attachment.compatibleWeapons || [];
        const compatible = compatibleWeapons.map((weapon) => {
            const status = weapon.owned ? 'Owned' : weapon.pending ? 'Pending order' : 'Required';
            return `${weapon.label || weapon.item} (${status})`;
        }).join(', ');
        const compatibleCount = compatibleWeapons.length;
        const eligibleCount = compatibleWeapons.filter((weapon) => weapon.owned || weapon.pending).length;
        const row = document.createElement('div');
        row.className = `weapon-row accessory-card ${selected ? 'active' : ''} ${attachment.canBuy ? '' : 'disabled'}`;
        const imagePath = inventoryImage(attachment.item, attachment.image);
        row.innerHTML = `
            <div class="weapon-card__image">
                <img src="${imagePath}" alt="" onerror="this.onerror=null;this.src='nui://ox_inventory/web/images/WEAPON_PISTOL.png';">
            </div>
            <div class="weapon-card__body">
                <div class="weapon-card__top">
                    <div>
                        <strong>${escapeHtml(attachment.label || attachment.item)}</strong>
                        <span class="muted-line">${escapeHtml(attachment.item)}</span>
                    </div>
                    <span class="price">$${formatMoney(attachment.price)}</span>
                </div>
                <p>${escapeHtml(attachment.description || 'Physical attachment item for compatible registered firearms.')}</p>
                <div class="weapon-card__meta">
                    <span>Attachment</span>
                    <span>${escapeHtml(attachment.canBuy ? 'Eligible' : 'Restricted')}</span>
                    <span>${eligibleCount}/${compatibleCount} weapons ready</span>
                </div>
                <span class="muted-line">Compatible with: ${escapeHtml(compatible || 'No configured weapons')}</span>
                ${attachment.reasons?.length ? `<span class="muted-line">${escapeHtml(attachment.reasons.join(', '))}</span>` : ''}
            </div>
        `;

        row.addEventListener('click', () => {
            if (!attachment.canBuy) return;

            if (selected) {
                delete state.accessoryCart[key];
            } else {
                state.accessoryCart[key] = { type: 'attachment', item: attachment.item };
            }

            if (state.paymentMethod && !canUsePayment(state.paymentMethod)) {
                state.paymentMethod = null;
            }

            renderAccessoryCatalog();
            renderCheckout();
            updateActionButtons();
        });

        container.appendChild(row);
    });

    document.querySelectorAll('[data-accessory-ammo]').forEach((select) => {
        select.addEventListener('change', (event) => {
            const item = event.target.dataset.accessoryAmmo;
            const key = `ammo:${item}`;
            const packages = Number(event.target.value || 0);

            if (packages > 0) {
                state.accessoryCart[key] = { type: 'ammo', item, packages };
            } else {
                delete state.accessoryCart[key];
            }

            if (state.paymentMethod && !canUsePayment(state.paymentMethod)) {
                state.paymentMethod = null;
            }

            renderAccessoryCatalog();
            renderCheckout();
            updateActionButtons();
        });
    });
}

function renderAccessoryCheckout() {
    const panel = el('accessoryCheckoutPanel');
    if (!panel) return;
    panel.innerHTML = '';
}

function renderMeleeCatalog() {
    const container = el('meleeCatalog');
    if (!container) return;

    container.innerHTML = '';

    if (!state.quote) {
        container.innerHTML = '<div class="empty">No active verified session. Complete document verification before buying melee items.</div>';
        return;
    }

    const entries = state.quote.melee || [];
    if (!entries.length) {
        container.innerHTML = '<div class="empty">No melee items configured.</div>';
        return;
    }

    entries.forEach((item) => {
        const selected = Boolean(state.meleeCart[item.item]);
        const row = document.createElement('div');
        row.className = `weapon-row melee-card ${selected ? 'active' : ''}`;
        const imagePath = inventoryImage(item.item, item.image);
        row.innerHTML = `
            <div class="weapon-card__image">
                <img src="${imagePath}" alt="" onerror="this.onerror=null;this.src='nui://ox_inventory/web/images/WEAPON_PISTOL.png';">
            </div>
            <div class="weapon-card__body">
                <div class="weapon-card__top">
                    <div>
                        <strong>${escapeHtml(item.label || item.item)}</strong>
                        <span class="muted-line">${escapeHtml(item.item)}</span>
                    </div>
                    <span class="price">$${formatMoney(item.price)}</span>
                </div>
                <p>${escapeHtml(item.description || 'Legal melee item available after customer verification.')}</p>
                <div class="weapon-card__meta">
                    <span>Melee</span>
                    <span>Reduced damage</span>
                    <span>Registry sale</span>
                </div>
            </div>
        `;

        row.addEventListener('click', () => {
            if (selected) {
                delete state.meleeCart[item.item];
                if (meleeItems().length <= 0) {
                    post('previewWeapon', { model: null });
                }
            } else {
                state.meleeCart[item.item] = { item: item.item };
                post('previewWeapon', { model: item.previewModel || item.item });
            }

            if (state.paymentMethod && !canUsePayment(state.paymentMethod)) {
                state.paymentMethod = null;
            }

            renderMeleeCatalog();
            renderCheckout();
            updateActionButtons();
        });

        container.appendChild(row);
    });
}

function renderMeleeCheckout() {
    const panel = el('meleeCheckoutPanel');
    if (!panel) return;
    panel.innerHTML = '';
}

function renderAssemblyOrders() {
    const container = el('assemblyOrders');
    if (!container) return;

    container.innerHTML = '';

    if (!state.assemblyOrders.length) {
        container.innerHTML = '<div class="empty">No weapon orders are waiting for assembly.</div>';
        return;
    }

    state.assemblyOrders.forEach((order) => {
        const row = document.createElement('div');
        row.className = 'order-row assembly-order';
        const parts = Array.isArray(order.parts) ? order.parts : [];
        const partRows = parts.map((part) => {
            return `<span class="assembly-part ${part.has ? 'ok' : 'missing'}">${escapeHtml(part.label || part.item)} ${escapeHtml(part.available || 0)}/${escapeHtml(part.count || 1)}</span>`;
        }).join('');

        row.innerHTML = `
            <strong>${escapeHtml(order.weapon_label)}</strong>
            <span class="muted-line">Order #${order.id} | ${escapeHtml(order.buyer_name || order.buyer_identifier || 'Unknown Buyer')}</span>
            <div class="assembly-parts">${partRows}</div>
            <button data-assemble-order="${order.id}" ${order.has_parts ? '' : 'disabled'}>${order.has_parts ? 'Assemble Order' : 'Missing Parts'}</button>
        `;

        const button = row.querySelector('[data-assemble-order]');
        if (button) {
            button.addEventListener('click', () => {
                button.disabled = true;
                button.textContent = 'Assembling...';
                post('assembleOrder', { orderId: order.id }).then(() => refreshAssemblyOrders());
            });
        }

        container.appendChild(row);
    });
}

function stockKitForFilter() {
    if (!state.stockWeaponFilter || state.stockWeaponFilter === 'all') return null;
    return (state.partsOrdering?.weaponKits || []).find((kit) => kit.item === state.stockWeaponFilter) || null;
}

function renderStockFilter(container) {
    const kits = state.partsOrdering?.weaponKits || [];
    if (!kits.length) return;

    const selectedKit = stockKitForFilter();
    const wrapper = document.createElement('div');
    wrapper.className = 'stock-filter';
    wrapper.innerHTML = `
        <div class="stock-filter__head">
            <div>
                <strong>Stock View</strong>
                <span>${selectedKit ? `Showing parts for ${escapeHtml(selectedKit.label)}` : 'Showing all supplier parts'}</span>
            </div>
            <select data-stock-weapon-filter>
                <option value="all" ${state.stockWeaponFilter === 'all' ? 'selected' : ''}>All Parts</option>
                ${kits.map((kit) => `<option value="${escapeHtml(kit.item)}" ${state.stockWeaponFilter === kit.item ? 'selected' : ''}>${escapeHtml(kit.label)}</option>`).join('')}
            </select>
        </div>
        ${selectedKit ? `
            <div class="stock-kit">
                <div class="stock-kit__image">
                    <img src="${inventoryImage(selectedKit.item, selectedKit.image)}" alt="" onerror="this.onerror=null;this.src='nui://ox_inventory/web/images/WEAPON_PISTOL.png';">
                </div>
                <div>
                    <strong>${escapeHtml(selectedKit.label)} Build Kit</strong>
                    <span class="muted-line">${selectedKit.parts.length} required part type(s) | One-build parts cost $${formatMoney(selectedKit.total)}</span>
                </div>
                <button type="button" data-add-stock-kit="${escapeHtml(selectedKit.item)}">Add One Build Kit</button>
            </div>
        ` : ''}
    `;

    wrapper.querySelector('[data-stock-weapon-filter]')?.addEventListener('change', (event) => {
        state.stockWeaponFilter = event.target.value || 'all';
        renderPartsCatalog();
    });

    wrapper.querySelector('[data-add-stock-kit]')?.addEventListener('click', () => {
        const kit = stockKitForFilter();
        if (!kit) return;

        kit.parts.forEach((part) => {
            const current = state.partsCart[part.item] || { item: part.item, packages: 0, packageUnits: part.packageUnits };
            const samePackage = Number(current.packageUnits || 0) === Number(part.packageUnits || 0);
            const packages = Math.min(10, (samePackage ? Number(current.packages || 0) : 0) + Number(part.packages || 1));
            state.partsCart[part.item] = { item: part.item, packages, packageUnits: part.packageUnits };
        });

        renderPartsCatalog();
        renderPartsCheckout();
        updateActionButtons();
    });

    container.appendChild(wrapper);
}

function renderPartsCatalog() {
    const container = el('partsCatalog');
    if (!container) return;

    container.innerHTML = '';

    if (!state.partsOrdering?.allowed) {
        container.innerHTML = '<div class="empty">You are not authorized to place store stock orders.</div>';
        return;
    }

    renderStockFilter(container);

    const kit = stockKitForFilter();
    const kitItems = new Set((kit?.parts || []).map((part) => part.item));
    const catalog = (state.partsOrdering.catalog || []).filter((part) => !kit || kitItems.has(part.item));
    if (!catalog.length) {
        container.insertAdjacentHTML('beforeend', '<div class="empty">No stock parts are configured for this view.</div>');
        return;
    }

    catalog.forEach((part) => {
        const entry = state.partsCart[part.item] || { item: part.item, packages: 0 };
        const packageOptions = stockPackageOptions(part);
        const selectedPackage = selectedStockPackage(part, entry);
        const packages = Number(entry.packages || 0);
        const units = packages * Number(selectedPackage.units || 1);
        const lineTotal = packages * Number(selectedPackage.price || 0);
        const kitPart = kit?.parts?.find((candidate) => candidate.item === part.item);
        const imagePath = inventoryImage(part.item, part.image || 'WEAPON_PISTOL.png');
        const row = document.createElement('div');
        row.className = `stock-card ${packages > 0 ? 'selected' : ''}`;
        row.innerHTML = `
            <div class="stock-card__head">
                <div class="stock-card__image">
                    <img src="${imagePath}" alt="" onerror="this.onerror=null;this.src='nui://ox_inventory/web/images/WEAPON_PISTOL.png';">
                </div>
                <div class="stock-card__main">
                    <div>
                        <strong>${escapeHtml(part.label)}</strong>
                        <span class="stock-card__sub">Supplier package / store inventory</span>
                    </div>
                    <span class="stock-card__price">$${formatMoney(selectedPackage.price)}</span>
                </div>
            </div>
            <div class="stock-card__meta">
                <span>${escapeHtml(selectedPackage.units || 1)} units / package</span>
                ${kitPart ? `<span>${escapeHtml(kitPart.count)} required / build</span>` : ''}
                <span>${packages > 0 ? `${units} units selected` : 'No packages selected'}</span>
                <span>${lineTotal > 0 ? `$${formatMoney(lineTotal)} line total` : 'Awaiting quantity'}</span>
            </div>
            <label class="stock-card__package">
                <span>Package Size</span>
                <select data-part-package-units="${escapeHtml(part.item)}">
                    ${packageOptions.map((option) => `<option value="${Number(option.units)}" ${Number(selectedPackage.units) === Number(option.units) ? 'selected' : ''}>${escapeHtml(option.label || `${option.units} Units`)} - $${formatMoney(option.price)}</option>`).join('')}
                </select>
            </label>
            <div class="stock-card__control">
                <span>Packages</span>
                <div class="stock-stepper">
                    <button type="button" data-part-step="${escapeHtml(part.item)}" data-delta="-1">-</button>
                    <select data-part-packages="${escapeHtml(part.item)}">
                        ${Array.from({ length: 11 }, (_, index) => `<option value="${index}" ${Number(entry.packages) === index ? 'selected' : ''}>${index}</option>`).join('')}
                    </select>
                    <button type="button" data-part-step="${escapeHtml(part.item)}" data-delta="1">+</button>
                </div>
            </div>
        `;

        const select = row.querySelector('[data-part-packages]');
        const packageSelect = row.querySelector('[data-part-package-units]');
        const setEntry = (packageValue, packageUnits) => {
            packageUnits = Number(packageUnits || selectedPackage.units || 1);
            const packages = Math.max(0, Math.min(10, Number(packageValue || 0)));
            if (packages > 0) {
                state.partsCart[part.item] = { item: part.item, packages, packageUnits };
            } else {
                delete state.partsCart[part.item];
            }
            renderPartsCatalog();
            renderPartsCheckout();
            updateActionButtons();
        };

        select.addEventListener('change', () => {
            setEntry(select.value, packageSelect.value);
        });

        packageSelect.addEventListener('change', () => {
            setEntry(select.value, packageSelect.value);
        });

        row.querySelectorAll('[data-part-step]').forEach((button) => {
            button.addEventListener('click', () => {
                setEntry(Number(select.value || 0) + Number(button.dataset.delta || 0), packageSelect.value);
            });
        });

        container.appendChild(row);
    });
}

function renderPartsCheckout() {
    const panel = el('partsCheckoutPanel');
    if (!panel) return;

    const total = partsTotal();
    const items = partsItems();
    const balances = state.partsOrdering?.balances || {};
    const sources = state.partsOrdering?.paymentSources || {};

    panel.innerHTML = `
        <div class="checkout__summary">
            <strong>Stock Cart</strong>
            <span class="muted-line">${items.length ? `${items.length} part type(s) selected` : 'No parts selected'}</span>
            <span class="muted-line">Total: $${formatMoney(total)}</span>
            <span class="muted-line">Parts deliver directly to store storage.</span>
        </div>
        <div class="payment-options parts-payment">
            ${sources.society ? `<button data-parts-payment="society" class="${state.partsPaymentSource === 'society' ? 'active' : ''}" ${Number(balances.society || 0) >= total && total > 0 ? '' : 'disabled'}>Society $${formatMoney(balances.society)}</button>` : ''}
            ${sources.bank ? `<button data-parts-payment="bank" class="${state.partsPaymentSource === 'bank' ? 'active' : ''}" ${Number(balances.bank || 0) >= total && total > 0 ? '' : 'disabled'}>Bank $${formatMoney(balances.bank)}</button>` : ''}
            ${sources.cash ? `<button data-parts-payment="cash" class="${state.partsPaymentSource === 'cash' ? 'active' : ''}" ${Number(balances.cash || 0) >= total && total > 0 ? '' : 'disabled'}>Cash $${formatMoney(balances.cash)}</button>` : ''}
        </div>
    `;

    panel.querySelectorAll('[data-parts-payment]').forEach((button) => {
        button.addEventListener('click', () => {
            state.partsPaymentSource = button.dataset.partsPayment;
            renderPartsCheckout();
            updateActionButtons();
        });
    });
}

function renderPartsOrders() {
    const container = el('partsOrders');
    if (!container) return;

    container.innerHTML = '';
    const orders = state.partsOrdering?.orders || [];

    if (!orders.length) {
        container.innerHTML = '<div class="empty">No recent stock orders found.</div>';
        return;
    }

    orders.forEach((order) => {
        const row = document.createElement('div');
        row.className = 'order-row';
        const status = formatStatus(order.status);
        const remaining = order.status === 'pending_delivery' ? formatRemaining(order.remaining_seconds, 'approved') : 'Delivered';
        const items = Array.isArray(order.items) ? order.items.map((item) => `${item.label || item.item} x${item.count}`).join(', ') : '';
        const canExpedite = order.status === 'pending_delivery' && Number(order.remaining_seconds || 0) > 30;
        const expediteFee = Math.max(1, Math.floor(Number(order.total || 0) * 0.07));
        row.innerHTML = `
            <strong>Stock Order #${escapeHtml(order.id)}</strong>
            <span class="muted-line">${escapeHtml(status)} | ${escapeHtml(remaining)} | ${escapeHtml(order.payment_source || 'unknown')}</span>
            <span class="muted-line">Employee: ${escapeHtml(order.employee_name || 'Unknown')}</span>
            <span class="muted-line">$${formatMoney(order.total)}${items ? ` | ${escapeHtml(items)}` : ''}</span>
            ${canExpedite ? `<button data-expedite-parts="${order.id}">Expedite Shipping - $${formatMoney(expediteFee)}</button>` : ''}
        `;
        const button = row.querySelector('[data-expedite-parts]');
        if (button) {
            button.addEventListener('click', async () => {
                const confirmed = await showConfirmPrompt({
                    eyebrow: 'Supplier Freight',
                    title: 'Expedited Shipping',
                    primary: `Order #${order.id}`,
                    secondary: `$${formatMoney(expediteFee)}`,
                    secure: '30 Sec ETA',
                    html: `
                        <strong>Confirm expedited freight?</strong>
                        <span>This will charge <b>$${formatMoney(expediteFee)}</b> to the original payment source: <b>${escapeHtml(formatStatus(order.payment_source || 'unknown'))}</b>.</span>
                        <span>Delivery time will be reduced to approximately 30 seconds.</span>
                    `
                });

                if (!confirmed) return;
                button.disabled = true;
                button.textContent = 'Expediting...';
                post('expeditePartsOrder', { orderId: order.id }).then(() => refreshPartsOrdering());
            });
        }
        container.appendChild(row);
    });
}

function renderPickupOrders() {
    const container = el('pickupOrders');
    container.innerHTML = '';

    if (!state.orders.length) {
        container.innerHTML = '<div class="empty">No active pickup orders found</div>';
        return;
    }

    state.orders.forEach((order) => {
        const row = document.createElement('div');
        row.className = 'order-row';
        const ready = order.status === 'ready';
        const countdown = formatRemaining(order.remaining_seconds, order.status);
        const attachments = orderAttachmentLabels(order);
        const isItem = order.order_type === 'item';
        const releaseLabel = isItem ? 'Release Pickup Item' : 'Release Registered Firearm';
        const itemLine = isItem
            ? `${escapeHtml(formatStatus(order.item_type || 'item'))} x${escapeHtml(order.count || order.ammo_count || 1)}`
            : `$${formatMoney(order.price)}${order.ammo_count > 0 ? ` | Ammo: ${escapeHtml(order.ammo_item)} x${escapeHtml(order.ammo_count)}` : ''}`;
        row.innerHTML = `
            <strong>${escapeHtml(order.weapon_label)}</strong>
            <span class="muted-line">Order #${order.id} | ${escapeHtml(formatStatus(order.status))} | ${escapeHtml(countdown)}</span>
            <span class="muted-line">${itemLine}</span>
            ${attachments.length ? `<span class="muted-line">Attachments: ${escapeHtml(attachments.join(', '))}</span>` : ''}
            ${ready ? `<button data-order="${order.id}">${releaseLabel}</button>` : `<span class="pickup-wait">${order.status === 'pending_assembly' ? 'Awaiting assembly' : 'Processing clearance'}</span>`}
        `;
        const button = row.querySelector('button');
        if (button) {
            button.addEventListener('click', () => post('pickupOrder', { orderId: order.id }).then(refreshPickup));
        }
        container.appendChild(row);
    });
}

function renderOrderRows(target, orders, includeSerial, allowRefund = false) {
    const container = el(target);
    container.innerHTML = '';

    if (!orders || !orders.length) {
        container.innerHTML = '<div class="empty">No orders found</div>';
        return;
    }

    orders.forEach((order) => {
        const row = document.createElement('div');
        row.className = 'order-row';
        const countdown = formatRemaining(order.remaining_seconds, order.status);
        const attachments = orderAttachmentLabels(order);
        const buyerLine = order.buyer_name || order.buyer_identifier ? `<span class="muted-line">Buyer: ${escapeHtml(order.buyer_name || order.buyer_identifier)}</span>` : '';
        row.innerHTML = `
            <strong>${escapeHtml(order.weapon_label)}</strong>
            ${buyerLine}
            <span class="muted-line">Order #${order.id} | ${escapeHtml(formatStatus(order.status))} | ${escapeHtml(countdown)}</span>
            <span class="muted-line">$${formatMoney(order.price)}${includeSerial && order.serial ? ` | Serial ${escapeHtml(order.serial)}` : ''}</span>
            ${attachments.length ? `<span class="muted-line">Attachments: ${escapeHtml(attachments.join(', '))}</span>` : ''}
            ${allowRefund ? `<div class="order-actions"><button class="refund-btn" data-refund-order="${order.id}">Refund Order</button><button class="clear-btn" data-clear-order="${order.id}">Clear Order</button></div>` : ''}
        `;
        const refund = row.querySelector('[data-refund-order]');
        if (refund) {
            refund.addEventListener('click', () => {
                refund.disabled = true;
                refund.textContent = 'Refunding...';
                post('refundActiveOrder', { orderId: order.id }).then(() => loadActiveOrders());
            });
        }
        const clear = row.querySelector('[data-clear-order]');
        if (clear) {
            clear.addEventListener('click', () => {
                clear.disabled = true;
                clear.textContent = 'Clearing...';
                post('clearActiveOrder', { orderId: order.id }).then(() => loadActiveOrders());
            });
        }
        container.appendChild(row);
    });
}

function renderProfile() {
    const card = el('profileCard');
    const profileOrders = el('profileOrders');
    const data = state.profile;

    if (!data) {
        card.innerHTML = '<div class="empty">Load a customer profile to view saved documents and history</div>';
        profileOrders.innerHTML = '';
        return;
    }

    const profile = data.profile || {};
    const licenseStatus = profile.license_status || 'unknown';
    card.innerHTML = `
        <div class="profile-grid">
            <div class="profile-row"><span>Name</span><strong>${escapeHtml(profile.full_name || data.currentName || 'No profile saved')}</strong></div>
            <div class="profile-row"><span>Citizen ID</span><strong>${escapeHtml(data.citizenid || profile.citizenid || '-')}</strong></div>
            <div class="profile-row"><span>DOB</span><strong>${escapeHtml(profile.dob || '-')}</strong></div>
            <div class="profile-row"><span>License</span><strong>Weapons License</strong><span class="muted-line">${escapeHtml(profile.license_id || '-')}</span></div>
            <div class="profile-row"><span>Status</span><strong class="profile-status ${statusClass(licenseStatus)}">${escapeHtml(formatStatus(licenseStatus))}</strong></div>
            <div class="profile-row"><span>Last Verified</span><strong>${escapeHtml(formatDateTime(profile.last_verified_at))}</strong></div>
        </div>
    `;

    renderOrderRows('profileOrders', data.orderHistory || [], true);
}

function render() {
    el('storeLabel').textContent = state.store?.label || '-';
    const employeeName = state.quote?.sellerName || state.employeeName;
    el('modeLabel').textContent = state.mode === 'sales' && employeeName ? employeeName : state.mode === 'order' ? 'Order Station' : state.mode === 'pickup' ? 'Secure Pickup' : state.mode === 'assembly' ? 'Assembly Station' : employeeName || 'Registry';
    const secureBadge = el('secureSessionBadge');
    const secureActive = Boolean(state.quote || state.verifiedBuyer);
    if (secureBadge) {
        secureBadge.classList.toggle('active', secureActive);
        secureBadge.textContent = secureActive ? 'Secure Session Active' : 'Secure Session';
    }

    renderCustomerPicker('scan', 'Customer');
    renderCustomerPicker('order', 'Verified Customer');
    renderCustomerPicker('active', 'Customer');
    renderCustomerPicker('profile', 'Customer');

    renderChecklist();
    renderCatalog('weaponCatalog');
    renderAccessoryCatalog();
    renderAccessoryCheckout();
    renderMeleeCatalog();
    renderMeleeCheckout();
    renderAssemblyOrders();
    renderPartsCatalog();
    renderPartsCheckout();
    renderPartsOrders();
    renderPickupOrders();
    renderOrderRows('activeOrders', state.activeOrders, false, state.mode === 'sales');
    renderProfile();
    renderCheckout();
    updateTabLocks();
    updateActionButtons();
}

function updateActionButtons() {
    const scanButton = document.querySelector('[data-action="scan"]');
    if (scanButton) {
        scanButton.disabled = state.scanning;
        scanButton.textContent = state.scanning ? 'Scanning Documents...' : 'Swipe Documents';
    }

    const orderButton = document.querySelector('[data-action="order"]');
    if (orderButton) {
        const orderTabActive = state.activeTab === 'order' || state.activeTab === 'accessories' || state.activeTab === 'melee';
        const ready = orderTabActive && cartTotal() > 0 && state.paymentMethod && canUsePayment(state.paymentMethod);
        orderButton.disabled = !ready;
        orderButton.textContent = ready ? 'Submit Secure Cart' : 'Select Items and Payment';
    }

    const accessoryButton = document.querySelector('[data-action="accessories"]');
    if (accessoryButton) {
        const ready = state.activeTab === 'accessories' && accessoryItems().length > 0 && state.accessoryPaymentMethod && canUseAccessoryPayment(state.accessoryPaymentMethod);
        accessoryButton.disabled = !ready;
        accessoryButton.textContent = ready ? 'Purchase Accessories' : 'Select Accessories and Payment';
    }

    const meleeButton = document.querySelector('[data-action="melee"]');
    if (meleeButton) {
        const ready = state.activeTab === 'melee' && meleeItems().length > 0 && state.meleePaymentMethod && canUseMeleePayment(state.meleePaymentMethod);
        meleeButton.disabled = !ready;
        meleeButton.textContent = ready ? 'Purchase Melee' : 'Select Melee and Payment';
    }

    const partsButton = document.querySelector('[data-action="parts"]');
    if (partsButton) {
        const ready = state.activeTab === 'stock' && partsItems().length > 0 && state.partsPaymentSource && canUsePartsPayment(state.partsPaymentSource);
        partsButton.disabled = !ready;
        partsButton.textContent = ready ? 'Submit Stock Order' : 'Select Parts and Payment';
    }
}

function refreshPickup() {
    return post('getReadyOrders').then((orders) => {
        state.orders = Array.isArray(orders) ? orders : [];
        renderPickupOrders();
    });
}

function refreshAssemblyOrders() {
    return post('getAssemblyOrders').then((orders) => {
        state.assemblyOrders = Array.isArray(orders) ? orders : [];
        renderAssemblyOrders();
    });
}

function refreshPartsOrdering() {
    return post('getPartsOrderingData').then((data) => {
        state.partsOrdering = data || { allowed: false, catalog: [], weaponKits: [], orders: [], paymentSources: {}, balances: {} };
        if (state.stockWeaponFilter !== 'all' && !(state.partsOrdering.weaponKits || []).some((kit) => kit.item === state.stockWeaponFilter)) {
            state.stockWeaponFilter = 'all';
        }
        renderPartsCatalog();
        renderPartsCheckout();
        renderPartsOrders();
        updateTabLocks();
        updateActionButtons();
    });
}

function loadActiveOrders() {
    const buyer = Number(state.selected.active);
    if (!buyer) return;

    return post('getActiveOrders', { buyer }).then((orders) => {
        state.activeOrders = Array.isArray(orders) ? orders : [];
        renderOrderRows('activeOrders', state.activeOrders, false, state.mode === 'sales');
    });
}

function loadProfile() {
    const buyer = Number(state.selected.profile);
    if (!buyer) return;

    return post('getCustomerProfile', { buyer }).then((profile) => {
        state.profile = profile || null;
        renderProfile();
    });
}

function refreshVerifiedCustomers() {
    return post('getVerifiedCustomers').then((buyers) => {
        if (Array.isArray(buyers)) {
            mergeBuyers(buyers);
            render();
        }
    });
}

function preloadCustomer(buyer) {
    state.selected.active = buyer;
    state.selected.profile = buyer;

    return Promise.all([
        loadActiveOrders(),
        loadProfile()
    ]);
}

function showConsentPrompt(data) {
    state.resource = data.resource || state.resource;
    state.consentResolved = false;
    if (state.consentCloseTimer) {
        clearTimeout(state.consentCloseTimer);
        state.consentCloseTimer = null;
    }
    setText('consentEmployee', data.employeeName || 'Employee');
    setText('consentStore', data.storeName || 'Gun Store');
    updateConsentTerminal('pending', 'Document scan consent pending', 'Approve this request only if you are completing a legal firearm purchase or document check.');
    document.querySelectorAll('[data-consent]').forEach((button) => {
        button.disabled = false;
    });
    consentPrompt?.classList.remove('hidden');
}

function hideConsentPrompt() {
    if (consentPrompt?.classList.contains('hidden')) return;
    consentPrompt?.classList.add('hidden');
    post('documentConsentClosed');
}

function updateConsentTerminal(status, counterText, operationText) {
    const cards = consentPrompt?.querySelectorAll('.doc-card') || [];
    const fill = consentPrompt?.querySelector('.consent-fill');

    cards.forEach((card) => {
        card.classList.remove('scanning', 'verified', 'rejected');
        const stamp = card.querySelector('.stamp');
        stamp?.classList.remove('show', 'rejected');
        if (status === 'approved') card.classList.add('verified');
        if (status === 'rejected' || status === 'declined') card.classList.add('rejected');
        if (status === 'pending' || status === 'processing') card.classList.add('scanning');
        if (status === 'approved' || status === 'rejected' || status === 'declined') {
            if (stamp) {
                stamp.textContent = status === 'approved' ? 'Approved' : 'Rejected';
                stamp.classList.add('show');
                if (status !== 'approved') stamp.classList.add('rejected');
            }
        }
    });

    const op = consentPrompt?.querySelector('.scan-status-op');
    const counter = consentPrompt?.querySelector('.scan-step-counter');
    if (op) op.textContent = operationText || '';
    if (counter) counter.textContent = counterText || '';
    if (fill) fill.style.width = status === 'approved' || status === 'rejected' || status === 'declined' ? '100%' : '55%';
}

function applyConsentCardState(type, status) {
    const card = consentPrompt?.querySelector(`[data-consent-card="${type}"]`);
    const stamp = consentPrompt?.querySelector(`[data-consent-stamp="${type}"]`);
    if (!card) return;

    card.classList.remove('scanning', 'verified', 'rejected');
    stamp?.classList.remove('show', 'rejected');

    if (status === 'approved') {
        card.classList.add('verified');
        if (stamp) {
            stamp.textContent = 'Approved';
            stamp.classList.add('show');
        }
        return;
    }

    if (status === 'rejected') {
        card.classList.add('rejected');
        if (stamp) {
            stamp.textContent = 'Rejected';
            stamp.classList.add('show', 'rejected');
        }
        return;
    }

    card.classList.add('scanning');
}

function consentDocumentStates(rows) {
    rows = Array.isArray(rows) ? rows : [];

    const idApproved = rows[2]?.status === 'success' && rows[3]?.status === 'success';
    const idRejected = rows[2]?.status === 'error' || rows[3]?.status === 'error';
    const idScanning = rows[2]?.status === 'processing' || rows[3]?.status === 'processing';

    const licenseApproved = rows[4]?.status === 'success'
        && rows[5]?.status === 'success'
        && rows[6]?.status === 'success'
        && rows[7]?.status === 'success'
        && rows[8]?.status === 'success';
    const licenseRejected = rows[4]?.status === 'error'
        || rows[5]?.status === 'error'
        || rows[6]?.status === 'error'
        || rows[7]?.status === 'error'
        || rows[8]?.status === 'error';
    const licenseScanning = rows[4]?.status === 'processing'
        || rows[5]?.status === 'processing'
        || rows[6]?.status === 'processing'
        || rows[7]?.status === 'processing'
        || rows[8]?.status === 'processing';

    return {
        id: idRejected ? 'rejected' : idApproved ? 'approved' : idScanning ? 'scanning' : 'scanning',
        license: licenseRejected ? 'rejected' : licenseApproved ? 'approved' : licenseScanning ? 'scanning' : 'scanning'
    };
}

function scheduleConsentClose(delay = 5000) {
    if (state.consentCloseTimer) clearTimeout(state.consentCloseTimer);
    state.consentCloseTimer = setTimeout(() => {
        hideConsentPrompt();
        state.consentCloseTimer = null;
    }, delay);
}

function updateConsentFromRows(rows) {
    if (consentPrompt?.classList.contains('hidden')) return;

    rows = Array.isArray(rows) ? rows : [];
    const hasError = rows.some((row) => row.status === 'error');
    const allSuccess = rows.length > 0 && rows.every((row) => row.status === 'success');
    const activeIndex = rows.findIndex((row) => row.status === 'processing');
    const completed = rows.filter((row) => row.status === 'success').length;
    const activeRow = rows[activeIndex] || rows.find((row) => row.status === 'error') || rows[completed] || rows[0];

    if (hasError) {
        updateConsentTerminal('rejected', 'Verification rejected', activeRow?.label || 'Registry verification failed.');
        const states = consentDocumentStates(rows);
        applyConsentCardState('id', states.id);
        applyConsentCardState('license', states.license);
        scheduleConsentClose(6500);
        return;
    }

    if (allSuccess) {
        updateConsentTerminal('approved', 'Cleared to shop', 'Verification approved. You may use the firearm order station.');
        applyConsentCardState('id', 'approved');
        applyConsentCardState('license', 'approved');
        scheduleConsentClose(6500);
        return;
    }

    updateConsentTerminal('processing', `${Math.min(Math.max(completed, activeIndex + 1), rows.length)} / ${rows.length} checks complete`, activeRow?.label || 'Registry scan in progress.');
    const states = consentDocumentStates(rows);
    applyConsentCardState('id', states.id);
    applyConsentCardState('license', states.license);
}

document.querySelectorAll('[data-consent]').forEach((button) => {
    button.addEventListener('click', () => {
        if (state.consentResolved) return;
        const approved = button.dataset.consent === 'approve';
        state.consentResolved = true;
        document.querySelectorAll('[data-consent]').forEach((control) => {
            control.disabled = true;
        });
        if (approved) {
            updateConsentTerminal('processing', 'Consent accepted', 'Consent accepted. Waiting for registry scan.');
        } else {
            updateConsentTerminal('declined', 'Consent declined', 'Document scan request declined.');
            scheduleConsentClose(3500);
        }
        post('documentConsentResponse', { approved });
    });
});

el('confirmCancel')?.addEventListener('click', () => resolveConfirmPrompt(false));
el('confirmApprove')?.addEventListener('click', () => resolveConfirmPrompt(true));

document.querySelectorAll('.tab').forEach((button) => {
    button.addEventListener('click', () => {
        if (button.classList.contains('locked')) return;
        setTab(button.dataset.tab);
        if (button.dataset.tab === 'pickup') refreshPickup();
        if (button.dataset.tab === 'assembly') refreshAssemblyOrders();
        if (button.dataset.tab === 'stock') refreshPartsOrdering();
        if (button.dataset.tab === 'active') loadActiveOrders();
        if (button.dataset.tab === 'profile') loadProfile();
    });
});

document.querySelectorAll('[data-action]').forEach((button) => {
    button.addEventListener('click', () => {
        const action = button.dataset.action;

        if (action === 'close') {
            state.cart = {};
            state.accessoryCart = {};
            state.meleeCart = {};
            state.selectedTradeIn = null;
            state.paymentMethod = null;
            post('previewWeapon', { model: null });
            post('close');
            setVisible(false);
            return;
        }

        if (action === 'scan') {
            const buyer = Number(state.selected.scan);
            if (!buyer) return;
            state.scanning = true;
            resetScanDocuments();
            state.lastScan = {
                checks: defaultScanChecks('processing')
            };
            render();
            post('scanDocuments', { buyer }).then((result) => {
                state.scanning = false;
                if (result?.checks) {
                    state.lastScan = result;
                }
                if (result?.buyer) {
                    updateScanDocumentText(result);
                    mergeBuyers([{
                        label: `Verified - ${result.buyerName || `Player ${result.buyer}`} (${result.citizenid || result.buyer})`,
                        value: result.buyer,
                        verified: true,
                        citizenid: result.citizenid,
                        buyerName: result.buyerName,
                        licenseId: result.licenseId
                    }]);
                    state.selected.scan = result.buyer;
                    state.selected.order = result.buyer;
                    state.selected.active = result.buyer;
                    state.selected.profile = result.buyer;
                    state.verifiedBuyer = result.buyer;
                    state.cart = {};
                    state.accessoryCart = {};
                    state.meleeCart = {};
                    state.selectedTradeIn = null;
                    state.paymentMethod = null;
                    state.accessoryPaymentMethod = null;
                    state.meleePaymentMethod = null;
                    refreshVerifiedCustomers();
                    preloadCustomer(result.buyer);
                    refreshQuote();
                }
                render();
            });
        }

        if (action === 'order') {
            const buyer = Number(state.verifiedBuyer || state.quote?.buyer);
            if (!buyer || cartTotal() <= 0 || !state.paymentMethod || !canUsePayment(state.paymentMethod)) return;

            const weaponCart = cartItems();
            const accessoryCart = accessoryItems();
            const meleeCart = meleeItems();
            const paymentMethod = state.paymentMethod;
            const trade = selectedTradeIn() ? { slot: selectedTradeIn().slot } : null;

            const submit = async () => {
                if (weaponCart.length > 0) {
                    const result = await post('createOrder', {
                        buyer,
                        cart: weaponCart,
                        paymentMethod,
                        tradeIn: trade
                    });
                    if (!result?.ok) return false;
                }

                if (accessoryCart.length > 0) {
                    const result = await post('purchaseAccessories', {
                        items: accessoryCart,
                        paymentMethod
                    });
                    if (!result?.ok) return false;
                }

                if (meleeCart.length > 0) {
                    const result = await post('purchaseMelee', {
                        items: meleeCart,
                        paymentMethod,
                        tradeIn: weaponCart.length > 0 ? null : trade
                    });
                    if (!result?.ok) return false;
                }

                return true;
            };

            submit().then((ok) => {
                if (!ok) return refreshQuote();
                state.selected.active = buyer;
                state.cart = {};
                state.accessoryCart = {};
                state.meleeCart = {};
                state.selectedTradeIn = null;
                state.paymentMethod = null;
                state.accessoryPaymentMethod = null;
                state.meleePaymentMethod = null;
                post('previewWeapon', { model: null });
                refreshQuote().then(() => {
                    if (Number(state.quote?.limits?.remaining || 0) > 0) {
                        setTab(state.activeTab === 'accessories' || state.activeTab === 'melee' ? state.activeTab : 'order');
                    } else {
                        state.verifiedBuyer = null;
                        setTab(state.mode === 'order' ? 'order' : 'scan');
                    }
                });
                loadActiveOrders();
            });
        }

        if (action === 'active') {
            loadActiveOrders();
        }

        if (action === 'profile') {
            loadProfile();
        }

        if (action === 'accessories') {
            if (accessoryItems().length === 0 || !state.accessoryPaymentMethod) return;
            post('purchaseAccessories', { items: accessoryItems(), paymentMethod: state.accessoryPaymentMethod }).then((result) => {
                if (!result?.ok) return refreshQuote();
                state.accessoryCart = {};
                state.accessoryPaymentMethod = null;
                refreshQuote().then(() => {
                    setTab('accessories');
                });
            });
        }

        if (action === 'melee') {
            if (meleeItems().length === 0 || !state.meleePaymentMethod) return;
            post('purchaseMelee', {
                items: meleeItems(),
                paymentMethod: state.meleePaymentMethod,
                tradeIn: selectedTradeIn() ? { slot: selectedTradeIn().slot } : null
            }).then((result) => {
                if (!result?.ok) return refreshQuote();
                state.meleeCart = {};
                state.selectedTradeIn = null;
                state.meleePaymentMethod = null;
                post('previewWeapon', { model: null });
                refreshQuote().then(() => {
                    setTab('melee');
                });
            });
        }

        if (action === 'parts') {
            if (partsItems().length === 0 || !state.partsPaymentSource) return;
            post('createPartsOrder', { cart: partsItems(), paymentSource: state.partsPaymentSource }).then((result) => {
                if (!result?.ok) return refreshPartsOrdering();
                state.partsCart = {};
                state.partsPaymentSource = null;
                refreshPartsOrdering();
            });
        }

    });
});

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.action === 'open') {
        state.resource = data.resource || state.resource;
        state.mode = data.mode || 'sales';
        state.store = data.store;
        state.employeeName = data.employeeName || null;
        state.buyers = data.buyers || [];
        state.weapons = data.weapons || [];
        state.orders = data.orders || [];
        state.assemblyOrders = data.assemblyOrders || [];
        state.partsOrdering = data.partsOrdering || { allowed: false, catalog: [], weaponKits: [], orders: [], paymentSources: {}, balances: {} };
        if (state.stockWeaponFilter !== 'all' && !(state.partsOrdering.weaponKits || []).some((kit) => kit.item === state.stockWeaponFilter)) {
            state.stockWeaponFilter = 'all';
        }
        state.activeOrders = [];
        state.profile = null;
        state.quote = data.quote || null;
        state.cart = {};
        state.accessoryCart = {};
        state.meleeCart = {};
        state.partsCart = {};
        state.selectedTradeIn = null;
        state.paymentMethod = null;
        state.accessoryPaymentMethod = null;
        state.meleePaymentMethod = null;
        state.partsPaymentSource = null;
        state.lastScan = null;
        state.scanning = false;
        state.verifiedBuyer = state.quote?.buyer || null;
        state.activeTab = 'scan';
        state.selectedWeapon = state.weapons[0]?.item || null;
        state.selected = { scan: null, order: null, active: null, profile: null };
        state.pickerQuery = { scan: '', order: '', active: '', profile: '' };

        const self = state.buyers.find((buyer) => buyer.self) || state.buyers[0];
        if (self) {
            state.selected.scan = self.value;
            state.selected.order = self.value;
            state.selected.active = self.value;
            state.selected.profile = self.value;
        }

        setVisible(true);
        resetScanDocuments();
        setTab(data.tab || (data.mode === 'pickup' ? 'pickup' : data.mode === 'assembly' ? 'assembly' : 'scan'));
        render();
    }

    if (data.action === 'close') {
        state.verifiedBuyer = null;
        state.scanning = false;
        state.cart = {};
        state.accessoryCart = {};
        state.meleeCart = {};
        state.selectedTradeIn = null;
        state.paymentMethod = null;
        hideConsentPrompt();
        resolveConfirmPrompt(false);
        setVisible(false);
    }

    if (data.action === 'documentConsentRequest') {
        showConsentPrompt(data);
    }

    if (data.action === 'documentConsentClose') {
        hideConsentPrompt();
    }

    if (data.action === 'documentConsentProgress') {
        updateConsentFromRows(data.checks || []);
    }

    if (data.action === 'scanProgress') {
        state.lastScan = { checks: data.checks || [] };
        renderChecklist();

        const scanButton = document.querySelector('[data-action="scan"]');
        if (scanButton) {
            scanButton.disabled = state.scanning;
            scanButton.textContent = state.scanning ? 'Scanning Documents...' : 'Swipe Documents';
        }
    }
});

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && !consentPrompt?.classList.contains('hidden')) {
        hideConsentPrompt();
        post('documentConsentResponse', { approved: false });
        return;
    }

    if (event.key === 'Escape' && !confirmPrompt?.classList.contains('hidden')) {
        resolveConfirmPrompt(false);
        return;
    }

    if (event.key === 'Escape' && state.visible) {
        state.cart = {};
        state.accessoryCart = {};
        state.meleeCart = {};
        state.selectedTradeIn = null;
        state.paymentMethod = null;
        post('previewWeapon', { model: null });
        post('close');
        resolveConfirmPrompt(false);
        setVisible(false);
    }
});

setInterval(() => {
    if (!state.visible) return;

    state.activeOrders.forEach((order) => {
        if (Number(order.remaining_seconds || 0) > 0) {
            order.remaining_seconds -= 1;
        }
    });

    state.orders.forEach((order) => {
        if (Number(order.remaining_seconds || 0) > 0) {
            order.remaining_seconds -= 1;
        }
    });

    if (state.profile?.activeOrders) {
        state.profile.activeOrders.forEach((order) => {
            if (Number(order.remaining_seconds || 0) > 0) {
                order.remaining_seconds -= 1;
            }
        });
    }

    if (state.partsOrdering?.orders) {
        state.partsOrdering.orders.forEach((order) => {
            if (Number(order.remaining_seconds || 0) > 0) {
                order.remaining_seconds -= 1;
            }
        });
    }

    renderOrderRows('activeOrders', state.activeOrders, false, state.mode === 'sales');
    if (state.activeTab === 'stock') {
        renderPartsOrders();
    }
    if (state.activeTab === 'pickup') {
        renderPickupOrders();
    }
}, 1000);
