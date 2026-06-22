const panel = document.getElementById('panel');
const closeButton = document.getElementById('close');
const refreshButton = document.getElementById('refresh');
const inviteButton = document.getElementById('invite');
const donateFundsButton = document.getElementById('donate-funds');
const quickInviteButton = document.getElementById('quick-invite');
const quickMembersButton = document.getElementById('quick-members');
const quickRewardsButton = document.getElementById('quick-rewards');
const createEventButton = document.getElementById('create-event');
const stopEventButton = document.getElementById('stop-event');
const tabs = document.querySelectorAll('.nav-item');
const familyName = document.getElementById('family-name');
const familyRole = document.getElementById('family-role');
const familyImage = document.getElementById('family-image');
const sidebarFamilyName = document.getElementById('sidebar-family-name');
const sidebarFamilyRole = document.getElementById('sidebar-family-role');
const sidebarFamilyImage = document.getElementById('sidebar-family-image');
const familyLevel = document.getElementById('family-level');
const familyPoints = document.getElementById('family-points');
const totalPoints = document.getElementById('total-points');
const familyFunds = document.getElementById('family-funds');
const onlineMembers = document.getElementById('online-members');
const memberFunds = document.getElementById('member-funds');
const progressFill = document.getElementById('progress-fill');
const nextLevel = document.getElementById('next-level');
const members = document.getElementById('members');
const rewards = document.getElementById('rewards');
const overviewFeed = document.getElementById('overview-feed');
const logsFeed = document.getElementById('logs-feed');
const eventPanel = document.getElementById('event-panel');
const settingsPanel = document.getElementById('settings-panel');
const quickEventStatus = document.getElementById('quick-event-status');
const quickEventSummary = document.getElementById('quick-event-summary');
const toastStack = document.getElementById('toasts');

let state = null;
let eventDraftOpen = false;
let eventDraft = {};
let countdownRefreshRequested = false;
let confirmAction = null;

function post(name, data = {}) {
    fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    });
}

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, (char) => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#039;'
    }[char]));
}

function safeImageUrl(value) {
    const url = String(value || '').trim();
    if (!/^https?:\/\//i.test(url) && !/^data:image\/[a-z0-9+.-]+;base64,/i.test(url)) return '';
    return url.replace(/['")\\]/g, '');
}

function safeThemeColor(value) {
    const color = String(value || '').trim();
    return /^#[0-9a-f]{6}$/i.test(color) ? color : '';
}

function hexToRgb(hex) {
    const clean = safeThemeColor(hex).slice(1);
    if (!clean) return null;

    return {
        r: parseInt(clean.slice(0, 2), 16),
        g: parseInt(clean.slice(2, 4), 16),
        b: parseInt(clean.slice(4, 6), 16)
    };
}

function applyThemeColor(value) {
    const color = safeThemeColor(value);
    const root = document.documentElement;
    if (!color) {
        root.style.removeProperty('--accent');
        root.style.removeProperty('--accent-bright');
        root.style.removeProperty('--accent-soft');
        root.style.removeProperty('--accent-line');
        return;
    }

    const rgb = hexToRgb(color);
    root.style.setProperty('--accent', color);
    root.style.setProperty('--accent-bright', color);
    root.style.setProperty('--accent-soft', `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 0.14)`);
    root.style.setProperty('--accent-line', `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 0.36)`);
}

function formatMoney(value) {
    return `$${Math.max(0, Math.floor(Number(value) || 0)).toLocaleString()}`;
}

function setFamilyImage(element, url) {
    if (!element) return;

    if (url) {
        element.src = url;
        element.classList.remove('hidden');
        return;
    }

    element.removeAttribute('src');
    element.classList.add('hidden');
}

function showToast(description, type = 'inform') {
    const toast = document.createElement('article');
    toast.className = `tablet-toast ${type}`;
    toast.innerHTML = `
        <strong>Family Tablet</strong>
        <span>${escapeHtml(description || 'Action complete.')}</span>
    `;

    toastStack.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('visible'));

    setTimeout(() => {
        toast.classList.remove('visible');
        setTimeout(() => toast.remove(), 220);
    }, 4200);
}

function closeConfirmModal() {
    const existing = document.querySelector('.tablet-modal-backdrop');
    if (existing) existing.remove();
    confirmAction = null;
}

function showConfirmModal(title, message, onConfirm) {
    closeConfirmModal();
    confirmAction = onConfirm;

    const backdrop = document.createElement('div');
    backdrop.className = 'tablet-modal-backdrop';
    backdrop.innerHTML = `
        <article class="tablet-modal">
            <strong>${escapeHtml(title)}</strong>
            <span>${escapeHtml(message)}</span>
            <div class="actions">
                <button class="action-button" data-modal-action="cancel">Cancel</button>
                <button class="action-button danger" data-modal-action="confirm">Confirm</button>
            </div>
        </article>
    `;

    panel.appendChild(backdrop);

    backdrop.querySelector('[data-modal-action="cancel"]').addEventListener('click', closeConfirmModal);
    backdrop.querySelector('[data-modal-action="confirm"]').addEventListener('click', () => {
        if (confirmAction) confirmAction();
        closeConfirmModal();
    });
}

function showInfoModal(title, message) {
    closeConfirmModal();

    const backdrop = document.createElement('div');
    backdrop.className = 'tablet-modal-backdrop';
    backdrop.innerHTML = `
        <article class="tablet-modal">
            <strong>${escapeHtml(title)}</strong>
            <span>${escapeHtml(message)}</span>
            <div class="actions">
                <button class="action-button" data-modal-action="cancel">Close</button>
            </div>
        </article>
    `;

    panel.appendChild(backdrop);
    backdrop.querySelector('[data-modal-action="cancel"]').addEventListener('click', closeConfirmModal);
}

function formatCountdown(seconds) {
    seconds = Math.max(0, Math.floor(Number(seconds) || 0));
    const minutes = Math.floor(seconds / 60);
    const remainder = seconds % 60;
    return `${minutes}:${String(remainder).padStart(2, '0')}`;
}

function eventCountdownSeconds(event) {
    if (!event) return 0;
    if (event.startsAt) return Number(event.startsAt) - Math.floor(Date.now() / 1000);
    return event.startsIn || 0;
}

function getPreset(presetId) {
    const presets = state?.eventPresets || [];
    return presets.find((preset) => preset.id === presetId) || presets[0] || null;
}

function getPolygonArea(points = []) {
    if (!Array.isArray(points) || points.length < 3) return 0;

    let area = 0;
    let j = points.length - 1;
    for (let i = 0; i < points.length; i += 1) {
        const current = points[i];
        const previous = points[j];
        area += ((Number(previous.x) || 0) + (Number(current.x) || 0)) * ((Number(previous.y) || 0) - (Number(current.y) || 0));
        j = i;
    }

    return Math.abs(area / 2);
}

function getPresetForArea(area) {
    const presets = [...(state?.eventPresets || [])].sort((a, b) => {
        const aMax = Number(a.maxArea) || 0;
        const bMax = Number(b.maxArea) || 0;
        if (aMax && bMax) return aMax - bMax;
        if (aMax) return -1;
        if (bMax) return 1;
        return String(a.label || a.id).localeCompare(String(b.label || b.id));
    });

    return presets.find((preset) => !Number(preset.maxArea) || area <= Number(preset.maxArea)) || presets[0] || null;
}

function formatArea(area) {
    return `${Math.round(Number(area) || 0).toLocaleString()} sq m`;
}

function updateDraftFromForm() {
    const nameInput = document.getElementById('draft-event-name');
    const locationInput = document.getElementById('draft-event-location');
    const propInput = document.getElementById('draft-event-prop');
    if (nameInput) eventDraft.name = nameInput.value;
    if (locationInput) eventDraft.location = locationInput.value;
    if (propInput) eventDraft.selectedProp = propInput.value;
}

function openEventDraft() {
    eventDraftOpen = true;
    eventDraft = {
        name: '',
        location: '',
        points: [],
        props: [],
        selectedProp: (state?.eventAllowedProps || [])[0]?.id || '',
        bannerUrl: ''
    };
    render(state);
}

function closeEventDraft() {
    post('clearDraftEventProps');
    eventDraftOpen = false;
    eventDraft = {};
    render(state);
}

function setTab(tab) {
    tabs.forEach((button) => {
        const active = button.dataset.tab === tab;
        button.classList.toggle('active', active);
        document.getElementById(`${button.dataset.tab}-tab`).classList.toggle('active', active);
    });
}

function renderProgress(data) {
    const progression = data.progression || {};
    const funds = data.funds || {};
    const total = progression.totalPoints || 0;
    const available = progression.availablePoints || 0;
    const currentLevelPoints = progression.currentLevelPoints || 0;
    const next = progression.nextLevel;

    familyLevel.textContent = `Level ${progression.level || 1}`;
    familyPoints.textContent = `${available} pts`;
    totalPoints.textContent = total;
    familyFunds.textContent = formatMoney(funds.balance || 0);

    if (next && next.points) {
        const span = Math.max(1, next.points - currentLevelPoints);
        const percent = Math.max(0, Math.min(100, ((total - currentLevelPoints) / span) * 100));
        progressFill.style.width = `${percent}%`;
        nextLevel.textContent = `${total} / ${next.points} total points toward Level ${next.level}`;
    } else {
        progressFill.style.width = '100%';
        nextLevel.textContent = `${total} total points. Max configured level reached.`;
    }
}

function renderOverview(data) {
    const list = data.members || [];
    const onlineCount = list.filter((member) => member.online).length;
    const rewardCount = data.progression?.rewards?.length || 0;
    const unlockedRewards = (data.progression?.rewards || []).filter((reward) => reward.unlocked && !reward.redeemed).length;

    onlineMembers.textContent = `${onlineCount}/${list.length}`;
    memberFunds.textContent = `${formatMoney(data.funds?.balance || 0)} saved`;

    const event = data.event;
    overviewFeed.innerHTML = `
        <article class="feed-item">
            <strong>Family Standing</strong>
            <span>${escapeHtml(data.self?.familyLabel || 'No Family')} has ${escapeHtml(String(data.progression?.availablePoints || 0))} points and ${escapeHtml(formatMoney(data.funds?.balance || 0))} saved.</span>
        </article>
        <article class="feed-item">
            <strong>Redeem Access</strong>
            <span>${unlockedRewards} available redemption(s) out of ${rewardCount} configured unlocks.</span>
        </article>
        <article class="feed-item">
            <strong>Event Operations</strong>
            <span>${event ? `${escapeHtml(event.name)} is active with ${event.insideCount || 0} member(s) in zone.` : 'No active family event is running.'}</span>
        </article>
    `;

    logsFeed.innerHTML = `
        <article class="feed-item">
            <strong>Point History</strong>
            <span>Family point updates and reward redemptions are logged server-side.</span>
        </article>
        <article class="feed-item">
            <strong>Event Logs</strong>
            <span>Event zone and prop placement logs will appear here once the event system is added.</span>
        </article>
    `;
}

function renderEvent(data) {
    const self = data.self || {};
    const event = data.event;
    const templates = data.eventTemplates || [];
    const shareOptions = data.familyShareOptions || [];
    const eventBannerUrl = safeImageUrl(event?.bannerUrl);
    const allowedProps = data.eventAllowedProps || [];
    const maxProps = Number(data.eventMaxProps) || 0;

    eventDraft.points = Array.isArray(eventDraft.points) ? eventDraft.points : [];
    eventDraft.props = Array.isArray(eventDraft.props) ? eventDraft.props : [];
    if (!eventDraft.selectedProp && allowedProps.length) eventDraft.selectedProp = allowedProps[0].id;

    const hasDraftZone = eventDraft.points.length >= (data.eventMinZonePoints || 4);

    createEventButton.classList.toggle('hidden', !self.isHead);
    stopEventButton.classList.toggle('hidden', !self.isHead || !event);

    quickEventStatus.textContent = event ? (event.status === 'scheduled' ? 'Scheduled' : 'Online') : 'Offline';
    quickEventSummary.textContent = event
        ? event.status === 'scheduled'
            ? `${event.name}: starts in ${formatCountdown(eventCountdownSeconds(event))}.`
            : `${event.name}: ${event.insideCount || 0} member(s) inside zone.`
        : 'No active family event is running.';

    const draftArea = getPolygonArea(eventDraft.points);
    const draftPreset = getPresetForArea(draftArea);
    const draftMarkup = eventDraftOpen ? `
        <article class="event-builder">
            <div class="event-head">
                <div>
                    <strong>Create Event</strong>
                    <span>Configure the event, add at least 4 zone points, then capture the banner.</span>
                </div>
                <span class="badge">Draft</span>
            </div>
            <div class="builder-body">
                <div class="builder-controls">
                    <label class="builder-field">
                        <span>Event Name</span>
                        <input id="draft-event-name" value="${escapeHtml(eventDraft.name || '')}" placeholder="Block Party">
                    </label>

                    <label class="builder-field">
                        <span>Event Location</span>
                        <input id="draft-event-location" value="${escapeHtml(eventDraft.location || '')}" placeholder="Mirror Park Tavern">
                    </label>

                    <section class="builder-section">
                        <div>
                            <span>Zone Points</span>
                            <strong>${eventDraft.points.length} / ${data.eventMinZonePoints || 4} minimum</strong>
                        </div>
                        <div class="actions compact">
                            <button class="action-button" data-action="add-zone-points">Add Points</button>
                            <button class="action-button" data-action="view-zone-points">View</button>
                            <button class="action-button" data-action="clear-zone-points">Clear</button>
                        </div>
                    </section>

                    <section class="builder-section">
                        <div>
                            <span>Scene Props</span>
                            <strong>${eventDraft.props.length} / ${maxProps} placed</strong>
                        </div>
                        ${allowedProps.length ? `<select id="draft-event-prop">
                            ${allowedProps.map((prop) => `<option value="${escapeHtml(prop.id)}" ${prop.id === eventDraft.selectedProp ? 'selected' : ''}>${escapeHtml(prop.label)}</option>`).join('')}
                        </select>` : '<small>No props configured.</small>'}
                        <div class="actions compact">
                            <button class="action-button" data-action="add-event-prop" ${!allowedProps.length || !hasDraftZone || eventDraft.props.length >= maxProps ? 'disabled' : ''}>Add Prop</button>
                            <button class="action-button" data-action="view-event-props">View</button>
                            <button class="action-button" data-action="clear-event-props">Clear</button>
                        </div>
                        <small>${hasDraftZone ? 'Props must stay inside the zone.' : 'Add zone points before props.'}</small>
                    </section>

                    <section class="builder-section">
                        <div>
                            <span>Banner</span>
                            <strong>${eventDraft.bannerUrl ? 'Captured' : 'Not captured'}</strong>
                        </div>
                        <button class="action-button" data-action="capture-banner">Capture Banner</button>
                    </section>
                </div>

                <aside class="builder-summary">
                    <div class="banner-preview ${eventDraft.bannerUrl ? '' : 'empty'}" ${eventDraft.bannerUrl ? `style="background-image: url('${safeImageUrl(eventDraft.bannerUrl)}')"` : ''}>
                        ${eventDraft.bannerUrl ? '' : '<span>No Banner</span>'}
                    </div>
                    <div class="summary-grid">
                        <div><span>Tier</span><strong>${escapeHtml(draftPreset?.label || 'Pending')}</strong></div>
                        <div><span>Area</span><strong>${escapeHtml(draftArea > 0 ? formatArea(draftArea) : 'No zone')}</strong></div>
                        <div><span>Payout</span><strong>${escapeHtml(draftPreset?.pointsPerTick || 0)} pts</strong></div>
                        <div><span>Every</span><strong>${escapeHtml(data.eventTickMinutes || 5)} min</strong></div>
                    </div>
                </aside>
            </div>
            <div class="actions">
                <button class="action-button" data-action="save-draft">Save Event</button>
                <button class="action-button" data-action="cancel-draft">Cancel</button>
            </div>
        </article>
    ` : '';

    if (eventDraftOpen) {
        eventPanel.innerHTML = draftMarkup;

        const nameInput = document.getElementById('draft-event-name');
        const locationInput = document.getElementById('draft-event-location');
        const propInput = document.getElementById('draft-event-prop');

        if (nameInput) nameInput.addEventListener('input', updateDraftFromForm);
        if (locationInput) locationInput.addEventListener('input', updateDraftFromForm);
        if (propInput) propInput.addEventListener('change', updateDraftFromForm);

        eventPanel.querySelector('[data-action="add-zone-points"]')?.addEventListener('click', () => {
            updateDraftFromForm();
            post('addEventZonePoints', { points: eventDraft.points });
        });

        eventPanel.querySelector('[data-action="view-zone-points"]')?.addEventListener('click', () => {
            if (!eventDraft.points.length) return showToast('No zone points added yet.', 'inform');
            showInfoModal('Zone Points', eventDraft.points.map((point, index) => `${index + 1}. x:${Number(point.x).toFixed(2)} y:${Number(point.y).toFixed(2)} z:${Number(point.z).toFixed(2)}`).join('\n'));
        });

        eventPanel.querySelector('[data-action="clear-zone-points"]')?.addEventListener('click', () => {
            eventDraft.points = [];
            showToast('Zone points cleared.', 'inform');
            renderEvent(state);
        });

        eventPanel.querySelector('[data-action="add-event-prop"]')?.addEventListener('click', () => {
            updateDraftFromForm();
            if (!allowedProps.length) return showToast('No event props are configured.', 'error');
            if (!hasDraftZone) return showToast(`Add at least ${state.eventMinZonePoints || 4} zone points before placing props.`, 'error');
            if (eventDraft.props.length >= maxProps) return showToast(`This event already has the max ${maxProps} props.`, 'error');
            post('addEventProp', { propId: eventDraft.selectedProp || allowedProps[0]?.id, points: eventDraft.points });
        });

        eventPanel.querySelector('[data-action="view-event-props"]')?.addEventListener('click', () => {
            if (!eventDraft.props.length) return showToast('No props placed yet.', 'inform');
            showInfoModal('Scene Props', eventDraft.props.map((prop, index) => `${index + 1}. ${prop.label || prop.id} | x:${Number(prop.coords?.x).toFixed(2)} y:${Number(prop.coords?.y).toFixed(2)} z:${Number(prop.coords?.z).toFixed(2)} | rot:${Number(prop.rotation?.x || 0).toFixed(1)}, ${Number(prop.rotation?.y || 0).toFixed(1)}, ${Number(prop.rotation?.z || prop.heading || 0).toFixed(1)}`).join('\n'));
        });

        eventPanel.querySelector('[data-action="clear-event-props"]')?.addEventListener('click', () => {
            eventDraft.props = [];
            post('clearDraftEventProps');
            showToast('Scene props cleared.', 'inform');
            renderEvent(state);
        });

        eventPanel.querySelector('[data-action="capture-banner"]')?.addEventListener('click', () => {
            updateDraftFromForm();
            post('captureEventBanner');
        });

        eventPanel.querySelector('[data-action="save-draft"]')?.addEventListener('click', () => {
            updateDraftFromForm();
            if (!eventDraft.name || !eventDraft.name.trim()) return showToast('Add an event name before saving.', 'error');
            if (eventDraft.points.length < (state.eventMinZonePoints || 4)) return showToast(`Add at least ${state.eventMinZonePoints || 4} zone points before saving.`, 'error');

            post('saveEventTemplate', eventDraft);
            post('clearDraftEventProps');
            closeEventDraft();
        });

        eventPanel.querySelector('[data-action="cancel-draft"]')?.addEventListener('click', closeEventDraft);
        return;
    }

    const activeMarkup = event ? (() => {
        const activePreset = getPreset(event.preset);
        const membersInside = event.insideMembers && event.insideMembers.length
            ? event.insideMembers.map((member) => `<span>${escapeHtml(member.name)} | ID ${member.source}</span>`).join('')
            : '<span>No family members currently inside.</span>';

        return `
        <article class="event-card">
            ${eventBannerUrl ? `<div class="event-banner" style="background-image: url('${eventBannerUrl}')"></div>` : ''}
            <div class="event-head">
                <div>
                    <strong>${escapeHtml(event.name)}</strong>
                    <span>${event.status === 'scheduled' ? `Starts in ${formatCountdown(eventCountdownSeconds(event))}` : 'Active'} | ${escapeHtml(activePreset?.label || event.preset || 'Auto Tier')} | ${escapeHtml(formatArea(event.zoneArea))} | ${(event.props || []).length} props | ${escapeHtml(event.pointsPerTick)} pts/member every ${escapeHtml(event.tickMinutes)} min</span>
                </div>
                <span class="badge">${event.status === 'scheduled' ? 'Scheduled' : 'Active'}</span>
            </div>
            <div class="event-grid">
                <div>
                    <small>${event.status === 'scheduled' ? 'Countdown' : 'Members In Zone'}</small>
                    <b>${event.status === 'scheduled' ? formatCountdown(eventCountdownSeconds(event)) : escapeHtml(event.insideCount || 0)}</b>
                </div>
                <div>
                    <small>Zone Points</small>
                    <b>${escapeHtml(event.pointCount || 0)}</b>
                </div>
                <div>
                    <small>Location</small>
                    <b>${escapeHtml(event.location || 'Marked Event Area')}</b>
                </div>
            </div>
            <div class="inside-list">${membersInside}</div>
        </article>
        `;
    })() : `
        <article class="event-card">
            <div class="event-head">
                <div>
                    <strong>No Active Event</strong>
                    <span>Create a saved event, then start it whenever the family hosts that scene.</span>
                </div>
                <span class="badge locked">Offline</span>
            </div>
        </article>
    `;

    const templateMarkup = templates.length ? templates.map((template) => {
        const bannerUrl = safeImageUrl(template.bannerUrl);
        const isActiveTemplate = event && Number(event.templateId) === Number(template.id);
        const templatePreset = getPreset(template.preset);
        const shareSelect = template.owned && shareOptions.length ? `
            <select class="share-select" data-share-select="${template.id}">
                ${shareOptions.map((family) => `<option value="${escapeHtml(family.id)}">${escapeHtml(family.label)}</option>`).join('')}
            </select>
        ` : '';
        return `
        <article class="event-template">
            ${bannerUrl ? `<div class="event-banner" style="background-image: url('${bannerUrl}')"></div>` : ''}
            <div class="event-head">
                <div>
                    <strong>${escapeHtml(template.name)}</strong>
                    <span>${template.shared ? `Shared by ${escapeHtml(template.familyLabel)}` : 'Owned'} | ${escapeHtml(template.location || 'Marked Event Area')} | ${escapeHtml(templatePreset?.label || template.preset || 'Auto Tier')} | ${escapeHtml(formatArea(template.zoneArea))} | ${(template.props || []).length} props | ${escapeHtml(template.pointsPerTick)} pts/member</span>
                </div>
                <span class="badge ${isActiveTemplate ? '' : 'locked'}">${isActiveTemplate ? 'Active' : 'Saved'}</span>
            </div>
            ${self.isHead ? `
                <div class="actions">
                    <button class="action-button" ${event ? 'disabled' : ''} data-action="start-template" data-template="${template.id}">Start Countdown</button>
                    ${template.owned ? `<button class="action-button" data-action="delete-template" data-template="${template.id}" data-name="${escapeHtml(template.name)}">Delete</button>` : ''}
                    ${shareSelect}
                    ${template.owned && shareOptions.length ? `<button class="action-button" data-action="share-template" data-template="${template.id}">Share</button>` : ''}
                </div>
            ` : ''}
        </article>
    `;
    }).join('') : `
        <div class="placeholder-grid">
            <article class="placeholder-card">
                <strong>No Saved Events</strong>
                <p>Heads of House can save recurring family events with a zone, point value, and captured scene banner.</p>
            </article>
            <article class="placeholder-card">
                <strong>Zone Points</strong>
                <p>Add at least four points to draw the polygon area for the event.</p>
            </article>
        </div>
    `;

    eventPanel.innerHTML = `
        ${activeMarkup}
        <div class="section-title saved-events-title">
            <h2>Saved Events</h2>
            <span class="soft-label">${templates.length} saved</span>
        </div>
        <div class="saved-events-scroll">
            <div class="saved-events">${templateMarkup}</div>
        </div>
    `;

    eventPanel.querySelectorAll('[data-action="start-template"]').forEach((button) => {
        button.addEventListener('click', () => post('startEvent', { templateId: Number(button.dataset.template) }));
    });

    eventPanel.querySelectorAll('[data-action="delete-template"]').forEach((button) => {
        button.addEventListener('click', () => {
            const name = button.dataset.name || 'this saved event';
            showConfirmModal('Delete Event', `Delete ${name}?`, () => {
                post('deleteEventTemplate', {
                    templateId: Number(button.dataset.template),
                    name
                });
            });
        });
    });

    eventPanel.querySelectorAll('[data-action="share-template"]').forEach((button) => {
        button.addEventListener('click', () => {
            const select = eventPanel.querySelector(`[data-share-select="${button.dataset.template}"]`);
            if (!select || !select.value) return showToast('Choose a family to share with.', 'error');
            post('shareEventTemplate', {
                templateId: Number(button.dataset.template),
                family: select.value
            });
        });
    });
}

function renderMembers(data) {
    const self = data.self || {};
    const list = data.members || [];
    members.innerHTML = '';
    donateFundsButton.classList.toggle('hidden', !self.family || self.family === 'none');

    if (!list.length) {
        members.innerHTML = '<div class="row"><p class="row-meta">No family members yet.</p></div>';
        return;
    }

    list.forEach((member) => {
        const isSelf = member.citizenid === self.citizenid;
        const row = document.createElement('article');
        row.className = 'row';
        row.innerHTML = `
            <div class="row-head">
                <div>
                    <p class="row-title">${escapeHtml(member.name)}</p>
                    <p class="row-meta">Role: ${escapeHtml(member.roleLabel)}<br>Job: ${escapeHtml(member.jobLabel)}<br>${member.online ? `Online | ID: ${member.source}` : 'Offline'}</p>
                </div>
                <span class="badge ${member.online ? '' : 'locked'}">${member.online ? 'Online' : 'Offline'}</span>
            </div>
        `;

        if (self.isManager && !isSelf) {
            const actions = document.createElement('div');
            actions.className = 'actions';

            if (self.canSetRole) {
                const button = document.createElement('button');
                button.className = 'action-button';
                button.textContent = 'Role';
                button.addEventListener('click', () => post('setRole', { citizenid: member.citizenid }));
                actions.appendChild(button);
            }

            if (self.canGiveAllowance && member.online) {
                const button = document.createElement('button');
                button.className = 'action-button';
                button.textContent = 'Allowance';
                button.addEventListener('click', () => post('allowance', { citizenid: member.citizenid }));
                actions.appendChild(button);
            }

            if (self.canKick) {
                const button = document.createElement('button');
                button.className = 'action-button';
                button.textContent = 'Remove';
                button.addEventListener('click', () => post('kick', { citizenid: member.citizenid, name: member.name }));
                actions.appendChild(button);
            }

            row.appendChild(actions);
        }

        members.appendChild(row);
    });
}

function renderRewards(data) {
    const self = data.self || {};
    const list = data.progression?.rewards || [];
    rewards.innerHTML = '';

    if (!list.length) {
        rewards.innerHTML = '<div class="row"><p class="row-meta">No redemptions configured yet.</p></div>';
        return;
    }

    list.forEach((reward) => {
        const locked = !reward.unlocked || reward.redeemed;
        const canRedeem = self.isHead && reward.unlocked && reward.affordable && !reward.redeemed;
        const isPropUnlock = reward.type === 'prop_unlock';
        const typeLabel = isPropUnlock ? 'Prop Unlock' : reward.type;
        const pointCost = Number(reward.cost) || 0;
        const fundCost = Number(reward.fundCost) || 0;
        const hasPoints = (data.progression?.availablePoints || 0) >= pointCost;
        const hasFunds = (data.funds?.balance || 0) >= fundCost;
        const costParts = [];
        if (pointCost > 0) costParts.push(`${pointCost} pts`);
        if (fundCost > 0) costParts.push(formatMoney(fundCost));
        const costText = costParts.length ? costParts.join(' + ') : 'Free';
        const status = reward.redeemed ? (isPropUnlock ? 'Unlocked' : 'Redeemed') : reward.unlocked ? costText : `Level ${reward.requiredLevel}`;

        const row = document.createElement('article');
        row.className = 'row';
        row.innerHTML = `
            <div class="row-head">
                <div>
                    <p class="row-title">${escapeHtml(reward.label)}</p>
                    <p class="row-meta">${escapeHtml(reward.description || '')}<br>Type: ${escapeHtml(typeLabel)}<br>Cost: ${escapeHtml(costText)}</p>
                </div>
                <span class="badge ${locked ? 'locked' : ''}">${escapeHtml(status)}</span>
            </div>
        `;

        if (self.isHead) {
            const actions = document.createElement('div');
            actions.className = 'actions';
            const button = document.createElement('button');
            button.className = 'action-button';
            button.textContent = canRedeem
                ? 'Redeem'
                : reward.redeemed
                    ? (isPropUnlock ? 'Unlocked' : 'Claimed')
                    : reward.unlocked
                        ? !hasPoints ? 'Need Points' : !hasFunds ? 'Need Funds' : 'Locked'
                        : 'Locked';
            button.disabled = !canRedeem;
            button.addEventListener('click', () => post('redeem', { rewardId: reward.id, label: reward.label }));
            actions.appendChild(button);
            row.appendChild(actions);
        }

        rewards.appendChild(row);
    });
}

function renderSettings(data) {
    const self = data.self || {};
    const settings = data.settings || {};
    const imageUrl = safeImageUrl(settings.imageUrl);
    const themeColor = safeThemeColor(settings.themeColor) || '#5ea2ff';
    const canEdit = self.isHead && self.family && self.family !== 'none';

    settingsPanel.innerHTML = `
        <article class="settings-card ${canEdit ? '' : 'locked'}">
            <div class="row-head">
                <div>
                    <p class="row-title">Family Image</p>
                    <p class="row-meta">${canEdit ? 'Set the image used in the tablet header and sidebar.' : 'Only Head of House can update the family image.'}</p>
                </div>
                <span class="badge ${canEdit ? '' : 'locked'}">${canEdit ? 'Head Access' : 'Locked'}</span>
            </div>
            <label>
                Image URL
                <input id="family-image-url" value="${escapeHtml(imageUrl)}" placeholder="https://example.com/family.png" ${canEdit ? '' : 'disabled'}>
            </label>
            <label>
                Theme Color
                <input id="family-theme-color" type="color" value="${escapeHtml(themeColor)}" ${canEdit ? '' : 'disabled'}>
            </label>
            <small>Use a direct image URL that starts with http:// or https://. Leave it blank to remove the family image.</small>
            <div class="actions">
                <button id="save-family-settings" class="action-button" ${canEdit ? '' : 'disabled'}>Save Settings</button>
            </div>
        </article>
        <article class="settings-card">
            <div class="settings-preview">
                ${imageUrl ? `<img src="${escapeHtml(imageUrl)}" alt="">` : '<span>No Family Image</span>'}
            </div>
        </article>
    `;

    const input = document.getElementById('family-image-url');
    const colorInput = document.getElementById('family-theme-color');
    const save = document.getElementById('save-family-settings');

    input?.addEventListener('input', () => {
        const previewUrl = safeImageUrl(input.value);
        const preview = settingsPanel.querySelector('.settings-preview');
        if (!preview) return;

        preview.innerHTML = previewUrl ? `<img src="${escapeHtml(previewUrl)}" alt="">` : '<span>No Family Image</span>';
    });

    colorInput?.addEventListener('input', () => {
        applyThemeColor(colorInput.value);
    });

    save?.addEventListener('click', () => {
        post('saveSettings', {
            imageUrl: input?.value || '',
            themeColor: colorInput?.value || ''
        });
    });
}

function render(data) {
    state = data;
    const self = data.self || {};
    const familySettings = data.settings || {};
    const imageUrl = safeImageUrl(familySettings.imageUrl);
    applyThemeColor(familySettings.themeColor);

    familyName.textContent = self.familyLabel || 'No Family';
    familyRole.textContent = `${self.roleLabel || 'Unaffiliated'}${self.isHead ? ' | Head of House' : ''}`;
    sidebarFamilyName.textContent = self.familyLabel || 'No Family';
    sidebarFamilyRole.textContent = self.roleLabel || 'Unaffiliated';
    setFamilyImage(familyImage, imageUrl);
    setFamilyImage(sidebarFamilyImage, imageUrl);
    inviteButton.classList.toggle('hidden', !self.canInvite);
    quickInviteButton.classList.toggle('hidden', !self.canInvite);
    renderProgress(data);
    renderOverview(data);
    renderEvent(data);
    renderMembers(data);
    renderRewards(data);
    renderSettings(data);
}

window.addEventListener('message', (event) => {
    if (event.data.action === 'open') {
        panel.classList.remove('hidden');
        panel.classList.remove('capturing');
        countdownRefreshRequested = false;
        render(event.data.data || {});
    }

    if (event.data.action === 'close') {
        panel.classList.add('hidden');
        panel.classList.remove('capturing');
        closeConfirmModal();
    }

    if (event.data.action === 'captureMode') {
        panel.classList.toggle('capturing', event.data.active === true);
        panel.classList.toggle('hidden', event.data.active === true);
    }

    if (event.data.action === 'toast') {
        showToast(event.data.description, event.data.type);
    }

    if (event.data.action === 'createEventDraft') {
        openEventDraft();
    }

    if (event.data.action === 'eventZonePointsSelected') {
        eventDraft.points = event.data.points || [];
        showToast(`Point placement finished with ${eventDraft.points.length} point(s).`, 'success');
        render(state);
    }

    if (event.data.action === 'eventPropPlaced') {
        if (event.data.prop) {
            eventDraft.props = [...(eventDraft.props || []), event.data.prop];
            showToast(`Prop added: ${event.data.prop.label || event.data.prop.id}.`, 'success');
        }
        render(state);
    }

    if (event.data.action === 'eventBannerCaptured') {
        if (event.data.bannerUrl) {
            eventDraft.bannerUrl = event.data.bannerUrl;
            showToast('Event banner captured.', 'success');
        }
        render(state);
    }
});

closeButton.addEventListener('click', () => post('close'));
refreshButton.addEventListener('click', () => post('refresh'));
inviteButton.addEventListener('click', () => post('invite'));
donateFundsButton.addEventListener('click', () => post('donateFunds'));
quickInviteButton.addEventListener('click', () => post('invite'));
quickMembersButton.addEventListener('click', () => setTab('members'));
quickRewardsButton.addEventListener('click', () => setTab('rewards'));
createEventButton.addEventListener('click', () => post('createEventTemplate'));
stopEventButton.addEventListener('click', () => post('stopEvent'));
tabs.forEach((button) => button.addEventListener('click', () => setTab(button.dataset.tab)));

setInterval(() => {
    if (state?.event?.status === 'scheduled' && !panel.classList.contains('hidden')) {
        if (eventCountdownSeconds(state.event) <= 0 && !countdownRefreshRequested) {
            countdownRefreshRequested = true;
            post('refresh');
        }
        renderEvent(state);
    }
}, 1000);

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') post('close');
});
