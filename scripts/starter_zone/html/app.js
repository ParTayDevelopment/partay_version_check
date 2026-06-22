let appState = {
  status: null,
  items: [],
  vehicles: [],
  bonus: null,
  budget: 4000,
  profile: 'default',
  profileLabel: 'Starter Pack',
  theme: 'default',
  jobs: [],
  maxChoices: 6,
  setJobFromMenu: true,
  requiredItem: 'phone',
  requiredItemLabel: 'Phone',
  mode: 'starter'
};
let selected = [];
let selectedVehicle = null;
let pendingJobSelection = null;
let jobWarningOpen = false;
let starterPackWarningOpen = false;
let starterPackReturnTab = 'checklist';
let pendingAction = false;

function selectedTotal() {
  const itemTotal = selected.reduce((total, item) => total + Number(item.quantity || 0), 0);
  return itemTotal + (selectedVehicle ? Number(selectedVehicle.countsAsChoices || 1) : 0);
}

function selectedCost() {
  const itemCost = selected.reduce((total, item) => total + (Number(item.quantity || 0) * Number(item.cost || 0)), 0);
  return itemCost + (selectedVehicle ? Number(selectedVehicle.cost || 0) : 0);
}

function getSelectedItem(itemName) {
  return selected.find(item => item.item === itemName);
}

function hasRequiredStarterItem() {
  return !appState.requiredItem || !!getSelectedItem(appState.requiredItem);
}

function nuiCallback(name, data = {}) {
  return fetch(`https://starter_zone/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
  }).then(resp => resp.json()).catch(() => ({ ok: false }));
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, char => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[char]));
}

function money(value) {
  return '$' + Number(value || 0).toLocaleString('en-US');
}

function canAffordAdditional(costDelta) {
  return selectedCost() + Number(costDelta || 0) <= Number(appState.budget || 0);
}

function minutes(seconds) {
  return Math.floor(Number(seconds || 0) / 60);
}

function miles(meters) {
  return `${((Number(meters) || 0) / 1609.344).toFixed(1)} mi`;
}

function closeUi() {
  document.body.classList.remove('ui-visible');
  document.body.classList.remove('modal-open');
  document.body.classList.remove('jobcenter-mode');
  nuiCallback('close');
}

function switchTab(name, btn) {
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
  document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
  const tabButton = btn || Array.from(document.querySelectorAll('.tab-btn')).find(b => b.dataset.tab === name);
  if (tabButton) tabButton.classList.add('active');
  document.getElementById('tab-' + name).classList.add('active');
}

function getActiveTab() {
  const activePanel = document.querySelector('.tab-panel.active');
  return activePanel ? activePanel.id.replace('tab-', '') : 'checklist';
}

function requestTab(name, btn) {
  if (name === 'jobs') {
    showToast('Go to the Job Center and speak with the counselor to get a job.');
    return;
  }

  if (name === 'starter') {
    openStarterPackWarning(btn);
    return;
  }

  switchTab(name, btn);
}

function renderChecklist() {
  const status = appState.status;
  if (!status) return;

  const checks = status.checks || {};
  const tasks = [
    {
      key: 'identity',
      icon: '&#128100;',
      name: 'Identity Established',
      desc: 'Completed during character creation - registered in the city database',
      done: !!checks.identity
    },
    {
      key: 'id_card',
      icon: '&#128179;',
      name: 'Register Official ID',
      desc: checks.id_card ? 'Your official ID and driver license have been issued - carry them at all times' : 'Register your official ID and 30-day driver license through city records',
      done: !!checks.id_card,
      action: 'registerId'
    },
    {
      key: 'starter_kit',
      icon: '&#127890;',
      name: 'Choose Starter Essentials',
      desc: checks.starter_kit ? 'Starter essentials selected and added to your inventory' : `Pick ${appState.maxChoices} items to get you started in No Love Lost - one time only`,
      done: !!checks.starter_kit,
      tab: 'starter'
    },
    {
      key: 'starter_job',
      icon: '&#128188;',
      name: 'Go to Job Center',
      desc: checks.starter_job ? `Current job: ${escapeHtml(status.job || 'unemployed')}. You can return to the Job Center to change city jobs.` : 'Go to the Job Center and speak with the counselor to get a job.',
      done: !!checks.starter_job
    },
    {
      key: 'bike_ride',
      icon: '&#128690;',
      name: `Ride a Bike - ${miles(status.requiredBikeRideDistance)} Required`,
      desc: `${miles(status.bikeRideDistance)} / ${miles(status.requiredBikeRideDistance)} tracked on approved starter bikes`,
      done: !!checks.bike_ride
    },
    {
      key: 'bank',
      icon: '&#127974;',
      name: 'Save Money in Bank',
      desc: `${money(status.bank)} / ${money(status.requiredBank)} required - deposit at any Fleeca Bank branch`,
      done: !!checks.bank
    },
    {
      key: 'playtime',
      icon: '&#9200;',
      name: `Stay Active - ${minutes(status.requiredPlaytime)} Min Playtime`,
      desc: `${minutes(status.playtime)} min / ${minutes(status.requiredPlaytime)} min required - time accrues automatically`,
      done: !!checks.playtime
    }
  ];

  const grid = document.getElementById('task-grid');
  grid.innerHTML = '';
  tasks.forEach(task => {
    const clickable = !task.done && (task.tab || task.action);
    const card = document.createElement('div');
    card.className = `task-card ${task.done ? 'done' : clickable ? 'active clickable' : ''}`;
    if (clickable) {
      card.onclick = () => {
        if (task.tab) requestTab(task.tab);
        if (task.action === 'registerId') registerId();
      };
    }
    card.innerHTML = `
      <div class="task-icon-wrap">${task.icon}</div>
      <div class="task-info">
        <div class="task-name">${escapeHtml(task.name)}</div>
        <div class="task-desc">${task.desc}</div>
      </div>
      <div class="task-status">
        <span class="status-pill ${task.done ? 'pill-done' : clickable ? 'pill-pending' : 'pill-locked'}">${task.done ? 'Done' : clickable ? 'Pending' : 'Locked'}</span>
        ${clickable ? '<span class="action-arrow">&rsaquo;</span>' : ''}
      </div>
    `;
    grid.appendChild(card);
  });

  const doneCount = tasks.filter(task => task.done).length;
  const total = tasks.length;
  const pending = total - doneCount;
  document.getElementById('prog-bar').style.width = Math.round((doneCount / total) * 100) + '%';
  document.getElementById('prog-label').textContent = `${doneCount} / ${total} Complete`;
  const badge = document.getElementById('pending-badge');
  badge.textContent = pending;
  badge.style.display = pending > 0 ? 'inline-flex' : 'none';

  const clearance = document.getElementById('clearance-box');
  clearance.className = `clearance-box ${status.canLeave ? 'cleared' : 'locked'}`;
  clearance.innerHTML = status.canLeave
    ? '<span class="clearance-icon">&#10003;</span><div><div style="font-size:14px;font-weight:700;letter-spacing:2px;">CLEARED FOR DEPARTURE</div><div style="font-size:11px;font-weight:400;margin-top:2px;color:rgba(182,255,46,0.78);">You are cleared to leave the city</div></div>'
    : '<span class="clearance-icon">&#128274;</span><div><div style="font-size:14px;font-weight:700;letter-spacing:2px;">NOT CLEARED FOR DEPARTURE</div><div style="font-size:11px;font-weight:400;margin-top:2px;color:rgba(33,216,255,0.78);">Complete all tasks above to unlock city departure clearance</div></div>';
}

function buildItemsGrid() {
  const grid = document.getElementById('items-grid');
  const claimed = !!(appState.status && appState.status.starter && appState.status.starter.claimedStarterKit);
  const total = selectedTotal();
  grid.innerHTML = '';
  appState.items.forEach(it => {
    const card = document.createElement('div');
    const selectedItem = getSelectedItem(it.item);
    const quantity = selectedItem ? selectedItem.quantity : 0;
    const isSelected = quantity > 0;
    const grantAmount = Number(it.amount || 1);
    const grantLabel = grantAmount > 1 ? `<div class="item-grant">${grantAmount} per selection</div>` : '';
    card.className = `item-card ${isSelected ? 'selected' : ''} ${claimed || (!isSelected && total >= appState.maxChoices) ? 'disabled' : ''}`;
    card.id = 'item-' + it.item;
    card.innerHTML = `
      <div class="item-check">&#10003;</div>
      <span class="item-amount">${money(it.cost)}</span>
      <img class="item-image" src="${escapeHtml(it.image)}" alt="${escapeHtml(it.label)}">
      <div class="item-label">${escapeHtml(it.label)}</div>
      ${grantLabel}
      <div class="item-qty-controls">
        <button type="button" class="item-qty-btn" data-action="decrease" ${quantity <= 0 || claimed ? 'disabled' : ''}>-</button>
        <span class="item-qty-value">${quantity}</span>
        <button type="button" class="item-qty-btn" data-action="increase" ${total >= appState.maxChoices || quantity >= (it.maxQuantity || appState.maxChoices) || !canAffordAdditional(it.cost) || claimed ? 'disabled' : ''}>+</button>
      </div>
    `;
    if (!claimed) {
      card.querySelector('[data-action="decrease"]').onclick = event => {
        event.stopPropagation();
        changeItemQuantity(it, -1);
      };
      card.querySelector('[data-action="increase"]').onclick = event => {
        event.stopPropagation();
        changeItemQuantity(it, 1);
      };
      card.onclick = () => changeItemQuantity(it, 1);
    }
    grid.appendChild(card);
  });
}

function changeItemQuantity(it, delta) {
  const idx = selected.findIndex(s => s.item === it.item);
  const current = idx >= 0 ? Number(selected[idx].quantity || 0) : 0;
  const totalWithoutItem = selectedTotal() - current;
  const next = Math.max(0, current + delta);

  if (totalWithoutItem + next > appState.maxChoices) {
    showToast(`Starter pack limit reached. You can choose ${appState.maxChoices} total selections.`);
    return;
  }
  if (next > (it.maxQuantity || appState.maxChoices)) {
    showToast(`Selection limit reached for ${it.label}. You can choose ${it.maxQuantity || appState.maxChoices}.`);
    return;
  }

  const costWithoutItem = selectedCost() - (current * Number(it.cost || 0));
  if (costWithoutItem + (next * Number(it.cost || 0)) > Number(appState.budget || 0)) {
    showToast('Starter budget exceeded. Remove an item or vehicle before adding this selection.');
    return;
  }

  if (next <= 0) {
    if (idx >= 0) selected.splice(idx, 1);
  } else if (idx >= 0) {
    selected[idx].quantity = next;
  } else {
    selected.push({ ...it, quantity: next });
  }

  buildItemsGrid();
  renderVehicles();
  renderBudget();
  renderSlots();
}

function renderBudget() {
  const used = selectedCost();
  const budget = Number(appState.budget || 0);
  const remaining = Math.max(0, budget - used);
  document.getElementById('profile-label').textContent = `// ${appState.profileLabel}`;
  document.getElementById('budget-label').textContent = `${money(budget)} budget`;
  document.getElementById('budget-used').textContent = `${money(used)} used`;
  document.getElementById('budget-remaining').textContent = `${money(remaining)} remaining`;
  document.getElementById('budget-meter-fill').style.width = budget > 0 ? Math.min(100, Math.round((used / budget) * 100)) + '%' : '0%';
}

function renderVehicles() {
  const section = document.getElementById('vehicle-section');
  const grid = document.getElementById('vehicle-grid');
  const claimed = !!(appState.status && appState.status.starter && appState.status.starter.claimedStarterKit);
  if (!appState.vehicles.length) {
    section.style.display = 'none';
    return;
  }

  section.style.display = 'block';
  grid.innerHTML = '';
  appState.vehicles.forEach(vehicle => {
    const isSelected = selectedVehicle && selectedVehicle.model === vehicle.model;
    const currentVehicleCost = selectedVehicle ? Number(selectedVehicle.cost || 0) : 0;
    const currentVehicleSlots = selectedVehicle ? Number(selectedVehicle.countsAsChoices || 1) : 0;
    const projectedCost = selectedCost() - currentVehicleCost + Number(vehicle.cost || 0);
    const projectedSlots = selectedTotal() - currentVehicleSlots + Number(vehicle.countsAsChoices || 1);
    const disabled = claimed || (!isSelected && (projectedCost > Number(appState.budget || 0) || projectedSlots > appState.maxChoices));
    const card = document.createElement('div');
    card.className = `vehicle-card ${isSelected ? 'selected' : ''} ${disabled ? 'disabled' : ''}`;
    card.innerHTML = `
      <div class="vehicle-name">${escapeHtml(vehicle.label)}</div>
      <div class="vehicle-meta">${money(vehicle.cost)} / ${vehicle.countsAsChoices || 1} slot</div>
      <button type="button" class="vehicle-select-btn">${isSelected ? 'SELECTED' : 'SELECT'}</button>
    `;
    if (!claimed && !disabled) {
      card.onclick = () => {
        selectedVehicle = isSelected ? null : vehicle;
        renderVehicles();
        buildItemsGrid();
        renderBudget();
        renderSlots();
      };
    }
    grid.appendChild(card);
  });
}

function renderBonus() {
  const section = document.getElementById('bonus-section');
  const title = document.getElementById('bonus-title');
  const label = document.getElementById('bonus-reel-label');
  const bonus = appState.bonus;

  if (!bonus || !bonus.enabled || !Array.isArray(bonus.items) || bonus.items.length === 0) {
    section.style.display = 'none';
    return;
  }

  section.style.display = 'block';
  title.textContent = String(bonus.label || 'Welcome Bonus').toUpperCase();
  label.textContent = 'Bonus item will reveal when you claim.';
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function revealBonus(rolledBonus) {
  const bonus = appState.bonus;
  if (!rolledBonus || !bonus || !Array.isArray(bonus.items) || bonus.items.length === 0) return;

  const reel = document.getElementById('bonus-reel');
  const label = document.getElementById('bonus-reel-label');
  reel.classList.add('rolling');

  for (let i = 0; i < 18; i++) {
    const item = bonus.items[i % bonus.items.length];
    label.textContent = `${item.label} x${item.amount || 1}`;
    await sleep(55 + i * 8);
  }

  label.innerHTML = `
    <img class="bonus-image" src="${escapeHtml(rolledBonus.image)}" alt="">
    <span>${escapeHtml(rolledBonus.label)} x${rolledBonus.amount || 1}</span>
  `;
  reel.classList.remove('rolling');
  reel.classList.add('revealed');
}

function renderSlots() {
  const container = document.getElementById('selected-slots');
  const claimed = !!(appState.status && appState.status.starter && appState.status.starter.claimedStarterKit);
  container.innerHTML = '';
  const expanded = [];
  selected.forEach(item => {
    for (let i = 0; i < Number(item.quantity || 0); i++) {
      expanded.push(item);
    }
  });
  if (selectedVehicle) {
    for (let i = 0; i < Number(selectedVehicle.countsAsChoices || 1); i++) {
      expanded.push({
        label: selectedVehicle.label,
        image: '',
        isVehicle: true
      });
    }
  }

  for (let i = 0; i < appState.maxChoices; i++) {
    const el = document.createElement('div');
    if (expanded[i]) {
      el.className = 'slot-item';
      el.innerHTML = expanded[i].isVehicle
        ? `<span class="slot-item-vehicle">CAR</span> ${escapeHtml(expanded[i].label)} <span style="margin-left:auto;font-size:11px;color:var(--text-muted)">x1</span>`
        : `<img class="slot-item-image" src="${escapeHtml(expanded[i].image)}" alt=""> ${escapeHtml(expanded[i].label)} <span style="margin-left:auto;font-size:11px;color:var(--text-muted)">x1</span>`;
    } else {
      el.className = 'slot-empty';
      el.textContent = `Slot ${i + 1} - empty`;
    }
    container.appendChild(el);
  }
  const total = selectedTotal();
  document.getElementById('slot-count').textContent = total;
  document.querySelector('.slot-counter .total').textContent = ` / ${appState.maxChoices}`;
  const button = document.getElementById('btn-claim');
  const missingRequiredItem = total > 0 && !hasRequiredStarterItem();
  button.disabled = claimed || total === 0 || missingRequiredItem || pendingAction;
  button.textContent = claimed ? 'CLAIMED' : pendingAction ? 'WAIT...' : missingRequiredItem ? `${String(appState.requiredItemLabel || 'PHONE').toUpperCase()} REQUIRED` : 'CLAIM PACK';
}

async function claimKit() {
  if (selectedTotal() === 0 || pendingAction) return;
  if (!hasRequiredStarterItem()) {
    showToast(`Choose a ${appState.requiredItemLabel || 'phone'} first. You need it for the Taxi app and airport transportation.`);
    renderSlots();
    return;
  }
  pendingAction = true;
  renderSlots();
  const response = await nuiCallback('claimKit', {
    items: selected.map(it => ({ item: it.item, quantity: it.quantity })),
    vehicle: selectedVehicle ? selectedVehicle.model : null
  });
  pendingAction = false;
  if (!response.ok && response.message) showToast(response.message);
  if (response.ok && response.bonus) await revealBonus(response.bonus);
  selected = [];
  selectedVehicle = null;
  renderBudget();
  renderVehicles();
  renderSlots();
}

function renderJobs() {
  const grid = document.getElementById('jobs-grid');
  const currentJob = appState.status && appState.status.job;
  grid.innerHTML = '';
  appState.jobs.forEach(job => {
    const stats = Array.isArray(job.stats) ? job.stats : [];
    const selectedJob = currentJob === job.name;
    const unlockLocked = !!job.locked;
    const locked = unlockLocked;
    const card = document.createElement('div');
    card.className = `job-card ${selectedJob ? 'selected' : ''} ${locked ? 'locked' : ''}`;
    card.id = 'job-' + job.name;
    if (!locked) card.onclick = () => openJobConfirm(job);
    card.innerHTML = `
      <span class="job-emoji">${job.icon || '&#128188;'}</span>
      <div class="job-name">${escapeHtml(job.label).toUpperCase()}</div>
      <span class="job-tag">${unlockLocked ? 'UNLOCKS LATER' : 'CITY JOB'}</span>
      <div class="job-desc">${escapeHtml(unlockLocked ? (job.lockedDescription || 'Unlocks after your new citizen clearance is complete.') : (job.description || 'Allowed starter job for new citizens.'))}</div>
      <div class="job-stats">${stats.map(stat => `<div class="job-stat"><strong>${escapeHtml(stat.value)}</strong> ${escapeHtml(stat.label)}</div>`).join('')}</div>
      <button class="job-select-btn">${selectedJob ? 'SELECTED' : locked ? 'LOCKED' : 'SELECT JOB'}</button>
    `;
    grid.appendChild(card);
  });
}

function setJobConfirmModal(title, body, confirmLabel, cancelLabel = 'CANCEL') {
  document.getElementById('job-confirm-title').textContent = title;
  document.getElementById('job-confirm-body').textContent = body;
  document.getElementById('job-confirm-primary').textContent = confirmLabel;
  document.getElementById('job-confirm-secondary').textContent = cancelLabel;
}

function openStarterPackWarning(btn) {
  const claimedStarterKit = appState.status && appState.status.starter && appState.status.starter.claimedStarterKit;
  if (claimedStarterKit) {
    switchTab('starter', btn);
    return;
  }

  starterPackReturnTab = getActiveTab();
  pendingJobSelection = null;
  jobWarningOpen = false;
  starterPackWarningOpen = true;
  switchTab('starter', btn);
  setJobConfirmModal(
    'BEFORE YOU CHOOSE',
    'Your starter pack is based on your character profile, so male and female characters may see different item options. Choose carefully: stay within your starter budget and choice limit, and understand that some starter items may not be obtainable again after onboarding.',
    'VIEW STARTER PACK',
    'GO BACK'
  );
  document.body.classList.add('modal-open');
  document.getElementById('job-confirm-overlay').classList.add('show');
}

function openJobWarning() {
  pendingJobSelection = null;
  jobWarningOpen = true;
  starterPackWarningOpen = false;
  setJobConfirmModal(
    'JOB CENTER',
    'Choose a city job to start earning. You can return to the Job Center later to switch between available city jobs.',
    'SHOW JOBS',
    'GO BACK'
  );
  document.body.classList.add('modal-open');
  document.getElementById('job-confirm-overlay').classList.add('show');
}

function openJobConfirm(job) {
  if (job.locked) {
    showToast(job.lockedDescription || 'That job unlocks after your new citizen clearance is complete.');
    return;
  }

  pendingJobSelection = job;
  jobWarningOpen = false;
  starterPackWarningOpen = false;
  setJobConfirmModal(
    'CONFIRM JOB',
    `Set your city job to ${job.label}. This completes your first Job Center checklist task, and you can return later to change city jobs.`,
    'SET JOB'
  );
  document.body.classList.add('modal-open');
  document.getElementById('job-confirm-overlay').classList.add('show');
}

function closeJobConfirm() {
  const shouldReturnFromStarterPack = starterPackWarningOpen;
  const returnTab = starterPackReturnTab || 'checklist';
  pendingJobSelection = null;
  jobWarningOpen = false;
  starterPackWarningOpen = false;
  document.body.classList.remove('modal-open');
  document.getElementById('job-confirm-overlay').classList.remove('show');

  if (shouldReturnFromStarterPack) {
    switchTab(returnTab);
  }
}

function confirmJobSelection() {
  if (starterPackWarningOpen) {
    pendingJobSelection = null;
    jobWarningOpen = false;
    starterPackWarningOpen = false;
    document.body.classList.remove('modal-open');
    document.getElementById('job-confirm-overlay').classList.remove('show');
    return;
  }

  if (jobWarningOpen) {
    closeJobConfirm();
    switchTab('jobs');
    return;
  }

  if (!pendingJobSelection) return;
  const jobName = pendingJobSelection.name;
  closeJobConfirm();
  selectJob(jobName);
}

async function selectJob(name) {
  if (pendingAction) return;
  pendingAction = true;
  const response = await nuiCallback('selectJob', { job: name });
  pendingAction = false;
  if (!response.ok && response.message) showToast(response.message);
}

async function registerId() {
  if (pendingAction) return;
  pendingAction = true;
  const response = await nuiCallback('registerId');
  pendingAction = false;
  if (!response.ok && response.message) showToast(response.message);
}

function renderStatus() {
  const status = appState.status;
  if (!status) return;
  const playerName = (status.playerName || 'New Citizen').trim();
  document.getElementById('player-name').textContent = playerName.toUpperCase();
  document.getElementById('player-status').textContent = appState.mode === 'jobcenter' ? 'JOB CENTER' : `PLAYER ID: ${status.playerId || '--'}`;
  document.getElementById('bank-status').textContent = `BANK: ${money(status.bank)} / ${money(status.requiredBank)}`;
  document.getElementById('playtime-status').textContent = `PLAYTIME: ${minutes(status.playtime)}:00 / ${minutes(status.requiredPlaytime)}:00`;
  renderChecklist();
  renderBudget();
  buildItemsGrid();
  renderVehicles();
  renderBonus();
  renderSlots();
  renderJobs();
}

function applyTheme() {
  document.body.classList.toggle('theme-female', appState.theme === 'female');
  document.body.classList.toggle('jobcenter-mode', appState.mode === 'jobcenter');
}

function setData(data) {
  appState = {
    status: data.status || appState.status,
    items: data.items || appState.items,
    vehicles: data.vehicles || appState.vehicles,
    bonus: data.bonus !== undefined ? data.bonus : appState.bonus,
    budget: data.budget || appState.budget,
    profile: data.profile || appState.profile,
    profileLabel: data.profileLabel || appState.profileLabel,
    theme: data.theme || appState.theme,
    jobs: data.jobs || appState.jobs,
    maxChoices: data.maxChoices || appState.maxChoices,
    setJobFromMenu: data.setJobFromMenu !== undefined ? data.setJobFromMenu : appState.setJobFromMenu,
    requiredItem: data.requiredItem !== undefined ? data.requiredItem : appState.requiredItem,
    requiredItemLabel: data.requiredItemLabel || appState.requiredItemLabel,
    mode: data.mode || 'starter'
  };
  if (appState.status && appState.status.starter && appState.status.starter.claimedStarterKit) {
    selected = [];
    selectedVehicle = null;
  }
  applyTheme();
  renderStatus();
  if (appState.mode === 'jobcenter') {
    switchTab('jobs');
  } else if (data.tab) {
    switchTab(data.tab);
  }
}

function showToast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(window._toastTimer);
  window._toastTimer = setTimeout(() => t.classList.remove('show'), 2500);
}

window.addEventListener('message', event => {
  const data = event.data || {};
  if (data.action === 'setData') setData(data);
  if (data.action === 'show') {
    document.body.classList.add('ui-visible');
    document.body.classList.toggle('jobcenter-mode', data.mode === 'jobcenter');
    if (data.mode === 'jobcenter') {
      switchTab('jobs');
    } else if (data.tab) {
      switchTab(data.tab);
    }
  }
  if (data.action === 'hide') {
    document.body.classList.remove('ui-visible');
    document.body.classList.remove('modal-open');
    document.body.classList.remove('jobcenter-mode');
  }
});

window.addEventListener('keydown', event => {
  if (event.key === 'Escape') closeUi();
});

document.querySelectorAll('.tab-btn').forEach(button => {
  const text = button.textContent.toLowerCase();
  if (text.includes('checklist')) button.dataset.tab = 'checklist';
  if (text.includes('starter')) button.dataset.tab = 'starter';
  if (text.includes('job')) button.dataset.tab = 'jobs';
  if (text.includes('city')) button.dataset.tab = 'cityinfo';
});

nuiCallback('ready');

