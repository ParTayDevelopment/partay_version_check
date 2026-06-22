// [[ ParTay Keys - NUI Router ]]

window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (data.action === 'openFob') {
        const fob = document.getElementById('fob-container');
        if (fob && fob.style.display === 'block') {
            postNui('closeUI');
            closeAllPanels();
            return;
        }

        closeAllPanels();
        window.fobToken = data.token;
        window.fobKeyTier = data.keyTier || 'smart';
        window.fobBrand = data.brand || 'UNKNOWN';
        window.fobPlate = data.plate || '';
        window.fobKeyVersion = data.keyVersion || '';
        window.oledPowered = false;
        window.oledSection = null;
        document.getElementById('fob-container').style.display = 'block';
        document.getElementById('fob-brand-text').innerText = window.fobBrand;
        setFobCapabilities(window.fobKeyTier);
        fitFobBrandText();
    } else if (data.action === 'openContract') {
        closeAllPanels();
        window.pendingContract = {
            seller: data.sellerId,
            plate: data.plate,
            token: data.token
        };
        document.getElementById('contract-plate').innerText = `Plate: ${data.plate || 'UNKNOWN'}`;
        document.getElementById('contract-price').innerText = `$${Number(data.price || 0).toLocaleString()}`;
        document.getElementById('contract-container').style.display = 'block';
    } else if (data.action === 'openGpsTablet') {
        closeAllPanels();
        window.gpsTabletToken = data.token;
        openGpsTablet(data.trackers || []);
    } else if (data.action === 'openSignalFinder') {
        closeAllPanels();
        window.signalFinderToken = data.token;
        openSignalFinder(data);
    } else if (data.action === 'openServiceMenu') {
        closeAllPanels();
        openServiceMenu(data);
    } else if (data.action === 'locksmithJobApproved') {
        if (window.serviceMenu) {
            window.locksmithActiveJob = data.job;
            renderServiceVehicleDetail();
        }
    } else if (data.action === 'locksmithBusinessData') {
        if (window.serviceMenu) {
            window.serviceMenu.businessData = data.businessData || {};
            renderServiceBusiness();
        }
    } else if (data.action === 'alarmVoiceWarning') {
        speakAlarmWarning(data.message, data.repeats);
    } else if (data.action === 'openLocksmithSetup') {
        closeAllPanels();
        openLocksmithSetup(data);
    } else if (data.action === 'openKeyMenu') {
        closeAllPanels();
        openKeyMenu(data);
    } else if (data.action === 'closeUI') {
        closeAllPanels();
    }
});

function speakAlarmWarning(message, repeats) {
    if (!('speechSynthesis' in window) || typeof SpeechSynthesisUtterance === 'undefined') return;

    const text = String(message || 'Warning, unauthorized entry attempt.');
    const count = Math.max(1, Math.min(3, Number(repeats || 2)));
    window.speechSynthesis.cancel();

    for (let index = 0; index < count; index += 1) {
        const utterance = new SpeechSynthesisUtterance(text);
        utterance.rate = 0.92;
        utterance.pitch = 0.85;
        utterance.volume = 1.0;
        window.speechSynthesis.speak(utterance);
    }
}

function closeAllPanels() {
    if (window.signalScanTimer) {
        clearTimeout(window.signalScanTimer);
        window.signalScanTimer = null;
    }

    document.getElementById('fob-container').style.display = 'none';
    document.getElementById('contract-container').style.display = 'none';
    document.getElementById('tablet-container').style.display = 'none';
    document.getElementById('signal-container').style.display = 'none';
    document.getElementById('service-container').style.display = 'none';
    document.getElementById('locksmith-setup-container').style.display = 'none';
    document.getElementById('key-container').style.display = 'none';
    window.fobToken = null;
    window.gpsTabletToken = null;
    window.signalFinderToken = null;
    window.locksmithSetupToken = null;
    window.signalVehicle = null;
    window.signalTrackers = [];
    const tabletFrame = document.querySelector('.tablet-frame');
    if (tabletFrame) tabletFrame.classList.remove('screen-off');
    window.oledPowered = false;
    window.oledSection = null;
    renderOledScreen();
}

function clearServiceState() {
    window.serviceMenu = null;
    window.serviceToken = null;
    window.locksmithInvoiceServices = [];
    window.locksmithActiveJob = null;
    window.selectedServiceVehicle = null;
}

function formatIdentifier(value, fallback = '') {
    const raw = String(value || fallback || '').trim();
    if (!raw) return '';
    return raw
        .replace(/[_-]+/g, ' ')
        .replace(/\s+/g, ' ')
        .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function getLocksmithSetupGroups() {
    const setup = (window.locksmithSetup && window.locksmithSetup.setup) || {};
    const groups = {};
    (setup.locations || []).forEach((location) => {
        const name = location.locationName || location.location_name || 'Main Locksmith';
        if (!groups[name]) {
            groups[name] = {
                locationName: name,
                shopType: location.shopType || location.shop_type || setup.defaultShopType || 'player_owned',
                jobName: location.jobName || location.job_name || setup.defaultJobName || '',
                stockMethod: location.stockMethod || location.stock_method || '',
                savedStockMethod: location.savedStockMethod || location.stockMethod || location.stock_method || '',
                locationBlip: location.locationBlip || location.location_blip || null,
                active: false,
                points: {}
            };
        }

        groups[name].points[location.type] = location;
        groups[name].active = groups[name].active || location.active === true || location.active === 1;
        groups[name].shopType = location.shopType || location.shop_type || groups[name].shopType;
        groups[name].stockMethod = location.stockMethod || location.stock_method || groups[name].stockMethod;
        groups[name].savedStockMethod = location.savedStockMethod || location.stockMethod || location.stock_method || groups[name].savedStockMethod || '';
        groups[name].locationBlip = location.locationBlip || location.location_blip || groups[name].locationBlip || null;
    });

    Object.entries(window.locksmithSetupDrafts || {}).forEach(([name, draft]) => {
        if (!groups[name]) {
            groups[name] = {
                locationName: name,
                shopType: draft.shopType || setup.defaultShopType || 'player_owned',
                jobName: draft.jobName || setup.defaultJobName || '',
                stockMethod: draft.stockMethod || '',
                savedStockMethod: draft.savedStockMethod || '',
                locationBlip: draft.locationBlip || null,
                active: false,
                draft: true,
                points: {}
            };
        }
    });

    return groups;
}

function makeLocksmithSetupDraftName(groups) {
    let index = 1;
    let name = 'New Locksmith Shop';
    while (groups[name] || (window.locksmithSetupDrafts || {})[name]) {
        index += 1;
        name = `New Locksmith Shop ${index}`;
    }
    return name;
}

function setLocksmithSetupLocationName(nextName) {
    const name = nextName || 'New Locksmith Shop';
    const oldName = window.locksmithSetupLocation;
    const drafts = window.locksmithSetupDrafts || {};
    if (oldName && drafts[oldName] && oldName !== name) {
        drafts[name] = drafts[oldName];
        drafts[name].locationName = name;
        delete drafts[oldName];
    }
    window.locksmithSetupLocation = name;
}

function getCurrentLocksmithSetupLocation() {
    const setup = (window.locksmithSetup && window.locksmithSetup.setup) || {};
    const groups = getLocksmithSetupGroups();
    const nameInput = document.getElementById('locksmith-setup-location-name');
    const jobInput = document.getElementById('locksmith-setup-job-name');
    const shopTypeSelect = document.getElementById('locksmith-setup-shop-type');
    const canEditJobName = setup.canEditJobName !== false;
    const name = (nameInput && nameInput.value.trim()) || window.locksmithSetupLocation || 'Main Locksmith';
    const shopType = (shopTypeSelect && shopTypeSelect.value) || (groups[name] && groups[name].shopType) || setup.defaultShopType || 'player_owned';
    const group = groups[name] || {
        locationName: name,
        shopType,
        jobName: canEditJobName && shopType !== 'self_service' ? ((jobInput && jobInput.value.trim()) || setup.defaultJobName || '') : (setup.defaultJobName || ''),
        stockMethod: '',
        active: false,
        points: {}
    };

    group.locationName = name;
    group.shopType = shopType;
    group.jobName = shopType === 'self_service'
        ? ''
        : (canEditJobName ? ((jobInput && jobInput.value.trim()) || group.jobName || setup.defaultJobName || '') : (setup.defaultJobName || group.jobName || ''));
    const stockSelect = document.getElementById('locksmith-setup-stock-method');
    group.stockMethod = (stockSelect && stockSelect.value) || group.stockMethod || '';
    return group;
}

function finalizeCurrentLocksmithSetupLocation() {
    const location = getCurrentLocksmithSetupLocation();
    postNui('locksmithSetupFinalize', {
        token: window.locksmithSetupToken,
        locationName: location.locationName,
        shopType: location.shopType,
        stockMethod: location.stockMethod
    });
}

function openLocksmithSetup(data) {
    const setup = data.setup || {};
    const groups = {};
    (setup.locations || []).forEach((location) => {
        const name = location.locationName || location.location_name || 'Main Locksmith';
        groups[name] = true;
    });

    window.locksmithSetup = data || {};
    window.locksmithSetupToken = data.token;
    window.locksmithSetupRecipes = null;
    window.locksmithSetupSupplierContracts = null;
    window.locksmithSetupDrafts = window.locksmithSetupDrafts || {};
    Object.keys(groups).forEach((name) => {
        if (window.locksmithSetupDrafts[name]) delete window.locksmithSetupDrafts[name];
    });
    window.locksmithSetupSection = window.locksmithSetupSection || (setup.adminSetup === true ? 'universal' : 'locations');
    window.locksmithLocationMenuMode = window.locksmithLocationMenuMode || (setup.adminSetup === true ? 'shops' : 'location');
    window.locksmithSetupLocationPage = window.locksmithSetupLocationPage || 'main';
    if (window.locksmithSetupSection === 'universal' && setup.adminSetup !== true) {
        window.locksmithSetupSection = 'locations';
        window.locksmithLocationMenuMode = 'location';
    }
    window.locksmithSetupLocation = window.locksmithSetupLocation || Object.keys(groups)[0] || 'Main Locksmith';

    document.getElementById('locksmith-setup-location-name').value = window.locksmithSetupLocation;
    const current = getCurrentLocksmithSetupLocation();
    const jobInput = document.getElementById('locksmith-setup-job-name');
    const shopTypeSelect = document.getElementById('locksmith-setup-shop-type');
    const locationInput = document.getElementById('locksmith-setup-location-name');
    if (shopTypeSelect) {
        shopTypeSelect.innerHTML = (setup.shopTypes || [
            { type: 'player_owned', label: 'Player Owned' },
            { type: 'self_service', label: 'Self Service' }
        ]).map((shopType) => `<option value="${escapeHtml(shopType.type)}">${escapeHtml(shopType.label || formatIdentifier(shopType.type))}</option>`).join('');
        shopTypeSelect.value = current.shopType || setup.defaultShopType || 'player_owned';
        shopTypeSelect.disabled = setup.adminSetup !== true || current.active === true;
    }
    if (jobInput) {
        jobInput.value = current.shopType === 'self_service' ? '' : (setup.canEditJobName === false ? (setup.defaultJobName || '') : (current.jobName || setup.defaultJobName || ''));
        jobInput.disabled = setup.canEditJobName === false || current.shopType === 'self_service';
    }
    if (locationInput) locationInput.disabled = setup.adminSetup !== true;
    document.getElementById('locksmith-setup-stock-method').value = current.stockMethod || '';
    renderLocksmithSetup();
    document.getElementById('locksmith-setup-container').style.display = 'block';
}

function setLocksmithSetupSection(section) {
    const setup = (window.locksmithSetup && window.locksmithSetup.setup) || {};
    window.locksmithSetupSection = section === 'universal' && setup.adminSetup === true ? 'universal' : 'locations';
    if (window.locksmithSetupSection === 'locations') {
        window.locksmithLocationMenuMode = setup.adminSetup === true ? 'shops' : 'location';
        window.locksmithSetupLocationPage = 'main';
    }
    renderLocksmithSetup();
}

function getLocksmithUniversalPages() {
    return [
        {
            id: 'staff',
            title: 'Staff',
            copy: 'Employee grades and default job cleanup.'
        },
        {
            id: 'supply',
            title: 'Supply',
            copy: 'Warehouse pickup, contracts, and order prices.'
        },
        {
            id: 'recipes',
            title: 'Recipes',
            copy: 'Workbench outputs and component requirements.'
        },
        {
            id: 'blackmarket',
            title: 'Blackmarket',
            copy: 'Dealer placement, blip, currency, and prices.'
        }
    ];
}

function renderLocksmithSetupSidebar() {
    const sidebar = document.getElementById('locksmith-setup-sidebar');
    const setup = (window.locksmithSetup && window.locksmithSetup.setup) || {};
    const section = window.locksmithSetupSection || 'locations';
    const groups = getLocksmithSetupGroups();
    const names = Object.keys(groups).sort((a, b) => a.localeCompare(b));
    sidebar.innerHTML = '';

    if (section === 'universal' && setup.adminSetup === true) {
        const pages = getLocksmithUniversalPages();
        if (!pages.some((page) => page.id === window.locksmithUniversalPage)) {
            window.locksmithUniversalPage = pages[0].id;
        }

        pages.forEach((page) => {
            const button = document.createElement('button');
            button.className = `service-tab${page.id === window.locksmithUniversalPage ? ' active' : ''}`;
            button.type = 'button';
            button.innerHTML = `<span class="service-tab-title">${escapeHtml(page.title)}</span><span class="service-tab-copy">${escapeHtml(page.copy)}</span>`;
            button.addEventListener('click', () => {
                window.locksmithUniversalPage = page.id;
                renderLocksmithSetup();
            });
            sidebar.appendChild(button);
        });
        return;
    }

    if (section === 'locations' && (window.locksmithLocationMenuMode === 'location' || setup.adminSetup !== true)) {
        if (!['main', 'points'].includes(window.locksmithSetupLocationPage)) {
            window.locksmithSetupLocationPage = 'main';
        }

        if (setup.adminSetup === true) {
            const backButton = document.createElement('button');
            backButton.className = 'service-mini-btn locksmith-submenu-back';
            backButton.type = 'button';
            backButton.textContent = 'Back';
            backButton.addEventListener('click', () => {
                window.locksmithLocationMenuMode = 'shops';
                renderLocksmithSetup();
            });
            sidebar.appendChild(backButton);
        }

        [
            { id: 'main', title: 'Main', copy: 'Profile, stocking method, finalize, and shop management.' },
            { id: 'points', title: 'Points', copy: 'Place and update the physical setup points.' }
        ].forEach((page) => {
            const button = document.createElement('button');
            button.className = `service-tab${window.locksmithSetupLocationPage === page.id ? ' active' : ''}`;
            button.type = 'button';
            button.innerHTML = `<span class="service-tab-title">${escapeHtml(page.title)}</span><span class="service-tab-copy">${escapeHtml(page.copy)}</span>`;
            button.addEventListener('click', () => {
                window.locksmithSetupLocationPage = page.id;
                renderLocksmithSetup();
            });
            sidebar.appendChild(button);
        });
        return;
    }

    names.forEach((name) => {
        const group = groups[name];
        const button = document.createElement('button');
        button.className = `service-tab${name === window.locksmithSetupLocation ? ' active' : ''}`;
        button.type = 'button';
        const groupTypeLabel = group.shopType === 'self_service' ? 'Self Service' : 'Player Owned';
        const groupAccessLabel = group.shopType === 'self_service' ? 'NPC Clerk' : (group.jobName || 'No Job');
        button.innerHTML = `<span class="service-tab-title">${escapeHtml(name)}</span><span class="service-tab-copy">${escapeHtml(groupTypeLabel)} | ${escapeHtml(groupAccessLabel)} | ${group.active ? 'Active' : 'Draft'}${group.draft ? ' | Unsaved' : ''}</span>`;
        button.addEventListener('click', () => {
            const setup = (window.locksmithSetup && window.locksmithSetup.setup) || {};
            setLocksmithSetupLocationName(name);
            document.getElementById('locksmith-setup-location-name').value = name;
            document.getElementById('locksmith-setup-shop-type').value = group.shopType || setup.defaultShopType || 'player_owned';
            document.getElementById('locksmith-setup-job-name').value = group.shopType === 'self_service' ? '' : (setup.canEditJobName === false ? (setup.defaultJobName || '') : (group.jobName || ''));
            document.getElementById('locksmith-setup-stock-method').value = group.stockMethod || '';
            window.locksmithLocationMenuMode = 'location';
            window.locksmithSetupLocationPage = 'main';
            renderLocksmithSetup();
        });
        sidebar.appendChild(button);
    });

    if (setup.adminSetup === true) {
        const newButton = document.createElement('button');
        newButton.className = 'service-tab';
        newButton.type = 'button';
        newButton.innerHTML = `<span class="service-tab-title">+ New Shop</span><span class="service-tab-copy">Create a separate draft location.</span>`;
        newButton.addEventListener('click', () => {
            const name = makeLocksmithSetupDraftName(groups);
            window.locksmithSetupDrafts = window.locksmithSetupDrafts || {};
            window.locksmithSetupDrafts[name] = {
                locationName: name,
                shopType: setup.defaultShopType || 'player_owned',
                jobName: setup.defaultJobName || '',
                stockMethod: ''
            };
            setLocksmithSetupLocationName(name);
            window.locksmithSetupSection = 'locations';
            window.locksmithLocationMenuMode = 'location';
            window.locksmithSetupLocationPage = 'main';
            document.getElementById('locksmith-setup-location-name').value = name;
            document.getElementById('locksmith-setup-shop-type').value = setup.defaultShopType || 'player_owned';
            document.getElementById('locksmith-setup-job-name').value = setup.defaultJobName || '';
            document.getElementById('locksmith-setup-stock-method').value = '';
            renderLocksmithSetup();
        });
        sidebar.appendChild(newButton);
    }
}

function renderLocksmithSetup() {
    const setup = (window.locksmithSetup && window.locksmithSetup.setup) || {};
    const grid = document.getElementById('locksmith-setup-grid');
    const universalGrid = document.getElementById('locksmith-setup-universal-grid');
    const status = document.getElementById('locksmith-setup-status');
    const finalizeButton = document.getElementById('btn-locksmith-setup-finalize');
    const fields = document.querySelector('.locksmith-setup-fields');
    const locationHeader = document.querySelector('#locksmith-setup-container .service-detail-header');
    const location = getCurrentLocksmithSetupLocation();
    const pointSupportsShopType = (point, shopType) => {
        const shopTypes = point.shopTypes || point.shop_types;
        if (!shopTypes) {
            return shopType === 'self_service' ? point.type === 'fallback_ped' : point.type !== 'fallback_ped';
        }
        return shopTypes[shopType] === true;
    };
    const pointSupportsStockMethod = (point, stockMethod) => {
        if (!point.requiresStockMethod) return true;
        return String(point.requiresStockMethod) === String(stockMethod || '');
    };
    const pointSupportsGarageMode = (point) => {
        if (!point.requiresGarageMode) return true;
        return String(point.requiresGarageMode) === String((setup.garageSetup && setup.garageSetup.mode) || '');
    };
    const points = (setup.points || [])
        .filter((point) => pointSupportsShopType(point, location.shopType || 'player_owned'))
        .filter((point) => pointSupportsStockMethod(point, location.stockMethod))
        .filter((point) => pointSupportsGarageMode(point));
    const topLevelPoints = points.filter((point) => !point.subPointOf);
    const placedCount = topLevelPoints.filter((point) => location.points && location.points[point.type]).length;
    const requiredPoints = points.filter((point) => {
        if (!pointSupportsStockMethod(point, location.stockMethod)) return false;
        if (point.required !== false) return true;
        return point.requiresWith && location.points && location.points[point.requiresWith];
    });
    const requiredPlacedCount = requiredPoints.filter((point) => location.points && location.points[point.type]).length;
    const stockMethodRequired = location.shopType !== 'self_service';
    const stockMethodSelected = !stockMethodRequired || Boolean(location.stockMethod);
    const complete = requiredPoints.length > 0 && requiredPlacedCount >= requiredPoints.length && stockMethodSelected;
    const stockMethods = setup.stockMethods || [];
    const stockSelect = document.getElementById('locksmith-setup-stock-method');
    const shopTypeSelect = document.getElementById('locksmith-setup-shop-type');
    let section = window.locksmithSetupSection || 'locations';
    const locationsTab = document.getElementById('locksmith-setup-tab-locations');
    const universalTab = document.getElementById('locksmith-setup-tab-universal');
    const recipesTab = document.getElementById('locksmith-setup-tab-recipes');
    const sidebar = document.getElementById('locksmith-setup-sidebar');
    const setupTitle = document.querySelector('#locksmith-setup-container .service-title');
    const setupSubtitle = document.querySelector('#locksmith-setup-container .service-subtitle');

    if (section === 'recipes') {
        section = 'universal';
        window.locksmithSetupSection = 'universal';
        window.locksmithUniversalPage = 'recipes';
    }
    if (section === 'universal' && setup.adminSetup !== true) {
        section = 'locations';
        window.locksmithSetupSection = 'locations';
        window.locksmithLocationMenuMode = 'location';
    }
    const locationSubmenuActive = section === 'locations' && (window.locksmithLocationMenuMode === 'location' || setup.adminSetup !== true);
    const locationPage = window.locksmithSetupLocationPage || 'main';

    renderLocksmithSetupSidebar();
    if (locationsTab) locationsTab.classList.toggle('active', section === 'locations');
    if (universalTab) {
        universalTab.classList.toggle('active', section === 'universal');
        universalTab.style.display = setup.adminSetup === true ? 'inline-flex' : 'none';
    }
    if (recipesTab) {
        recipesTab.classList.remove('active');
        recipesTab.style.display = 'none';
    }
    if (setupTitle) setupTitle.textContent = section === 'universal' ? 'Universal Settings' : 'Business Locations';
    if (setupSubtitle) {
        setupSubtitle.textContent = section === 'universal'
            ? 'Configure global defaults, supply settings, recipes, and dealer behavior.'
            : 'Create a location, place every required point, then finalize it for use.';
    }
    const jobInput = document.getElementById('locksmith-setup-job-name');
    if (jobInput) jobInput.disabled = setup.canEditJobName === false || location.shopType === 'self_service';
    if (shopTypeSelect) shopTypeSelect.disabled = setup.adminSetup !== true || location.active === true;
    const locationInput = document.getElementById('locksmith-setup-location-name');
    if (locationInput) locationInput.disabled = setup.adminSetup !== true;
    const jobField = jobInput && jobInput.closest ? jobInput.closest('.service-inline-field') : null;
    const stockField = stockSelect && stockSelect.closest ? stockSelect.closest('.service-inline-field') : null;
    if (jobField) jobField.style.display = location.shopType === 'self_service' ? 'none' : 'flex';
    if (stockField) stockField.style.display = location.shopType === 'self_service' ? 'none' : 'flex';
    if (grid) grid.style.display = section === 'locations' ? 'grid' : 'none';
    if (universalGrid) universalGrid.style.display = section === 'universal' ? 'grid' : 'none';
    const recipesGrid = document.getElementById('locksmith-setup-recipes-grid');
    if (recipesGrid) recipesGrid.style.display = 'none';
    if (sidebar) sidebar.style.display = section === 'locations' || section === 'universal' ? 'flex' : 'none';
    const mainPane = document.querySelector('#locksmith-setup-container .service-main');
    if (mainPane) mainPane.style.gridColumn = '';
    if (fields) fields.style.display = section === 'locations' && locationSubmenuActive && locationPage === 'main' ? 'grid' : 'none';
    if (status) status.style.display = section === 'locations' && locationSubmenuActive && locationPage === 'points' ? 'block' : 'none';
    if (locationHeader) locationHeader.style.display = section === 'locations' && locationSubmenuActive && locationPage === 'main' ? 'flex' : 'none';

    if (section === 'universal') {
        renderLocksmithSetupUniversal();
        return;
    }
    grid.innerHTML = '';
    if (!locationSubmenuActive) {
        finalizeButton.disabled = true;
        grid.innerHTML = '<div class="service-empty wide">Select a shop from the left menu, or create a new shop.</div>';
        return;
    }
    if (stockSelect && !stockSelect.options.length) {
        stockSelect.innerHTML = [
            '<option value="">Select stocking method</option>',
            ...stockMethods.map((method) => `<option value="${escapeHtml(method.method)}">${escapeHtml(method.label || method.method)}</option>`)
        ].join('');
    }
    if (stockSelect) stockSelect.value = location.stockMethod || '';
    status.textContent = `${placedCount}/${topLevelPoints.length} setup points placed for ${location.locationName}. ${complete ? 'Ready to finalize.' : (stockMethodSelected ? 'Place every required point before finalizing.' : 'Choose a stocking method before finalizing.')}`;
    finalizeButton.disabled = !complete;

    if (locationPage === 'main') {
        const selectedMethod = stockMethods.find((method) => method.method === location.stockMethod);
        const savedMethod = location.savedStockMethod || '';
        const hasSavedStockMethod = savedMethod !== '';
        const methodChanged = hasSavedStockMethod && savedMethod !== location.stockMethod;

        if (location.shopType !== 'self_service') {
            const stockCard = document.createElement('div');
            stockCard.className = 'service-item-card wide locksmith-setup-card';
            stockCard.innerHTML = `
                <div>
                    <div class="service-item-title">Stocking Method</div>
                    <div class="service-item-copy">${escapeHtml(selectedMethod ? selectedMethod.description : 'Choose how this business location receives ordered stock.')}</div>
                    <div class="service-item-copy muted">${hasSavedStockMethod ? (methodChanged ? 'Method changed in the tablet. Save to apply it to this location.' : 'Method saved for this location.') : 'Choose a method and save it before finalizing this location.'}</div>
                </div>
                <div class="service-pill">${escapeHtml(methodChanged ? 'Unsaved Change' : (selectedMethod ? selectedMethod.label : 'Required'))}</div>
                <button class="service-primary-btn save-stock-method" type="button">${hasSavedStockMethod ? 'Change Method' : 'Save Method'}</button>
            `;
            stockCard.querySelector('.save-stock-method').addEventListener('click', () => {
                location.savedStockMethod = location.stockMethod || '';
                if (window.locksmithSetupDrafts && window.locksmithSetupDrafts[location.locationName]) {
                    window.locksmithSetupDrafts[location.locationName].savedStockMethod = location.savedStockMethod;
                }
                postNui('locksmithSetupSaveStockMethod', {
                    token: window.locksmithSetupToken,
                    locationName: location.locationName,
                    stockMethod: location.stockMethod
                });
                renderLocksmithSetup();
            });
            grid.appendChild(stockCard);
        }

        const locationBlip = location.locationBlip || {};
        const blipCoords = locationBlip.coords || {};
        const blipCard = document.createElement('article');
        blipCard.className = 'service-item-card wide locksmith-setup-card locksmith-setup-panel';
        blipCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Map Blip</div>
                <div class="service-item-copy">Optional public map marker for this shop. If no override position is set, the blip uses the best saved shop point.</div>
                <div class="invoice-line-list">
                    <div class="invoice-line static">
                        <span>Enabled</span>
                        <span class="business-action-row">
                            <input type="checkbox" ${locationBlip.enabled === true ? 'checked' : ''} data-location-blip="enabled">
                        </span>
                    </div>
                    <div class="invoice-line static">
                        <span>Label</span>
                        <span class="business-action-row">
                            <input class="service-inline-input" type="text" maxlength="40" value="${escapeHtml(locationBlip.label || location.locationName || 'Locksmith')}" data-location-blip="label">
                        </span>
                    </div>
                    <div class="invoice-line static">
                        <span>Sprite / Color / Scale</span>
                        <span class="business-action-row">
                            <input class="service-inline-input" type="number" min="0" value="${Number(locationBlip.sprite || 402)}" data-location-blip="sprite">
                            <input class="service-inline-input" type="number" min="0" value="${Number(locationBlip.color || 2)}" data-location-blip="color">
                            <input class="service-inline-input" type="number" min="0.1" step="0.05" value="${Number(locationBlip.scale || 0.75)}" data-location-blip="scale">
                        </span>
                    </div>
                    <div class="invoice-line static">
                        <span>Short Range</span>
                        <span class="business-action-row">
                            <input type="checkbox" ${locationBlip.shortRange === false ? '' : 'checked'} data-location-blip="shortRange">
                        </span>
                    </div>
                    <div class="invoice-line static">
                        <span>Override Position</span>
                        <span>${locationBlip.coords ? `${Number(blipCoords.x || 0).toFixed(2)}, ${Number(blipCoords.y || 0).toFixed(2)}, ${Number(blipCoords.z || 0).toFixed(2)}` : 'Auto from saved shop point'}</span>
                        <span class="business-action-row">
                            <button class="service-mini-btn" type="button" data-location-blip-position>Use Current Position</button>
                        </span>
                    </div>
                </div>
            </div>
            <button class="service-primary-btn" type="button" data-location-blip-save>Save Map Blip</button>
        `;
        grid.appendChild(blipCard);
        const readLocationBlip = (key) => blipCard.querySelector(`[data-location-blip="${key}"]`);
        const buildLocationBlipPayload = () => ({
            enabled: readLocationBlip('enabled')?.checked === true,
            label: String(readLocationBlip('label')?.value || location.locationName || 'Locksmith'),
            sprite: Number(readLocationBlip('sprite')?.value || 402),
            color: Number(readLocationBlip('color')?.value || 2),
            scale: Number(readLocationBlip('scale')?.value || 0.75),
            shortRange: readLocationBlip('shortRange')?.checked !== false,
            coords: locationBlip.coords || null
        });
        blipCard.querySelector('[data-location-blip-save]')?.addEventListener('click', () => {
            postNui('locksmithSetupSaveLocationBlip', {
                token: window.locksmithSetupToken,
                locationName: location.locationName,
                blip: buildLocationBlipPayload()
            });
        });
        blipCard.querySelector('[data-location-blip-position]')?.addEventListener('click', () => {
            postNui('locksmithSetupSetLocationBlipPosition', {
                token: window.locksmithSetupToken,
                locationName: location.locationName,
                blip: buildLocationBlipPayload()
            });
        });

        if (setup.adminSetup === true) {
            const manageCard = document.createElement('div');
            manageCard.className = 'service-item-card wide locksmith-setup-card';
            manageCard.innerHTML = `
                <div>
                    <div class="service-item-title">Shop Management</div>
                    <div class="service-item-copy">Admin-only controls for this whole shop location. Owners can tune assigned shop points, but cannot create, delete, or reassign shops.</div>
                </div>
                <button class="service-secondary-btn delete-shop" type="button">${location.draft ? 'Discard Draft' : 'Delete Shop'}</button>
            `;
            manageCard.querySelector('.delete-shop').addEventListener('click', () => {
                if (location.draft) {
                    delete (window.locksmithSetupDrafts || {})[location.locationName];
                    const groups = getLocksmithSetupGroups();
                    const nextName = Object.keys(groups).sort((a, b) => a.localeCompare(b))[0] || 'New Locksmith Shop';
                    setLocksmithSetupLocationName(nextName);
                    window.locksmithLocationMenuMode = 'shops';
                    window.locksmithSetupLocationPage = 'main';
                    document.getElementById('locksmith-setup-location-name').value = nextName;
                    renderLocksmithSetup();
                    return;
                }

                postNui('locksmithSetupClearPoint', {
                    token: window.locksmithSetupToken,
                    locationName: location.locationName,
                    pointType: 'all'
                });
            });
            grid.appendChild(manageCard);
        }
        return;
    }

    const pointsSaveCard = document.createElement('div');
    pointsSaveCard.className = 'service-item-card wide locksmith-setup-card';
    const saveLabel = location.active ? 'Save Changes' : 'Finalize Location';
    pointsSaveCard.innerHTML = `
        <div>
            <div class="service-item-title">${escapeHtml(saveLabel)}</div>
            <div class="service-item-copy">${escapeHtml(location.active ? 'Apply newly placed optional points and point changes to this active shop.' : 'Activate this shop after all required points are placed.')}</div>
            <div class="service-item-copy muted">${escapeHtml(complete ? 'Ready to save.' : (stockMethodSelected ? 'Place every required point before saving.' : 'Choose and save a stocking method before saving.'))}</div>
        </div>
        <button class="service-primary-btn points-save-location" type="button" ${complete ? '' : 'disabled'}>${escapeHtml(saveLabel)}</button>
    `;
    pointsSaveCard.querySelector('.points-save-location')?.addEventListener('click', finalizeCurrentLocksmithSetupLocation);
    grid.appendChild(pointsSaveCard);

    topLevelPoints.forEach((point) => {
        const placed = location.points && location.points[point.type];
        const childPoints = points.filter((candidate) => candidate.subPointOf === point.type);
        const coordOnly = point.coordOnly === true;
        const noRoutePoints = ['customer_pickup', 'management', 'status_sign', 'stock', 'timeclock', 'workbench'];
        const noStandSpotPoints = ['customer_pickup', 'management', 'status_sign', 'stock', 'timeclock'];
        const supportsRoutes = point.isPed !== true && !noRoutePoints.includes(point.type);
        const supportsStandSpot = point.isPed !== true && point.targetable !== false && !coordOnly && !noStandSpotPoints.includes(point.type);
        const showClearPoint = !coordOnly;
        const hasStandSpot = placed && placed.stockSettings && placed.stockSettings.standSpot;
        const routeCount = placed && placed.stockSettings && Array.isArray(placed.stockSettings.route) ? placed.stockSettings.route.length : 0;
        const stateCopy = placed
            ? (point.isPed === true
                ? `Clerk placed${placed.spawnProp === false ? ' using an existing MLO prop' : ''}.`
                : supportsRoutes
                    ? `${coordOnly ? 'Coordinate saved.' : `Point placed${placed.spawnProp === false ? ' using an existing MLO prop' : ''}.`} ${supportsStandSpot ? (hasStandSpot ? 'Stand spot set.' : 'No stand spot set.') : ''} ${routeCount ? `${routeCount} route point${routeCount === 1 ? '' : 's'} set.` : 'No route points set.'}`.replace(/\s+/g, ' ').trim()
                    : `Point placed${placed.spawnProp === false ? ' using an existing MLO prop' : ''}.`)
            : (point.required === false ? 'Optional point.' : 'Not placed yet.');
        const helpCopy = [point.description, point.routeDescription].filter(Boolean).join(' ');
        const garageSetup = setup.garageSetup || {};
        const garageSpawnPoint = childPoints.find((candidate) => candidate.type === 'vehicle_spawn');
        const garageSpawnPlaced = garageSpawnPoint && location.points && location.points[garageSpawnPoint.type];
        const garageProviderCopy = point.type === 'garage' && garageSetup.mode === 'provider'
            ? `Detected ${garageSetup.provider || 'garage'} provider. Mirror this garage as ${garageSetup.providerGarageName || 'partay_locksmith'} (${garageSetup.providerGarageType || 'job'}) in the garage resource.`
            : '';
        const card = document.createElement('div');
        card.className = 'service-item-card locksmith-setup-card';
        card.innerHTML = `
            <div class="setup-card-head">
                <div class="setup-card-info">
                    <div class="service-item-title">${escapeHtml(point.label || formatIdentifier(point.type))}</div>
                    <div class="service-item-copy">${escapeHtml(stateCopy)}</div>
                    ${helpCopy ? `<div class="service-item-copy muted">${escapeHtml(helpCopy)}</div>` : ''}
                    ${garageProviderCopy ? `<div class="service-item-copy muted">${escapeHtml(garageProviderCopy)}</div>` : ''}
                    ${point.type === 'garage' && garageSetup.mode === 'standalone' && garageSpawnPoint ? `<div class="service-item-copy muted">Vehicle spawn: ${garageSpawnPlaced ? 'saved' : 'not set'}.</div>` : ''}
                </div>
                <div class="service-pill">${placed ? (placed.active ? 'Active' : 'Draft') : 'Missing'}</div>
            </div>
            <div class="setup-card-actions">
                <button class="service-primary-btn place-point" type="button">${coordOnly ? (placed ? 'Reset Coordinate' : 'Set Coordinate') : (placed ? 'Re-Place Prop' : 'Place Prop')}</button>
                ${point.allowExistingProp ? `<button class="service-secondary-btn mlo-point" type="button">Use MLO Prop</button>` : ''}
                ${point.type === 'garage' && garageSetup.mode === 'standalone' && garageSpawnPoint ? `<button class="service-secondary-btn garage-spawn-point" type="button" ${placed ? '' : 'disabled'}>${garageSpawnPlaced ? 'Reset Vehicle Spawn' : 'Set Vehicle Spawn'}</button>` : ''}
                ${supportsStandSpot ? `<button class="service-secondary-btn stand-point" type="button" ${placed ? '' : 'disabled'}>${hasStandSpot ? 'Reset Stand Spot' : 'Set Stand Spot'}</button>` : ''}
                ${supportsRoutes ? `<button class="service-secondary-btn route-point" type="button" ${placed ? '' : 'disabled'}>Add Route Point</button>` : ''}
                ${supportsRoutes ? `<button class="service-secondary-btn route-clear" type="button" ${routeCount ? '' : 'disabled'}>Clear Route</button>` : ''}
                ${showClearPoint ? `<button class="service-secondary-btn clear-point" type="button" ${placed ? '' : 'disabled'}>Clear</button>` : ''}
            </div>
        `;

        card.querySelector('.place-point').addEventListener('click', () => {
            postNui('locksmithSetupPlacePoint', {
                token: window.locksmithSetupToken,
                locationName: location.locationName,
                shopType: location.shopType,
                jobName: location.jobName,
                pointType: point.type,
                stockMethod: location.stockMethod,
                model: point.model,
                coordOnly,
                isPed: point.isPed === true,
                spawnProp: !coordOnly
            });
        });

        const garageSpawnButton = card.querySelector('.garage-spawn-point');
        if (garageSpawnButton && garageSpawnPoint) {
            garageSpawnButton.addEventListener('click', () => {
                postNui('locksmithSetupPlacePoint', {
                    token: window.locksmithSetupToken,
                    locationName: location.locationName,
                    shopType: location.shopType,
                    jobName: location.jobName,
                    pointType: garageSpawnPoint.type,
                    stockMethod: location.stockMethod,
                    model: garageSetup.vehiclePreviewModel || garageSpawnPoint.model || 'speedo',
                    coordOnly: false,
                    isPed: false,
                    vehiclePreview: true,
                    spawnProp: false
                });
            });
        }

        const mloButton = card.querySelector('.mlo-point');
        if (mloButton) {
            mloButton.addEventListener('click', () => {
                postNui('locksmithSetupPlacePoint', {
                    token: window.locksmithSetupToken,
                    locationName: location.locationName,
                    shopType: location.shopType,
                    jobName: location.jobName,
                    pointType: point.type,
                    stockMethod: location.stockMethod,
                    model: point.model,
                    isPed: point.isPed === true,
                    spawnProp: false
                });
            });
        }

        const standButton = card.querySelector('.stand-point');
        if (standButton) {
            standButton.addEventListener('click', () => {
                postNui('locksmithSetupSetStandSpot', {
                    token: window.locksmithSetupToken,
                    locationName: location.locationName,
                    pointType: point.type
                });
            });
        }

        const routeButton = card.querySelector('.route-point');
        if (routeButton) {
            routeButton.addEventListener('click', () => {
                postNui('locksmithSetupAddRoutePoint', {
                    token: window.locksmithSetupToken,
                    locationName: location.locationName,
                    shopType: location.shopType,
                    jobName: location.jobName,
                    stockMethod: location.stockMethod,
                    pointType: point.type
                });
            });
        }

        const routeClearButton = card.querySelector('.route-clear');
        if (routeClearButton) {
            routeClearButton.addEventListener('click', () => {
                postNui('locksmithSetupClearRoute', {
                    token: window.locksmithSetupToken,
                    locationName: location.locationName,
                    pointType: point.type
                });
            });
        }

        const clearButton = card.querySelector('.clear-point');
        if (clearButton) {
            clearButton.addEventListener('click', () => {
                postNui('locksmithSetupClearPoint', {
                    token: window.locksmithSetupToken,
                    locationName: location.locationName,
                    pointType: point.type
                });
            });
        }

        grid.appendChild(card);
    });

}

function renderLocksmithSetupUniversal() {
    const setup = (window.locksmithSetup && window.locksmithSetup.setup) || {};
    const grid = document.getElementById('locksmith-setup-universal-grid');
    if (!grid) return;

    const stocking = setup.stocking || {};
    const contracts = getLocksmithSetupSupplierContracts();
    const prices = setup.prices || {};
    const orderPriceEntries = (prices.entries || []).filter((entry) => entry.category === 'order');
    const staffDefaults = setup.staffDefaults || {};
    const blackmarket = setup.blackmarket || {};
    const warehousePickup = setup.warehousePickup || {};
    const warehouseCoords = warehousePickup.coords || {};
    const warehouseBlip = warehousePickup.blip || {};
    const blackmarketCoords = blackmarket.coords || {};
    const blackmarketBlip = blackmarket.blip || {};

    grid.innerHTML = '';

    const appendCategory = (title, copy) => {
        const category = document.createElement('article');
        category.className = 'locksmith-setup-section-heading';
        category.innerHTML = `
            <div class="locksmith-setup-section-title">${escapeHtml(title)}</div>
            <div class="locksmith-setup-section-copy">${escapeHtml(copy || '')}</div>
        `;
        grid.appendChild(category);
    };

    const pages = getLocksmithUniversalPages();
    if (!pages.some((page) => page.id === window.locksmithUniversalPage)) {
        window.locksmithUniversalPage = pages[0].id;
    }
    const universalPage = window.locksmithUniversalPage || 'staff';

    if (universalPage === 'recipes') {
        renderLocksmithSetupRecipes(grid);
        return;
    }

    if (universalPage === 'staff') {
    appendCategory('Staff', 'Global employee defaults used by every player-owned locksmith location.');

    const staffCard = document.createElement('article');
    staffCard.className = 'service-item-card wide locksmith-setup-card locksmith-setup-panel';
    staffCard.innerHTML = `
        <div class="service-item-content">
            <div class="service-item-title">Staff Defaults</div>
            <div class="service-item-copy">Set the global hire grade, employee grade range, and job assignment used when staff are removed.</div>
            <div class="invoice-line-list">
                <div class="invoice-line static">
                    <span>Default Hire Grade</span>
                    <span class="business-action-row">
                        <input class="service-inline-input" type="number" min="0" value="${Number(staffDefaults.defaultHireGrade || 0)}" data-setup-staff-default="defaultHireGrade">
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Minimum Employee Grade</span>
                    <span class="business-action-row">
                        <input class="service-inline-input" type="number" min="0" value="${Number(staffDefaults.minEmployeeGrade || 0)}" data-setup-staff-default="minEmployeeGrade">
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Maximum Employee Grade</span>
                    <span class="business-action-row">
                        <input class="service-inline-input" type="number" min="0" value="${Number(staffDefaults.maxEmployeeGrade || 4)}" data-setup-staff-default="maxEmployeeGrade">
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Fire Job</span>
                    <span class="business-action-row">
                        <input class="service-inline-input" type="text" maxlength="40" value="${escapeHtml(staffDefaults.fireJob || 'unemployed')}" data-setup-staff-default="fireJob">
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Fire Grade</span>
                    <span class="business-action-row">
                        <input class="service-inline-input" type="number" min="0" value="${Number(staffDefaults.fireGrade || 0)}" data-setup-staff-default="fireGrade">
                    </span>
                </div>
            </div>
        </div>
        <button class="service-primary-btn" type="button" data-setup-staff-save>Save Defaults</button>
    `;
    grid.appendChild(staffCard);
    const readStaffDefault = (key) => staffCard.querySelector(`[data-setup-staff-default="${key}"]`);
    const staffSave = staffCard.querySelector('[data-setup-staff-save]');
    if (staffSave) {
        staffSave.addEventListener('click', () => {
            postNui('locksmithSetupSetStaffDefaults', {
                token: window.locksmithSetupToken,
                defaultHireGrade: Number(readStaffDefault('defaultHireGrade')?.value || 0),
                minEmployeeGrade: Number(readStaffDefault('minEmployeeGrade')?.value || 0),
                maxEmployeeGrade: Number(readStaffDefault('maxEmployeeGrade')?.value || 0),
                fireJob: String(readStaffDefault('fireJob')?.value || 'unemployed'),
                fireGrade: Number(readStaffDefault('fireGrade')?.value || 0)
            });
        });
    }
        return;
    }

    if (universalPage === 'supply') {
    appendCategory('Supply', 'Supplier contracts and stock order prices for every locksmith location.');

    const warehouseCard = document.createElement('article');
    warehouseCard.className = 'service-item-card wide locksmith-setup-card locksmith-setup-panel';
    warehouseCard.innerHTML = `
        <div class="service-item-content">
            <div class="service-item-title">Warehouse Pickup</div>
            <div class="service-item-copy">Global off-site pickup destination used by the Warehouse Pickup stocking method.</div>
            <div class="invoice-line-list">
                <div class="invoice-line static">
                    <span>Enabled</span>
                    <span class="business-action-row">
                        <input type="checkbox" ${warehousePickup.enabled === false ? '' : 'checked'} data-warehouse-setting="enabled">
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Position</span>
                    <span>${Number(warehouseCoords.x || 0).toFixed(2)}, ${Number(warehouseCoords.y || 0).toFixed(2)}, ${Number(warehouseCoords.z || 0).toFixed(2)}, ${Number(warehouseCoords.w || 0).toFixed(2)}</span>
                    <span class="business-action-row">
                        <button class="service-mini-btn" type="button" data-warehouse-position>Use Current Position</button>
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Pickup Ped</span>
                    <span class="business-action-row">
                        <input type="checkbox" ${warehousePickup.spawnPed === true ? 'checked' : ''} data-warehouse-setting="spawnPed">
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Ped Model</span>
                    <span class="business-action-row">
                        <input class="service-inline-input" type="text" maxlength="60" value="${escapeHtml(warehousePickup.pedModel || 's_m_m_warehouse_01')}" data-warehouse-setting="pedModel">
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Map Blip</span>
                    <span class="business-action-row">
                        <input type="checkbox" ${warehousePickup.showOnMap === true ? 'checked' : ''} data-warehouse-setting="showOnMap">
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Blip Label</span>
                    <span class="business-action-row">
                        <input class="service-inline-input" type="text" maxlength="40" value="${escapeHtml(warehouseBlip.label || 'Locksmith Warehouse')}" data-warehouse-blip="label">
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Blip Sprite / Color / Scale</span>
                    <span class="business-action-row">
                        <input class="service-inline-input" type="number" min="0" value="${Number(warehouseBlip.sprite || 473)}" data-warehouse-blip="sprite">
                        <input class="service-inline-input" type="number" min="0" value="${Number(warehouseBlip.color || 5)}" data-warehouse-blip="color">
                        <input class="service-inline-input" type="number" min="0.1" step="0.05" value="${Number(warehouseBlip.scale || 0.75)}" data-warehouse-blip="scale">
                    </span>
                </div>
            </div>
        </div>
        <button class="service-primary-btn" type="button" data-warehouse-save>Save Warehouse Pickup</button>
    `;
    grid.appendChild(warehouseCard);
    const readWarehouse = (key) => warehouseCard.querySelector(`[data-warehouse-setting="${key}"]`);
    const readWarehouseBlip = (key) => warehouseCard.querySelector(`[data-warehouse-blip="${key}"]`);
    const buildWarehousePayload = () => ({
        token: window.locksmithSetupToken,
        enabled: readWarehouse('enabled')?.checked === true,
        spawnPed: readWarehouse('spawnPed')?.checked === true,
        pedModel: String(readWarehouse('pedModel')?.value || 's_m_m_warehouse_01'),
        showOnMap: readWarehouse('showOnMap')?.checked === true,
        blip: {
            label: String(readWarehouseBlip('label')?.value || 'Locksmith Warehouse'),
            sprite: Number(readWarehouseBlip('sprite')?.value || 473),
            color: Number(readWarehouseBlip('color')?.value || 5),
            scale: Number(readWarehouseBlip('scale')?.value || 0.75)
        },
        coords: warehousePickup.coords || null
    });
    warehouseCard.querySelector('[data-warehouse-save]')?.addEventListener('click', () => {
        postNui('locksmithSetupSetWarehousePickupSettings', buildWarehousePayload());
    });
    warehouseCard.querySelector('[data-warehouse-position]')?.addEventListener('click', () => {
        postNui('locksmithSetupSetWarehousePickupPosition', { token: window.locksmithSetupToken });
    });

    const supplierCard = document.createElement('article');
    supplierCard.className = 'service-item-card wide locksmith-setup-card locksmith-setup-panel';
    supplierCard.innerHTML = `
        <div class="service-item-content">
            <div class="service-item-title">Supplier Contracts</div>
            <div class="service-item-copy">${contracts.length ? 'Edit the supplier contracts shop owners can choose from in their management tablet.' : 'No supplier contracts are configured.'}</div>
            <div class="invoice-line-list">
                ${contracts.map((contract, index) => `
                    <div class="invoice-line static supplier-contract-row">
                        <span class="business-action-row">
                            <input class="service-inline-input" type="text" maxlength="40" value="${escapeHtml(contract.id || '')}" data-setup-supplier-field="${index}:id" placeholder="id">
                            <input class="service-inline-input" type="text" maxlength="80" value="${escapeHtml(contract.label || '')}" data-setup-supplier-field="${index}:label" placeholder="label">
                        </span>
                        <span class="business-action-row">
                            <input class="service-inline-input" type="number" min="0.1" max="10" step="0.05" value="${Number(contract.priceMultiplier || 1).toFixed(2)}" data-setup-supplier-field="${index}:priceMultiplier" title="Price multiplier">
                            <input class="service-inline-input" type="number" min="0.1" max="10" step="0.05" value="${Number(contract.delayMultiplier || 1).toFixed(2)}" data-setup-supplier-field="${index}:delayMultiplier" title="Delay multiplier">
                        </span>
                        <span class="business-action-row">
                            <input class="service-inline-input" type="text" maxlength="180" value="${escapeHtml(contract.description || '')}" data-setup-supplier-field="${index}:description" placeholder="description">
                            <button class="service-mini-btn ${contract.enabled !== false ? 'active' : ''}" type="button" data-setup-supplier-toggle="${index}">${contract.enabled !== false ? 'Enabled' : 'Disabled'}</button>
                            <button class="service-mini-btn danger" type="button" data-setup-supplier-remove="${index}">Remove</button>
                        </span>
                    </div>
                `).join('')}
            </div>
        </div>
        <div class="business-action-row">
            <button class="service-mini-btn" type="button" data-setup-supplier-add>Add Contract</button>
            <button class="service-mini-btn" type="button" data-setup-supplier-reset>Reset Defaults</button>
            <button class="service-primary-btn" type="button" data-setup-supplier-save>Save Contracts</button>
        </div>
    `;
    grid.appendChild(supplierCard);
    supplierCard.querySelectorAll('[data-setup-supplier-field]').forEach((input) => {
        input.addEventListener('input', () => {
            const [indexRaw, field] = String(input.dataset.setupSupplierField || '').split(':');
            const index = Number(indexRaw);
            const contract = contracts[index];
            if (!contract || !field) return;
            if (field === 'id') {
                contract.id = normalizeSupplierContractId(input.value);
            } else if (field === 'priceMultiplier' || field === 'delayMultiplier') {
                contract[field] = Math.max(0.1, Math.min(Number(input.value || 1), 10));
            } else {
                contract[field] = input.value;
            }
        });
    });
    supplierCard.querySelectorAll('[data-setup-supplier-toggle]').forEach((button) => {
        button.addEventListener('click', () => {
            const contract = contracts[Number(button.dataset.setupSupplierToggle)];
            if (!contract) return;
            contract.enabled = contract.enabled === false;
            renderLocksmithSetupUniversal();
        });
    });
    supplierCard.querySelectorAll('[data-setup-supplier-remove]').forEach((button) => {
        button.addEventListener('click', () => {
            const index = Number(button.dataset.setupSupplierRemove);
            contracts.splice(index, 1);
            renderLocksmithSetupUniversal();
        });
    });
    supplierCard.querySelector('[data-setup-supplier-add]')?.addEventListener('click', () => {
        let nextId = 'new_supplier';
        let suffix = 1;
        while (contracts.some((contract) => contract.id === nextId)) {
            suffix += 1;
            nextId = `new_supplier_${suffix}`;
        }
        contracts.push({
            id: nextId,
            label: 'New Supplier',
            description: '',
            priceMultiplier: 1,
            delayMultiplier: 1,
            enabled: true
        });
        renderLocksmithSetupUniversal();
    });
    supplierCard.querySelector('[data-setup-supplier-reset]')?.addEventListener('click', () => {
        window.locksmithSetupSupplierContracts = null;
        postNui('locksmithSetupResetSupplierContracts', { token: window.locksmithSetupToken });
    });
    supplierCard.querySelector('[data-setup-supplier-save]')?.addEventListener('click', () => {
        postNui('locksmithSetupSaveSupplierContracts', {
            token: window.locksmithSetupToken,
            contracts
        });
    });

    const orderCard = document.createElement('article');
    orderCard.className = 'service-item-card wide locksmith-setup-card locksmith-setup-panel';
    orderCard.innerHTML = `
        <div class="service-item-content">
            <div class="service-item-title">Order Item Prices</div>
            <div class="service-item-copy">${orderPriceEntries.length ? 'Set the base order price before supplier contract multipliers.' : 'No order item prices are configured.'}</div>
            <div class="invoice-line-list">
                ${orderPriceEntries.map((entry, index) => `
                    <div class="invoice-line static">
                        <span>${escapeHtml(entry.label || entry.id || entry.key)}</span>
                        <span>${formatMoney(entry.current || 0)}</span>
                        <span class="business-action-row">
                            <input class="service-inline-input" type="number" min="0" value="${Number(entry.current || 0)}" data-setup-order-price="${index}">
                            <button class="service-mini-btn" type="button" data-setup-order-save="${index}">Save</button>
                        </span>
                    </div>
                `).join('')}
            </div>
        </div>
    `;
    grid.appendChild(orderCard);
    orderCard.querySelectorAll('[data-setup-order-save]').forEach((button) => {
        button.addEventListener('click', () => {
            const index = Number(button.dataset.setupOrderSave);
            const entry = orderPriceEntries[index];
            const input = orderCard.querySelector(`[data-setup-order-price="${index}"]`);
            if (!entry) return;

            postNui('locksmithSetupSetOrderPrice', {
                token: window.locksmithSetupToken,
                priceKey: entry.key,
                price: input ? Number(input.value || 0) : 0
            });
        });
    });
        return;
    }

    if (universalPage === 'blackmarket') {
    appendCategory('Blackmarket', 'Global dealer placement, map display, currency, and item prices.');

    const blackmarketCard = document.createElement('article');
    blackmarketCard.className = 'service-item-card wide locksmith-setup-card locksmith-setup-panel';
    blackmarketCard.innerHTML = `
        <div class="service-item-content">
            <div class="service-item-title">Blackmarket Dealer</div>
            <div class="service-item-copy">Use the current position button while standing where the dealer should appear.</div>
            <div class="invoice-line-list">
                <div class="invoice-line static">
                    <span>Enabled</span>
                    <span class="business-action-row">
                        <input type="checkbox" ${blackmarket.enabled === false ? '' : 'checked'} data-blackmarket-setting="enabled">
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Ped Model</span>
                    <span class="business-action-row">
                        <input class="service-inline-input" type="text" maxlength="60" value="${escapeHtml(blackmarket.model || 's_m_y_dealer_01')}" data-blackmarket-setting="model">
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Currency</span>
                    <span class="business-action-row">
                        <input class="service-inline-input" type="text" maxlength="40" value="${escapeHtml(blackmarket.currency || 'black_money')}" data-blackmarket-setting="currency">
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Position</span>
                    <span>${Number(blackmarketCoords.x || 0).toFixed(2)}, ${Number(blackmarketCoords.y || 0).toFixed(2)}, ${Number(blackmarketCoords.z || 0).toFixed(2)}, ${Number(blackmarketCoords.w || 0).toFixed(2)}</span>
                    <span class="business-action-row">
                        <button class="service-mini-btn" type="button" data-blackmarket-position>Use Current Position</button>
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Map Blip</span>
                    <span class="business-action-row">
                        <input type="checkbox" ${blackmarket.showOnMap === false ? '' : 'checked'} data-blackmarket-setting="showOnMap">
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Blip Label</span>
                    <span class="business-action-row">
                        <input class="service-inline-input" type="text" maxlength="40" value="${escapeHtml(blackmarketBlip.label || 'Blackmarket')}" data-blackmarket-blip="label">
                    </span>
                </div>
                <div class="invoice-line static">
                    <span>Blip Sprite / Color / Scale</span>
                    <span class="business-action-row">
                        <input class="service-inline-input" type="number" min="0" value="${Number(blackmarketBlip.sprite || 378)}" data-blackmarket-blip="sprite">
                        <input class="service-inline-input" type="number" min="0" value="${Number(blackmarketBlip.color || 1)}" data-blackmarket-blip="color">
                        <input class="service-inline-input" type="number" min="0.1" step="0.05" value="${Number(blackmarketBlip.scale || 0.75)}" data-blackmarket-blip="scale">
                    </span>
                </div>
                ${(blackmarket.items || []).map((item, index) => `
                    <div class="invoice-line static">
                        <span>${escapeHtml(item.label || item.item)}</span>
                        <span class="business-action-row">
                            <input class="service-inline-input" type="number" min="0" value="${Number(item.price || 0)}" data-blackmarket-item-price="${index}">
                        </span>
                    </div>
                `).join('')}
            </div>
        </div>
        <button class="service-primary-btn" type="button" data-blackmarket-save>Save Blackmarket</button>
    `;
    grid.appendChild(blackmarketCard);
    const readBlackmarket = (key) => blackmarketCard.querySelector(`[data-blackmarket-setting="${key}"]`);
    const readBlackmarketBlip = (key) => blackmarketCard.querySelector(`[data-blackmarket-blip="${key}"]`);
    const buildBlackmarketPayload = () => ({
        token: window.locksmithSetupToken,
        enabled: readBlackmarket('enabled')?.checked === true,
        model: String(readBlackmarket('model')?.value || 's_m_y_dealer_01'),
        currency: String(readBlackmarket('currency')?.value || 'black_money'),
        showOnMap: readBlackmarket('showOnMap')?.checked === true,
        blip: {
            label: String(readBlackmarketBlip('label')?.value || 'Blackmarket'),
            sprite: Number(readBlackmarketBlip('sprite')?.value || 378),
            color: Number(readBlackmarketBlip('color')?.value || 1),
            scale: Number(readBlackmarketBlip('scale')?.value || 0.75)
        },
        coords: blackmarket.coords || null,
        items: (blackmarket.items || []).map((item, index) => ({
            item: item.item,
            price: Number(blackmarketCard.querySelector(`[data-blackmarket-item-price="${index}"]`)?.value || 0)
        }))
    });
    blackmarketCard.querySelector('[data-blackmarket-save]')?.addEventListener('click', () => {
        postNui('locksmithSetupSetBlackmarketSettings', buildBlackmarketPayload());
    });
    blackmarketCard.querySelector('[data-blackmarket-position]')?.addEventListener('click', () => {
        postNui('locksmithSetupSetBlackmarketPosition', { token: window.locksmithSetupToken });
    });
    }
}

function getLocksmithSetupSupplierContracts() {
    const setup = (window.locksmithSetup && window.locksmithSetup.setup) || {};
    const stocking = setup.stocking || {};
    if (!Array.isArray(window.locksmithSetupSupplierContracts)) {
        const source = stocking.editableSupplierContracts || stocking.supplierContracts || [];
        window.locksmithSetupSupplierContracts = JSON.parse(JSON.stringify(source));
    }
    return window.locksmithSetupSupplierContracts;
}

function normalizeSupplierContractId(value) {
    return String(value || '')
        .trim()
        .toLowerCase()
        .replace(/[^a-z0-9_-]/g, '_')
        .replace(/^_+|_+$/g, '')
        .slice(0, 40);
}

function normalizeSetupRecipes() {
    const setup = (window.locksmithSetup && window.locksmithSetup.setup) || {};
    if (!Array.isArray(window.locksmithSetupRecipes)) {
        window.locksmithSetupRecipes = JSON.parse(JSON.stringify((setup.recipeSetup && setup.recipeSetup.recipes) || []));
    }
    return window.locksmithSetupRecipes;
}

function renderLocksmithSetupRecipes(targetGrid) {
    const grid = targetGrid || document.getElementById('locksmith-setup-recipes-grid');
    if (!grid) return;

    const setup = (window.locksmithSetup && window.locksmithSetup.setup) || {};
    const recipeSetup = setup.recipeSetup || {};
    const itemOptions = Array.isArray(recipeSetup.itemOptions) ? recipeSetup.itemOptions : [];
    const itemListId = 'locksmith-recipe-item-options';
    const itemListAttr = itemOptions.length ? ` list="${itemListId}"` : '';
    const recipes = normalizeSetupRecipes();
    grid.innerHTML = '';

    if (itemOptions.length) {
        const datalist = document.createElement('datalist');
        datalist.id = itemListId;
        datalist.innerHTML = itemOptions.map((item) => {
            const name = escapeHtml(item.name || '');
            const label = escapeHtml(item.label || item.name || '');
            return `<option value="${name}" label="${label}"></option>`;
        }).join('');
        grid.appendChild(datalist);
    }

    const introCard = document.createElement('article');
    introCard.className = 'service-item-card wide locksmith-setup-card';
    introCard.innerHTML = `
        <div class="service-item-content">
            <div class="service-item-title">Workbench Recipes</div>
            <div class="service-item-copy">Edit outputs, images, quantities, and required components for every locksmith workbench recipe.</div>
        </div>
        <div class="business-action-row">
            <button class="service-secondary-btn" type="button" data-recipes-add>Add Recipe</button>
            <button class="service-secondary-btn" type="button" data-recipes-reset>Reset Defaults</button>
            <button class="service-primary-btn" type="button" data-recipes-save>Save Recipes</button>
        </div>
    `;
    grid.appendChild(introCard);

    const collectRecipes = () => recipes.map((recipe, recipeIndex) => {
        const card = grid.querySelector(`[data-recipe-card="${recipeIndex}"]`);
        if (!card) return recipe;

        return {
            id: String(card.querySelector('[data-recipe-field="id"]')?.value || '').trim(),
            label: String(card.querySelector('[data-recipe-field="label"]')?.value || '').trim(),
            produces: String(card.querySelector('[data-recipe-field="produces"]')?.value || '').trim(),
            image: String(card.querySelector('[data-recipe-field="image"]')?.value || '').trim(),
            amount: Number(card.querySelector('[data-recipe-field="amount"]')?.value || 1),
            enabled: card.querySelector('[data-recipe-field="enabled"]')?.checked !== false,
            components: Array.from(card.querySelectorAll('[data-component-row]')).map((row) => ({
                item: String(row.querySelector('[data-component-field="item"]')?.value || '').trim(),
                label: String(row.querySelector('[data-component-field="label"]')?.value || '').trim(),
                amount: Number(row.querySelector('[data-component-field="amount"]')?.value || 1)
            })).filter((component) => component.item)
        };
    });

    const syncRecipes = () => {
        const collected = collectRecipes();
        recipes.splice(0, recipes.length, ...collected);
        window.locksmithSetupRecipes = recipes;
        return window.locksmithSetupRecipes;
    };

    introCard.querySelector('[data-recipes-add]')?.addEventListener('click', () => {
        syncRecipes();
        const index = recipes.length + 1;
        recipes.push({
            id: `custom_recipe_${index}`,
            label: `Custom Recipe ${index}`,
            produces: '',
            image: '',
            amount: 1,
            enabled: true,
            components: [{ item: '', label: '', amount: 1 }]
        });
        renderLocksmithSetupRecipes(grid);
    });
    introCard.querySelector('[data-recipes-reset]')?.addEventListener('click', () => {
        window.locksmithSetupRecipes = null;
        postNui('locksmithSetupResetRecipes', { token: window.locksmithSetupToken });
    });
    introCard.querySelector('[data-recipes-save]')?.addEventListener('click', () => {
        postNui('locksmithSetupSaveRecipes', {
            token: window.locksmithSetupToken,
            recipes: syncRecipes()
        });
    });

    recipes.forEach((recipe, recipeIndex) => {
        const card = document.createElement('article');
        card.className = 'service-item-card wide locksmith-setup-card';
        card.dataset.recipeCard = String(recipeIndex);
        card.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">${escapeHtml(recipe.label || recipe.id || 'Recipe')}</div>
                <div class="invoice-line-list">
                    <div class="invoice-line static">
                        <span>Enabled</span>
                        <span class="business-action-row"><input type="checkbox" ${recipe.enabled === false ? '' : 'checked'} data-recipe-field="enabled"></span>
                    </div>
                    <div class="invoice-line static">
                        <span>ID</span>
                        <span class="business-action-row"><input class="service-inline-input" type="text" maxlength="60" value="${escapeHtml(recipe.id || '')}" data-recipe-field="id"></span>
                    </div>
                    <div class="invoice-line static">
                        <span>Label</span>
                        <span class="business-action-row"><input class="service-inline-input" type="text" maxlength="80" value="${escapeHtml(recipe.label || '')}" data-recipe-field="label"></span>
                    </div>
                    <div class="invoice-line static">
                        <span>Output Item</span>
                        <span class="business-action-row"><input class="service-inline-input" type="text" maxlength="80"${itemListAttr} value="${escapeHtml(recipe.produces || '')}" data-recipe-field="produces"></span>
                    </div>
                    <div class="invoice-line static">
                        <span>Output Quantity</span>
                        <span class="business-action-row"><input class="service-inline-input" type="number" min="1" value="${Number(recipe.amount || 1)}" data-recipe-field="amount"></span>
                    </div>
                    <div class="invoice-line static">
                        <span>Image</span>
                        <span class="business-action-row"><input class="service-inline-input" type="text" maxlength="120" value="${escapeHtml(recipe.image || '')}" data-recipe-field="image"></span>
                    </div>
                    ${(recipe.components || []).map((component, componentIndex) => `
                        <div class="invoice-line static" data-component-row="${componentIndex}">
                            <span>Component ${componentIndex + 1}</span>
                            <span class="business-action-row">
                                <input class="service-inline-input" type="text" maxlength="80"${itemListAttr} placeholder="item" value="${escapeHtml(component.item || '')}" data-component-field="item">
                                <input class="service-inline-input" type="text" maxlength="80" placeholder="label" value="${escapeHtml(component.label || '')}" data-component-field="label">
                                <input class="service-inline-input" type="number" min="1" value="${Number(component.amount || 1)}" data-component-field="amount">
                                <button class="service-mini-btn" type="button" data-component-remove="${componentIndex}">Remove</button>
                            </span>
                        </div>
                    `).join('')}
                </div>
            </div>
            <div class="business-action-row">
                <button class="service-secondary-btn" type="button" data-recipe-component-add>Add Component</button>
                <button class="service-secondary-btn" type="button" data-recipe-duplicate>Duplicate</button>
                <button class="service-secondary-btn" type="button" data-recipe-remove>Remove Recipe</button>
            </div>
        `;
        grid.appendChild(card);

        card.querySelectorAll('[data-component-remove]').forEach((button) => {
            button.addEventListener('click', () => {
                syncRecipes();
                const componentIndex = Number(button.dataset.componentRemove);
                recipes[recipeIndex].components.splice(componentIndex, 1);
                if (!recipes[recipeIndex].components.length) {
                    recipes[recipeIndex].components.push({ item: '', label: '', amount: 1 });
                }
                renderLocksmithSetupRecipes(grid);
            });
        });
        card.querySelector('[data-recipe-component-add]')?.addEventListener('click', () => {
            syncRecipes();
            recipes[recipeIndex].components = recipes[recipeIndex].components || [];
            recipes[recipeIndex].components.push({ item: '', label: '', amount: 1 });
            renderLocksmithSetupRecipes(grid);
        });
        card.querySelector('[data-recipe-duplicate]')?.addEventListener('click', () => {
            syncRecipes();
            const copy = JSON.parse(JSON.stringify(recipes[recipeIndex]));
            copy.id = `${copy.id || 'recipe'}_copy`;
            copy.label = `${copy.label || 'Recipe'} Copy`;
            recipes.splice(recipeIndex + 1, 0, copy);
            renderLocksmithSetupRecipes(grid);
        });
        card.querySelector('[data-recipe-remove]')?.addEventListener('click', () => {
            syncRecipes();
            recipes.splice(recipeIndex, 1);
            renderLocksmithSetupRecipes(grid);
        });
    });
}

function setFobCapabilities(keyTier) {
    const fob = document.getElementById('fob-container');
    const remoteEngine = document.getElementById('btn-remote-engine');
    const power = document.getElementById('btn-oled-power');
    const buttons = document.querySelector('.fob-buttons');
    const fobImages = {
        smart: 'assets/fob_smart.png',
        advanced: 'assets/fob_advanced.png',
        oled: 'assets/fob_oled.png'
    };

    if (fob) {
        fob.style.backgroundImage = `url('${fobImages[keyTier] || 'assets/fob_base.png'}')`;
        fob.dataset.tier = keyTier;
    }

    if (remoteEngine) {
        remoteEngine.style.display = (keyTier === 'advanced' || keyTier === 'oled') ? 'flex' : 'none';
    }

    if (buttons) {
        buttons.style.display = keyTier === 'oled' ? 'none' : 'grid';
    }

    if (power) {
        power.style.display = keyTier === 'oled' ? 'flex' : 'none';
    }

    renderOledScreen();
}

function fitFobBrandText() {
    const brand = document.getElementById('fob-brand-text');
    if (!brand) return;

    const text = (brand.innerText || '').trim();
    const shouldWrap = text.length > 14;
    const maxFontSize = shouldWrap ? 12.5 : 17.6;
    const minFontSize = shouldWrap ? 7.5 : 5.5;
    const maxLetterSpacing = 2;
    const minLetterSpacing = 0;
    let fontSize = maxFontSize;
    let letterSpacing = maxLetterSpacing;
    let lineHeight = shouldWrap ? 0.92 : 1;

    brand.style.setProperty('--fob-brand-font-size', `${fontSize}px`);
    brand.style.setProperty('--fob-brand-letter-spacing', `${letterSpacing}px`);
    brand.style.setProperty('--fob-brand-line-height', String(lineHeight));
    brand.style.whiteSpace = shouldWrap ? 'normal' : 'nowrap';

    while ((brand.scrollWidth > brand.clientWidth || brand.scrollHeight > brand.clientHeight) && fontSize > minFontSize) {
        fontSize -= 0.5;
        letterSpacing = Math.max(minLetterSpacing, letterSpacing - 0.08);
        brand.style.setProperty('--fob-brand-font-size', `${fontSize}px`);
        brand.style.setProperty('--fob-brand-letter-spacing', `${letterSpacing}px`);
    }

    if (brand.scrollHeight > brand.clientHeight && shouldWrap) {
        brand.style.setProperty('--fob-brand-line-height', '0.82');
    }
}

// NUI Callback Router
function sendFobAction(actionType) {
    fetch(`https://${GetParentResourceName()}/fobAction`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: actionType, token: window.fobToken })
    });
}

function toggleOledPower() {
    if (window.fobKeyTier !== 'oled') return;
    window.oledPowered = !window.oledPowered;
    window.oledSection = null;
    renderOledScreen();
}

function openOledSection(section) {
    window.oledSection = section;
    renderOledScreen();
}

function renderOledScreen() {
    const fob = document.getElementById('fob-container');
    const brand = document.getElementById('fob-brand-text');
    const screen = document.getElementById('oled-screen');
    const home = document.getElementById('oled-home');
    const sectionPanel = document.getElementById('oled-section');
    const title = document.getElementById('oled-section-title');
    const content = document.getElementById('oled-section-content');

    if (!fob || !screen || !home || !sectionPanel || !title || !content) return;

    const isOled = window.fobKeyTier === 'oled';
    const isPowered = isOled && window.oledPowered;
    fob.dataset.oledPower = isPowered ? 'on' : 'off';
    screen.style.display = isOled ? 'block' : 'none';
    screen.setAttribute('aria-hidden', isPowered ? 'false' : 'true');

    if (brand) {
        brand.style.display = 'flex';
    }

    if (!isPowered) {
        home.style.display = 'none';
        sectionPanel.style.display = 'none';
        return;
    }

    const sections = {
        doors: {
            title: 'Doors',
            actions: [
                { label: 'Lock', action: 'lock' },
                { label: 'Unlock', action: 'unlock' },
                { label: 'Trunk', action: 'trunk' }
            ]
        },
        security: {
            title: 'Security',
            actions: [{ label: 'Panic', action: 'alarm' }]
        },
        lights: {
            title: 'Lights',
            actions: [{ label: 'Headlights', action: 'headlights' }]
        },
        valet: {
            title: 'Valet',
            actions: [{ label: 'Call Vehicle', action: 'valet' }]
        },
        info: {
            title: 'Info',
            actions: []
        }
    };

    const active = sections[window.oledSection];
    home.style.display = active ? 'none' : 'grid';
    sectionPanel.style.display = active ? 'block' : 'none';

    if (!active) return;

    title.innerText = active.title;

    if (window.oledSection === 'info') {
        const tier = (window.fobKeyTier || 'oled').replace(/_/g, ' ').toUpperCase();
        content.innerHTML = `
            <div class="oled-info-line"><span>Make</span><strong>${escapeHtml(window.fobBrand || 'UNKNOWN')}</strong></div>
            <div class="oled-info-line"><span>Plate</span><strong>${escapeHtml(window.fobPlate || 'UNKNOWN')}</strong></div>
            <div class="oled-info-line"><span>Version</span><strong>${escapeHtml(window.fobKeyVersion || 'UNKNOWN')}</strong></div>
            <div class="oled-info-line"><span>Tier</span><strong>${escapeHtml(tier)}</strong></div>
        `;
        return;
    }

    content.innerHTML = active.actions.map((item) => `
        <button class="oled-action-btn" type="button" data-fob-action="${item.action}">${item.label}</button>
    `).join('');
}

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, (char) => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
    }[char]));
}

function postNui(name, payload = {}) {
    return fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    }).catch((error) => {
        console.error(`NUI callback failed: ${name}`, error);
        return null;
    });
}

function formatMoney(amount) {
    return `$${Number(amount || 0).toLocaleString()}`;
}

function sanitizeQuantity(value) {
    const quantity = Number.parseInt(value, 10);
    if (Number.isNaN(quantity)) return 1;
    return Math.max(1, Math.min(quantity, 99));
}

function getServicePaymentOptions() {
    const menu = window.serviceMenu || {};
    return menu.paymentOptions && menu.paymentOptions.length ? menu.paymentOptions : [{ value: 'cash', label: 'Cash' }];
}

function setServiceSection(section) {
    const menu = window.serviceMenu || {};
    if (menu.service === 'blackmarket') section = 'shop';
    if (section === 'shop' && menu.service === 'locksmith' && menu.shopEnabled !== true) {
        section = menu.workstationMode || menu.ownerMode || menu.employeeMode ? 'business' : 'vehicles';
    }
    if (section === 'vehicles' && (menu.service === 'blackmarket' || menu.workstationMode || menu.vehicleServicesEnabled !== true)) {
        section = menu.shopEnabled === true ? 'shop' : 'business';
    }

    window.serviceSection = section;
    document.getElementById('service-vehicles-section').style.display = section === 'vehicles' ? 'block' : 'none';
    document.getElementById('service-shop-section').style.display = section === 'shop' ? 'block' : 'none';
    document.getElementById('service-business-section').style.display = section === 'business' ? 'block' : 'none';
    const businessSidebarTabs = document.getElementById('service-business-sidebar-tabs');
    if (businessSidebarTabs) {
        businessSidebarTabs.style.display = section === 'business' ? 'flex' : 'none';
    }

    document.querySelectorAll('.service-tab').forEach((tab) => {
        tab.classList.toggle('active', tab.dataset.section === section);
    });
}

function openServiceMenu(data) {
    window.serviceMenu = data || {};
    window.serviceToken = data.token;
    window.selectedServiceVehicle = (data.vehicles || [])[0] || null;
    window.locksmithInvoiceServices = [];
    window.locksmithActiveJob = data.activeJob || null;
    window.serviceBusinessTab = data.businessDefaultTab || window.serviceBusinessTab || null;
    window.serviceBusinessDrilldown = null;
    if (window.locksmithActiveJob && Array.isArray(data.vehicles)) {
        window.selectedServiceVehicle = data.vehicles.find((vehicle) => vehicle.plate === window.locksmithActiveJob.plate) || window.selectedServiceVehicle;
    }

    document.getElementById('service-kicker').innerText = data.service === 'blackmarket' ? 'OFF-BOOKS SUPPLY' : 'CERTIFIED SERVICE';
    document.getElementById('service-title').innerText = data.title || 'Welcome';
    document.getElementById('service-subtitle').innerText = data.subtitle || 'Please select from the available options.';
    document.getElementById('service-shop-title').innerText = data.shopTitle || 'Shop';
    document.getElementById('service-shop-copy').innerText = data.shopDescription || 'Choose an item and quantity.';
    document.getElementById('service-currency-label').innerText = data.currencyLabel || 'Cash / Bank';
    document.querySelector('#service-vehicles-section .service-section-title').innerText = data.employeeMode ? 'Nearby Customer Vehicles' : 'Nearby Owned Vehicles';
    document.querySelector('#service-vehicles-section .service-section-copy').innerText = data.employeeMode ? 'Registered customer vehicles close enough for service are shown here.' : 'Only vehicles registered to you are shown here.';

    const vehicleTab = document.getElementById('service-tab-vehicles');
    vehicleTab.style.display = data.service !== 'blackmarket' && data.vehicleServicesEnabled === true ? 'flex' : 'none';
    const shopTab = document.getElementById('service-tab-shop');
    shopTab.style.display = data.service === 'blackmarket' || data.shopEnabled === true ? 'flex' : 'none';
    const businessTab = document.getElementById('service-tab-business');
    businessTab.style.display = (data.ownerMode || data.employeeMode) ? 'flex' : 'none';
    businessTab.innerHTML = `
        <span class="service-tab-title">${data.workstationMode ? 'Workbench' : (data.employeeMode && !data.ownerMode ? 'Work Queue' : 'Business')}</span>
        <span class="service-tab-copy">${data.workstationMode ? 'Build stock.' : 'Manage shop operations.'}</span>
    `;

    renderServiceVehicles();
    renderServiceShop();
    renderServiceBusiness();
    setServiceSection(data.defaultSection || (data.service === 'blackmarket' ? 'shop' : 'vehicles'));
    document.getElementById('service-container').style.display = 'block';
}

function getLocksmithServiceLabel(service) {
    if (!service) return 'Vehicle Service';
    if (service.action === 'copy') return 'Physical Key Copy';
    if (service.action === 'recover') return 'Recover Possession';
    if (service.action === 'rekey') return 'Re-Key Vehicle';
    if (service.action === 'upgrade') return `Key System: ${service.tierLabel || service.label || service.tier || 'Change'}`;
    return service.title || 'Vehicle Service';
}

function addLocksmithInvoiceService(service) {
    window.locksmithInvoiceServices = window.locksmithInvoiceServices || [];
    const key = service.action === 'upgrade' ? `upgrade:${service.tier || ''}` : service.action;
    const existingIndex = window.locksmithInvoiceServices.findIndex((item) => {
        const itemKey = item.action === 'upgrade' ? `upgrade:${item.tier || ''}` : item.action;
        return itemKey === key;
    });

    if (existingIndex >= 0) {
        window.locksmithInvoiceServices.splice(existingIndex, 1, service);
    } else {
        window.locksmithInvoiceServices.push(service);
    }

    renderServiceVehicleDetail();
}

function removeLocksmithInvoiceService(index) {
    window.locksmithInvoiceServices = window.locksmithInvoiceServices || [];
    window.locksmithInvoiceServices.splice(index, 1);
    renderServiceVehicleDetail();
}

function renderLocksmithInvoicePanel(detail, vehicle) {
    const selected = window.locksmithInvoiceServices || [];
    if (!vehicle.employeeService) return;

    const panel = document.createElement('div');
    panel.className = 'service-action-card invoice-panel';
    const total = selected.reduce((sum, service) => sum + Number(service.fee || 0), 0);
    panel.innerHTML = `
        <div>
            <div class="service-card-title">Draft Invoice</div>
            <div class="service-card-copy">${selected.length ? 'Review selected services before presenting the clipboard.' : 'Select one or more services to build the customer invoice.'}</div>
            <div class="invoice-line-list">
                ${selected.map((service, index) => `
                    <button class="invoice-line" type="button" data-remove-invoice="${index}">
                        <span>${escapeHtml(getLocksmithServiceLabel(service))}</span>
                        <span>${formatMoney(service.fee)}</span>
                    </button>
                `).join('')}
            </div>
        </div>
        <div class="service-card-footer">
            <div class="service-price">${formatMoney(total)}</div>
            <button class="service-primary-btn" type="button" ${selected.length ? '' : 'disabled'}>Send Invoice</button>
        </div>
    `;

    panel.querySelectorAll('[data-remove-invoice]').forEach((button) => {
        button.addEventListener('click', () => removeLocksmithInvoiceService(Number(button.dataset.removeInvoice)));
    });

    panel.querySelector('.service-primary-btn').addEventListener('click', () => {
        if (!selected.length) return;
        postNui('locksmithSendInvoice', {
            token: window.serviceToken,
            customerId: vehicle.customerId,
            plate: vehicle.plate,
            netId: vehicle.netId,
            services: selected
        });
    });

    detail.appendChild(panel);
}

function renderLocksmithActiveJob(detail, vehicle) {
    const job = window.locksmithActiveJob;
    if (!job || !vehicle || job.plate !== vehicle.plate) return;

    const panel = document.createElement('div');
    panel.className = 'service-action-card invoice-panel approved';
    panel.innerHTML = `
        <div>
            <div class="service-card-title">Approved Job</div>
            <div class="service-card-copy">Complete the requested work, then present the mobile terminal for payment.</div>
            <div class="invoice-line-list">
                ${(job.services || []).map((service) => `
                    <div class="invoice-line static">
                        <span>${escapeHtml(getLocksmithServiceLabel(service))}</span>
                        <span>${formatMoney(service.fee)}</span>
                    </div>
                `).join('')}
            </div>
        </div>
        <div class="service-card-footer">
            <div class="service-price">${formatMoney(job.total)}</div>
            <button class="service-secondary-btn perform-job" type="button">Perform Work</button>
            <button class="service-primary-btn request-payment" type="button">Present Terminal</button>
        </div>
    `;

    panel.querySelector('.perform-job').addEventListener('click', () => {
        postNui('locksmithPerformJob', {
            token: window.serviceToken,
            id: job.id,
            plate: job.plate,
            netId: job.netId,
            services: job.services
        });
    });

    panel.querySelector('.request-payment').addEventListener('click', () => {
        postNui('locksmithRequestPayment', {
            token: window.serviceToken,
            id: job.id
        });
    });

    detail.appendChild(panel);
}

function renderServiceVehicles() {
    const list = document.getElementById('service-vehicle-list');
    const detail = document.getElementById('service-vehicle-detail');
    const menu = window.serviceMenu || {};
    const vehicles = menu.vehicles || [];

    list.innerHTML = '';
    detail.innerHTML = '';

    if (!vehicles.length) {
        list.innerHTML = `<div class="service-empty">${menu.employeeMode ? 'No customer vehicles are close enough for locksmith service.' : 'No owned vehicles are close enough for locksmith service.'}</div>`;
        detail.innerHTML = `<div class="service-empty detail-empty">${menu.employeeMode ? 'Ask the customer to stand nearby with their registered vehicle.' : 'Bring a registered vehicle nearby to recover possession, re-key, or upgrade the key system.'}</div>`;
        return;
    }

    vehicles.forEach((vehicle) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'service-vehicle-row';
        if (window.selectedServiceVehicle && window.selectedServiceVehicle.plate === vehicle.plate) {
            button.classList.add('active');
        }

        button.innerHTML = `
            <span class="service-row-title">${vehicle.label || 'Vehicle'}</span>
            <span class="service-row-meta">${vehicle.plate || 'UNKNOWN'} | ${Number(vehicle.distance || 0).toFixed(1)}m</span>
        `;
        button.addEventListener('click', () => {
            window.selectedServiceVehicle = vehicle;
            renderServiceVehicles();
        });
        list.appendChild(button);
    });

    renderServiceVehicleDetail();
}

function renderPaymentSelector(name, options, defaultValue) {
    return `
        <div class="service-payments ${options.length === 1 ? 'single' : ''}" data-payment-group="${name}">
            ${options.map((option, index) => `
                <button class="service-payment ${option.value === defaultValue || (!defaultValue && index === 0) ? 'active' : ''}" type="button" data-payment="${option.value}">
                    ${option.label}
                </button>
            `).join('')}
        </div>
    `;
}

function attachPaymentHandlers(root) {
    root.querySelectorAll('.service-payment').forEach((button) => {
        button.addEventListener('click', () => {
            const group = button.closest('.service-payments');
            group.querySelectorAll('.service-payment').forEach((item) => item.classList.remove('active'));
            button.classList.add('active');
        });
    });
}

function getSelectedPayment(root) {
    const active = root.querySelector('.service-payment.active');
    return active ? active.dataset.payment : 'cash';
}

function renderServiceVehicleDetail() {
    const detail = document.getElementById('service-vehicle-detail');
    const vehicle = window.selectedServiceVehicle;
    const menu = window.serviceMenu || {};
    const paymentOptions = getServicePaymentOptions();

    detail.innerHTML = '';
    if (!vehicle) return;

    const header = document.createElement('div');
    header.className = 'service-detail-header';
    header.innerHTML = `
        <div>
            <div class="service-detail-title">${vehicle.label || 'Vehicle'}</div>
            <div class="service-detail-subtitle">Plate ${vehicle.plate || 'UNKNOWN'}${vehicle.customerName ? ` | Customer ${escapeHtml(vehicle.customerName)}` : ''}</div>
        </div>
    `;
    detail.appendChild(header);

    renderLocksmithActiveJob(detail, vehicle);
    renderLocksmithInvoicePanel(detail, vehicle);

    const services = [
        {
            action: 'copy',
            title: 'Create Physical Copy',
            description: 'Creates a current legal physical key for the registered owner.',
            price: menu.serviceFees && menu.serviceFees.copy
        },
        {
            action: 'recover',
            title: 'Recover Possession',
            description: 'Updates possession so you can store the vehicle again. Existing same-version keys still work.',
            price: menu.serviceFees && menu.serviceFees.recover
        },
        {
            action: 'rekey',
            title: 'Re-Key Vehicle',
            description: 'Refreshes the key version, gives a new key, and invalidates older physical keys.',
            price: menu.serviceFees && menu.serviceFees.rekey
        }
    ];

    services.forEach((service) => {
        const card = document.createElement('div');
        card.className = 'service-action-card';
        card.innerHTML = `
            <div>
                <div class="service-card-title">${service.title}</div>
                <div class="service-card-copy">${service.description}</div>
            </div>
            <div class="service-card-footer">
                <div class="service-price">${formatMoney(service.price)}</div>
                ${vehicle.employeeService ? '' : renderPaymentSelector(`${service.action}-${vehicle.plate}`, paymentOptions)}
                <button class="service-primary-btn" type="button">${vehicle.employeeService ? 'Add' : 'Start'}</button>
            </div>
        `;
        if (!vehicle.employeeService) attachPaymentHandlers(card);
        card.querySelector('.service-primary-btn').addEventListener('click', () => {
            if (vehicle.employeeService) {
                addLocksmithInvoiceService({
                    action: service.action,
                    title: service.title,
                    fee: service.price
                });
                return;
            }

            postNui('serviceVehicleAction', {
                token: window.serviceToken,
                action: service.action,
                plate: vehicle.plate,
                netId: vehicle.netId,
                customerId: vehicle.employeeService ? vehicle.customerId : null,
                paymentMethod: getSelectedPayment(card)
            });
        });
        detail.appendChild(card);
    });

    const keyTiers = menu.keyTiers || [];
    if (keyTiers.length > 0) {
        const upgradeWrap = document.createElement('div');
        upgradeWrap.className = 'service-upgrade-wrap';
        upgradeWrap.innerHTML = '<div class="service-subheading">Change Key System</div><div class="key-tier-grid"></div>';

        const tierGrid = upgradeWrap.querySelector('.key-tier-grid');
        keyTiers.forEach((tier) => {
            tierGrid.appendChild(buildTierCard(tier, {
                button: vehicle.employeeService ? 'Add' : 'Change',
                paymentOptions: vehicle.employeeService ? [] : paymentOptions,
                onClick: (paymentMethod) => postNui('serviceVehicleAction', {
                    token: window.serviceToken,
                    action: 'upgrade',
                    plate: vehicle.plate,
                    netId: vehicle.netId,
                    customerId: vehicle.employeeService ? vehicle.customerId : null,
                    tier: tier.tier,
                    paymentMethod
                })
            }));

            if (vehicle.employeeService) {
                const lastCard = tierGrid.lastElementChild;
                const button = lastCard && lastCard.querySelector('button');
                if (button) {
                    button.replaceWith(button.cloneNode(true));
                    lastCard.querySelector('button').addEventListener('click', () => {
                        addLocksmithInvoiceService({
                            action: 'upgrade',
                            tier: tier.tier,
                            tierLabel: tier.label,
                            label: tier.label,
                            fee: tier.price
                        });
                    });
                }
            }
        });

        detail.appendChild(upgradeWrap);
    }
}

function renderServiceShop() {
    const grid = document.getElementById('service-shop-grid');
    const menu = window.serviceMenu || {};
    const items = menu.shopItems || [];
    const paymentOptions = getServicePaymentOptions();

    grid.innerHTML = '';

    if (menu.service === 'locksmith' && menu.shopEnabled === false) {
        grid.innerHTML = '<div class="service-empty wide">This locksmith is configured for services only.</div>';
        return;
    }

    if (!items.length) {
        grid.innerHTML = '<div class="service-empty wide">No shop inventory is available right now.</div>';
        return;
    }

    if (menu.customerOrderMode) {
        const info = document.createElement('article');
        info.className = 'service-item-card wide';
        info.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Staffed Register</div>
                <div class="service-item-copy">Your purchase creates a paid shop order. A locksmith employee will fill it from business stock and place it at the pick-up point.</div>
            </div>
            <div class="service-pill">Customer View</div>
        `;
        grid.appendChild(info);
    }

    items.forEach((item) => {
        const card = document.createElement('article');
        card.className = 'service-item-card';
        card.innerHTML = `
            <div class="service-item-media">
                <img class="service-item-img" src="${item.image || ''}" alt="">
            </div>
            <div class="service-item-content">
                <div class="service-item-title">${item.label || item.item}</div>
                <div class="service-item-copy">${item.description || 'Specialty service item.'}</div>
            </div>
            <div class="service-item-controls">
                <div class="service-price" data-unit-price="${item.price}">${formatMoney(item.price)}</div>
                <div class="service-quantity">
                    <button type="button" data-qty-step="-1">-</button>
                    <input type="number" min="1" max="99" value="1" inputmode="numeric">
                    <button type="button" data-qty-step="1">+</button>
                </div>
                ${renderPaymentSelector(`shop-${item.item}`, paymentOptions)}
                <button class="service-primary-btn" type="button">${menu.customerOrderMode ? 'Place Order' : 'Purchase'}</button>
            </div>
        `;

        const input = card.querySelector('input');
        const price = card.querySelector('.service-price');
        const updateTotal = () => {
            input.value = sanitizeQuantity(input.value);
            price.innerText = formatMoney(Number(item.price || 0) * sanitizeQuantity(input.value));
        };

        card.querySelectorAll('[data-qty-step]').forEach((button) => {
            button.addEventListener('click', () => {
                input.value = sanitizeQuantity(input.value) + Number(button.dataset.qtyStep);
                updateTotal();
            });
        });
        input.addEventListener('input', updateTotal);
        attachPaymentHandlers(card);
        card.querySelector('.service-primary-btn').addEventListener('click', () => {
            const quantity = sanitizeQuantity(input.value);
            postNui('serviceShopPurchase', {
                token: window.serviceToken,
                service: menu.service,
                item: item.item,
                price: item.price,
                quantity,
                paymentMethod: getSelectedPayment(card)
            });
        });

        grid.appendChild(card);
    });
}

function renderServiceBusiness() {
    const grid = document.getElementById('service-business-grid');
    const status = document.getElementById('service-business-status');
    const businessSidebarTabs = document.getElementById('service-business-sidebar-tabs');
    if (!grid) return;

    const menu = window.serviceMenu || {};
    const business = menu.businessData || {};
    const stock = business.stock || {};
    const supplierOrders = ((business.stocking || {}).orders) || [];
    const recipes = business.recipes || [];
    const isWorkbench = menu.workstationMode === true;
    const isStockMode = menu.stockMode === true;
    const permissions = business.permissions || {};
    const permissionAllowed = permissions.allowed || {};

    grid.innerHTML = '';
    if (businessSidebarTabs) businessSidebarTabs.innerHTML = '';
    if (status) status.innerText = `${Number(business.onlineEmployees || 0)} On Duty`;

    if (!(menu.ownerMode || menu.employeeMode) || business.allowed !== true) {
        grid.innerHTML = `<div class="service-empty wide">${isWorkbench ? 'This workstation is available to authorized locksmith staff.' : 'Business management is available to authorized locksmith owners.'}</div>`;
        return;
    }

    const ownerAccess = business.ownerAccess !== false && menu.ownerMode === true;
    const canUseManagement = (key) => ownerAccess || permissionAllowed[key] === true;
    const reportPageDefinitions = [
        { id: 'reports_revenue', title: 'Revenue', copy: 'Revenue totals and summary.' },
        { id: 'reports_invoices', title: 'Invoices', copy: 'Customer invoice history.' },
        { id: 'reports_orders', title: 'Orders', copy: 'Completed supplier orders.' },
        { id: 'reports_logs', title: 'Logs', copy: 'Business activity log.' }
    ];
    const operationsPageDefinitions = [
        { id: 'operations_status', title: 'Status', copy: 'Shop status and on-call contact.' },
        { id: 'operations_pricing', title: 'Pricing', copy: 'Service price controls.' },
        { id: 'operations_funds', title: 'Funds', copy: 'Society balance and transfers.' }
    ];
    const staffPageDefinitions = [
        { id: 'staff_main', title: 'Main', copy: 'Employees, payroll, and hiring.' },
        ...(ownerAccess ? [{ id: 'staff_permissions', title: 'Permissions', copy: 'Employee management access.' }] : [])
    ];
    const inReportsDrilldown = window.serviceBusinessDrilldown === 'reports'
        && !isWorkbench
        && !isStockMode
        && canUseManagement('Reports');
    const inOperationsDrilldown = window.serviceBusinessDrilldown === 'operations'
        && !isWorkbench
        && !isStockMode
        && ownerAccess;
    const inStaffDrilldown = window.serviceBusinessDrilldown === 'staff'
        && !isWorkbench
        && !isStockMode
        && (ownerAccess || canUseManagement('Payroll') || canUseManagement('Candidates'));
    const inBusinessDrilldown = inReportsDrilldown || inOperationsDrilldown || inStaffDrilldown;
    const categoryDefinitions = inReportsDrilldown
        ? reportPageDefinitions
        : inOperationsDrilldown
            ? operationsPageDefinitions
            : inStaffDrilldown
                ? staffPageDefinitions
        : isWorkbench
        ? [{ id: 'build', title: 'Build Stock', copy: 'Craft locksmith inventory.' }]
        : isStockMode
            ? [{ id: 'stock', title: 'Stock', copy: 'Inventory and supplier orders.' }]
        : [
            { id: 'queue', title: 'Queue', copy: 'Orders and appointments.' },
            ...(ownerAccess ? [{ id: 'supply', title: 'Supply', copy: 'Supplier contracts and stock orders.' }] : []),
            ...(ownerAccess ? [{ id: 'operations', title: 'Operations', copy: 'Pricing, funds, and status.' }] : []),
            ...((ownerAccess || canUseManagement('Payroll') || canUseManagement('Candidates')) ? [{ id: 'staff', title: 'Staff', copy: 'Employees, payroll, and hiring.' }] : []),
            ...(canUseManagement('Reports') ? [{ id: 'reports', title: 'Reports', copy: 'Revenue, invoices, and logs.' }] : [])
        ];
    const businessTabs = businessSidebarTabs || document.createElement('div');
    businessTabs.className = businessSidebarTabs ? 'service-business-sidebar-tabs' : 'service-business-tabs';
    businessTabs.innerHTML = '';
    const businessPanels = document.createElement('div');
    businessPanels.className = 'service-business-panels';
    const panels = {};
    const firstCategory = (categoryDefinitions[0] && categoryDefinitions[0].id) || 'queue';
    if (!categoryDefinitions.some((category) => category.id === window.serviceBusinessTab)) {
        window.serviceBusinessTab = firstCategory;
    }
    const updateBusinessHeading = (categoryId) => {
        const category = categoryDefinitions.find((item) => item.id === categoryId) || categoryDefinitions[0];
        const title = document.getElementById('service-business-title');
        const copy = document.getElementById('service-business-copy');
        if (title) title.innerText = inReportsDrilldown && category
            ? `Reports: ${category.title}`
            : inOperationsDrilldown && category
                ? `Operations: ${category.title}`
                : inStaffDrilldown && category
                    ? `Staff: ${category.title}`
                : (category ? category.title : 'Business');
        if (copy) copy.innerText = category ? category.copy : 'Manage shop operations.';
    };

    const activateBusinessTab = (categoryId) => {
        if ((categoryId === 'reports' || categoryId === 'operations' || categoryId === 'staff') && !window.serviceBusinessDrilldown) {
            window.serviceBusinessDrilldown = categoryId;
            window.serviceBusinessReturnTab = window.serviceBusinessTab && window.serviceBusinessTab !== categoryId ? window.serviceBusinessTab : 'queue';
            window.serviceBusinessTab = categoryId === 'reports'
                ? 'reports_revenue'
                : categoryId === 'operations'
                    ? 'operations_status'
                    : 'staff_main';
            renderServiceBusiness();
            setServiceSection('business');
            return;
        }

        window.serviceBusinessTab = categoryId;
        setServiceSection('business');
        updateBusinessHeading(categoryId);
        businessTabs.querySelectorAll('[data-business-tab]').forEach((button) => {
            button.classList.toggle('active', button.dataset.businessTab === categoryId);
        });
        businessPanels.querySelectorAll('[data-business-panel]').forEach((panel) => {
            panel.classList.toggle('active', panel.dataset.businessPanel === categoryId);
        });
    };

    if (inReportsDrilldown || inOperationsDrilldown || inStaffDrilldown) {
        const backButton = document.createElement('button');
        backButton.className = businessSidebarTabs ? 'service-business-sidebar-back' : 'service-mini-btn';
        backButton.type = 'button';
        backButton.innerText = 'Back';
        backButton.addEventListener('click', () => {
            window.serviceBusinessDrilldown = null;
            window.serviceBusinessTab = window.serviceBusinessReturnTab || 'queue';
            renderServiceBusiness();
            setServiceSection('business');
        });
        businessTabs.appendChild(backButton);
    }

    categoryDefinitions.forEach((category) => {
        const button = document.createElement('button');
        button.className = `${businessSidebarTabs ? 'service-business-sidebar-tab' : 'service-business-tab'}${window.serviceBusinessTab === category.id ? ' active' : ''}`;
        button.type = 'button';
        button.dataset.businessTab = category.id;
        button.innerHTML = `
            <span class="service-business-tab-title">${escapeHtml(category.title)}</span>
            <span class="service-business-tab-copy">${escapeHtml(category.copy)}</span>
        `;
        button.addEventListener('click', () => activateBusinessTab(category.id));
        businessTabs.appendChild(button);

        const panel = document.createElement('div');
        panel.className = `service-business-panel${window.serviceBusinessTab === category.id ? ' active' : ''}`;
        panel.dataset.businessPanel = category.id;
        panels[category.id] = panel;
        businessPanels.appendChild(panel);
    });

    if (!businessSidebarTabs) {
        grid.appendChild(businessTabs);
    }
    grid.appendChild(businessPanels);
    updateBusinessHeading(window.serviceBusinessTab);

    const appendBusinessCard = (categoryId, card) => {
        const panel = panels[categoryId] || panels[firstCategory];
        if (panel) panel.appendChild(card);
    };

    const finalizeBusinessTabs = () => {
        categoryDefinitions.forEach((category) => {
            const panel = panels[category.id];
            if (!panel || panel.children.length > 0) return;
            const empty = document.createElement('div');
            empty.className = 'service-empty wide';
            empty.innerText = `No ${category.title.toLowerCase()} tools are available here.`;
            panel.appendChild(empty);
        });
    };

    if (inStaffDrilldown && ownerAccess) {
        const permissionDefinitions = permissions.definitions || [];
        if (permissionDefinitions.length) {
            const permissionCard = document.createElement('article');
            permissionCard.className = 'service-item-card wide';
            permissionCard.innerHTML = `
                <div class="service-item-content">
                            <div class="service-item-title">Employee Permissions</div>
                            <div class="service-item-copy">Set the minimum job grade required for services and management tools at this location.</div>
                    <div class="invoice-line-list">
                        ${permissionDefinitions.map((permission, index) => `
                            <div class="invoice-line static">
                                <span>${escapeHtml(permission.label || permission.key)}</span>
                                <span class="business-action-row">
                                    <input class="service-inline-input" type="number" min="0" max="99" value="${Number(permission.minGrade || 0)}" data-permission-grade="${index}">
                                    <button class="service-mini-btn" type="button" data-permission-save="${index}">Save</button>
                                </span>
                            </div>
                        `).join('')}
                    </div>
                </div>
            `;
            appendBusinessCard('staff_permissions', permissionCard);
            permissionCard.querySelectorAll('[data-permission-save]').forEach((button) => {
                button.addEventListener('click', () => {
                    const index = Number(button.dataset.permissionSave);
                    const permission = permissionDefinitions[index];
                    const input = permissionCard.querySelector(`[data-permission-grade="${index}"]`);
                    if (!permission) return;
                    postNui('locksmithSetManagementPermission', {
                        token: window.serviceToken,
                        permissionKey: permission.key,
                        minGrade: input ? Number(input.value || 0) : 0
                    });
                });
            });
        }
    }

    if (inOperationsDrilldown) {
        const statusCard = document.createElement('article');
        statusCard.className = 'service-item-card wide';
        const shopStatus = business.shopStatus || 'open';
        statusCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Shop Operating Status</div>
                <div class="service-item-copy">Open allows fallback service, on-call routes customers to employees, closed blocks public service. Status signs show this value in-world.</div>
                <div class="business-action-row">
                    ${['open', 'on_call', 'closed'].map((status) => `
                        <button class="service-mini-btn ${shopStatus === status ? 'active' : ''}" type="button" data-shop-status="${status}">${formatIdentifier(status)}</button>
                    `).join('')}
                </div>
                <div class="invoice-line-list">
                    <div class="invoice-line static">
                        <span>On-Call Contact</span>
                        <span class="business-action-row">
                            <input class="service-inline-input" type="text" maxlength="80" value="${escapeHtml(business.onCallContact || '')}" placeholder="555-0100 or employee name" id="locksmith-on-call-contact">
                            <button class="service-mini-btn" type="button" id="locksmith-save-on-call-contact">Save</button>
                        </span>
                    </div>
                </div>
            </div>
        `;
        appendBusinessCard('operations_status', statusCard);
        statusCard.querySelectorAll('[data-shop-status]').forEach((button) => {
            button.addEventListener('click', () => {
                postNui('locksmithSetShopStatus', {
                    token: window.serviceToken,
                    status: button.dataset.shopStatus
                });
            });
        });
        statusCard.querySelector('#locksmith-save-on-call-contact').addEventListener('click', () => {
            const input = statusCard.querySelector('#locksmith-on-call-contact');
            postNui('locksmithSetOnCallContact', {
                token: window.serviceToken,
                contact: input ? input.value : ''
            });
        });

        const societyCard = document.createElement('article');
        societyCard.className = 'service-item-card wide';
        societyCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Society Funds</div>
                <div class="service-item-copy">Account ${escapeHtml(business.societyAccount || (business.stocking && business.stocking.societyAccount) || 'locksmith')} | Balance ${business.societyBalance === null || business.societyBalance === undefined ? 'unknown' : formatMoney(business.societyBalance)}</div>
                <div class="business-action-row">
                    <input class="service-inline-input" id="locksmith-society-amount" type="number" min="1" value="1000">
                    <select class="service-inline-input" id="locksmith-society-payment">
                        <option value="bank">Bank</option>
                        <option value="cash">Cash</option>
                    </select>
                    <button class="service-mini-btn" type="button" data-society-action="deposit">Deposit</button>
                    <button class="service-mini-btn danger" type="button" data-society-action="withdraw">Withdraw</button>
                </div>
            </div>
        `;
        appendBusinessCard('operations_funds', societyCard);
        societyCard.querySelectorAll('[data-society-action]').forEach((button) => {
            button.addEventListener('click', () => {
                const amountInput = societyCard.querySelector('#locksmith-society-amount');
                const paymentInput = societyCard.querySelector('#locksmith-society-payment');
                postNui('locksmithMoveSocietyFunds', {
                    token: window.serviceToken,
                    actionType: button.dataset.societyAction,
                    amount: amountInput ? Number(amountInput.value || 0) : 0,
                    paymentMethod: paymentInput ? paymentInput.value : 'bank'
                });
            });
        });

        const businessPriceCategories = { service: true, tier: true, shop: true };
        const priceEntries = ((business.prices && business.prices.entries) || [])
            .filter((entry) => businessPriceCategories[entry.category] === true);
        const pricingCard = document.createElement('article');
        pricingCard.className = 'service-item-card wide';
        pricingCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Service Pricing</div>
                <div class="service-item-copy">${priceEntries.length ? 'Adjust active locksmith prices within the server economy limits.' : 'No owner-managed prices are configured.'}</div>
                <div class="invoice-line-list">
                    ${priceEntries.map((entry, index) => `
                        <div class="invoice-line static">
                            <span>${escapeHtml(entry.label || entry.key || 'Price')}</span>
                            <span>${formatMoney(entry.current || 0)}</span>
                            <span class="business-action-row">
                                <input class="service-inline-input" type="number" min="0" value="${Number(entry.current || 0)}" data-price-index="${index}">
                                <button class="service-mini-btn" type="button" data-price-save="${index}">Save</button>
                            </span>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
        appendBusinessCard('operations_pricing', pricingCard);
        pricingCard.querySelectorAll('[data-price-save]').forEach((button) => {
            button.addEventListener('click', () => {
                const index = Number(button.dataset.priceSave);
                const entry = priceEntries[index];
                const input = pricingCard.querySelector(`[data-price-index="${index}"]`);
                if (!entry) return;
                postNui('locksmithSetPrice', {
                    token: window.serviceToken,
                    priceKey: entry.key,
                    price: input ? Number(input.value || 0) : 0
                });
            });
        });
    }

    if (isStockMode) {
        const stockCard = document.createElement('article');
        stockCard.className = 'service-item-card wide';
        stockCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Current Business Stock</div>
                <div class="service-item-copy">${Object.keys(stock).length ? 'Inventory currently held by the locksmith business storage.' : 'No business stock has been built yet.'}</div>
                <div class="invoice-line-list">
                    ${Object.entries(stock).map(([item, quantity]) => `
                        <div class="invoice-line static">
                            <span>${escapeHtml(item)}</span>
                            <span>${Number(quantity || 0)}</span>
                        </div>
                    `).join('')}
                </div>
            </div>
            <button class="service-primary-btn" type="button" data-stock-storage-open>Open Storage</button>
        `;
        appendBusinessCard('stock', stockCard);
        stockCard.querySelector('[data-stock-storage-open]')?.addEventListener('click', () => {
            postNui('locksmithOpenStockStorage', {
                token: window.serviceToken,
                locationName: business.locationName
            });
        });
    }

    const shopOrders = business.shopOrders || [];
    if (!isWorkbench && !isStockMode && !inBusinessDrilldown) {
        const shopOrdersCard = document.createElement('article');
        shopOrdersCard.className = 'service-item-card wide';
        shopOrdersCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Customer Register Orders</div>
                <div class="service-item-copy">${shopOrders.length ? 'Fill paid customer orders from business stock, then place them at the pick-up point.' : 'No customer register orders are waiting.'}</div>
                <div class="invoice-line-list">
                    ${shopOrders.map((order) => `
                        <div class="invoice-line static">
                            <span>${escapeHtml(order.label || order.item_name || 'Item')} x${Number(order.quantity || 0)}</span>
                            <span>${escapeHtml(order.customer_name || 'Customer')} | ${escapeHtml(order.location_name || 'Location')} | ${escapeHtml(formatIdentifier(order.status || 'pending'))}</span>
                            <span class="business-action-row">
                                ${order.status === 'pending' ? `<button class="service-mini-btn" type="button" data-shop-order-fill="${escapeHtml(order.order_id || '')}">Fill</button>` : '<span class="service-pill">Awaiting Pickup</span>'}
                            </span>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
        appendBusinessCard('queue', shopOrdersCard);
        shopOrdersCard.querySelectorAll('[data-shop-order-fill]').forEach((button) => {
            button.addEventListener('click', () => {
                postNui('locksmithFillShopOrder', {
                    token: window.serviceToken,
                    orderId: button.dataset.shopOrderFill
                });
            });
        });
    }

    if (!isWorkbench && !isStockMode && !inBusinessDrilldown && ownerAccess && business.stocking && business.stocking.enabled !== false) {
        const stocking = business.stocking || {};
        const contracts = stocking.supplierContracts || [];
        if (contracts.length) {
            const supplierCard = document.createElement('article');
            supplierCard.className = 'service-item-card wide';
            supplierCard.innerHTML = `
                <div class="service-item-content">
                    <div class="service-item-title">Supplier Contract</div>
                    <div class="service-item-copy">Choose the active supplier contract for future stock orders.</div>
                    <div class="invoice-line-list">
                        ${contracts.map((contract) => `
                            <div class="invoice-line static">
                                <span>${escapeHtml(contract.label || contract.id)}</span>
                                <span>${Number(contract.priceMultiplier || 1).toFixed(2)}x price | ${Number(contract.delayMultiplier || 1).toFixed(2)}x delay</span>
                                <span class="business-action-row">
                                    <button class="service-mini-btn ${contract.active ? 'active' : ''}" type="button" data-supplier-contract="${escapeHtml(contract.id)}">${contract.active ? 'Active' : 'Select'}</button>
                                </span>
                            </div>
                        `).join('')}
                    </div>
                </div>
            `;
            appendBusinessCard('supply', supplierCard);
            supplierCard.querySelectorAll('[data-supplier-contract]').forEach((button) => {
                button.addEventListener('click', () => {
                    postNui('locksmithSetSupplierContract', {
                        token: window.serviceToken,
                        contractId: button.dataset.supplierContract
                    });
                });
            });
        }

        const orderCard = document.createElement('article');
        orderCard.className = 'service-item-card wide';
        orderCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Supplier Orders</div>
                <div class="service-item-copy">Order raw business stock using the selected location's stocking method.</div>
                <div class="invoice-line-list">
                    ${(stocking.orderItems || []).map((item, index) => `
                        <div class="invoice-line static">
                            <span>${escapeHtml(item.label || item.item)}</span>
                            <span>${formatMoney(item.price || 0)} each</span>
                            <span class="business-action-row">
                                <input class="service-inline-input" type="number" min="0" max="${Number(stocking.maxOrderQuantity || 50)}" value="0" data-stock-qty="${index}">
                            </span>
                        </div>
                    `).join('')}
                </div>
            </div>
            <button class="service-primary-btn" type="button" data-stock-order-cart>Order Cart</button>
        `;
        appendBusinessCard('supply', orderCard);
        orderCard.querySelector('[data-stock-order-cart]')?.addEventListener('click', () => {
            const maxOrderQuantity = Number(stocking.maxOrderQuantity || 50);
            const items = (stocking.orderItems || []).map((item, index) => {
                const quantityInput = orderCard.querySelector(`[data-stock-qty="${index}"]`);
                const quantity = Math.max(0, Math.min(maxOrderQuantity, sanitizeQuantity(quantityInput ? quantityInput.value : 0)));
                return quantity > 0 ? { item: item.item, quantity } : null;
            }).filter(Boolean);

            if (!items.length) return;

            postNui('locksmithOrderStock', {
                token: window.serviceToken,
                items,
                locationName: business.locationName || null
            });
        });

        const orders = supplierOrders.filter((order) => String(order.status || '').toLowerCase() !== 'completed');
        const ordersCard = document.createElement('article');
        ordersCard.className = 'service-item-card wide';
        ordersCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Active Stock Orders</div>
                <div class="service-item-copy">${orders.length ? 'Resume supplier orders still waiting on fulfillment.' : 'No active supplier orders are waiting.'}</div>
                <div class="invoice-line-list">
                    ${orders.map((order) => `
                        <div class="invoice-line static">
                            <span>${escapeHtml(order.label || order.item_name || 'Stock')} x${Number(order.quantity || 0)}</span>
                            <span>${escapeHtml(formatIdentifier(order.stock_method || 'auto'))} | ${escapeHtml(formatIdentifier(order.status || 'pending'))}</span>
                            <span class="business-action-row">
                                ${order.status !== 'completed' && order.stock_method !== 'auto' ? `<button class="service-mini-btn" type="button" data-stock-resume="${escapeHtml(order.order_id || '')}">Resume</button>` : ''}
                            </span>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
        appendBusinessCard('supply', ordersCard);
        ordersCard.querySelectorAll('[data-stock-resume]').forEach((button) => {
            button.addEventListener('click', () => {
                postNui('locksmithResumeStockOrder', {
                    token: window.serviceToken,
                    orderId: button.dataset.stockResume
                });
            });
        });
    }

    if (isStockMode) {
        finalizeBusinessTabs();
        return;
    }

    if (isWorkbench) {
        recipes.forEach((recipe) => {
            const card = document.createElement('article');
            card.className = 'service-item-card';
            const components = (recipe.components || []).map((component) => `${component.amount || 1}x ${component.label || component.item}`).join(', ');
            const image = recipe.image || (recipe.produces ? `assets/${recipe.produces}.png` : '');
            card.innerHTML = `
                <div class="service-item-media">
                    <img class="service-item-img" src="${image}" alt="">
                </div>
                <div class="service-item-content">
                    <div class="service-item-title">${escapeHtml(recipe.label || recipe.id || 'Build Stock')}</div>
                    <div class="service-item-copy">Produces ${Number(recipe.amount || 1)}x ${escapeHtml(recipe.produces || 'stock')}. Requires ${escapeHtml(components || 'configured parts')}.</div>
                </div>
                <div class="service-item-controls">
                    <div class="service-quantity">
                        <button type="button" data-qty-step="-1">-</button>
                        <input type="number" min="1" max="50" value="1" inputmode="numeric">
                        <button type="button" data-qty-step="1">+</button>
                    </div>
                    <button class="service-primary-btn" type="button">Build Stock</button>
                </div>
            `;

            const input = card.querySelector('input');
            card.querySelectorAll('[data-qty-step]').forEach((button) => {
                button.addEventListener('click', () => {
                    input.value = Math.max(1, Math.min(50, sanitizeQuantity(input.value) + Number(button.dataset.qtyStep)));
                });
            });
            card.querySelector('.service-primary-btn').addEventListener('click', () => {
                postNui('locksmithBuildStock', {
                    token: window.serviceToken,
                    recipeId: recipe.id,
                    craftSeconds: business.craftSeconds || 5,
                    quantity: Math.max(1, Math.min(50, sanitizeQuantity(input.value)))
                });
            });
            appendBusinessCard('build', card);
        });
        finalizeBusinessTabs();
        return;
    }

    const employees = business.employees || [];
    if (inStaffDrilldown && ownerAccess) {
        const employeeCard = document.createElement('article');
        employeeCard.className = 'service-item-card wide';
        employeeCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Employees</div>
                <div class="service-item-copy">${employees.length ? 'Current locksmith staff visible to the business tablet.' : 'No locksmith staff are online.'}</div>
                <div class="invoice-line-list">
                    ${employees.map((employee) => `
                        <div class="invoice-line static">
                            <span>${escapeHtml(employee.name || 'Employee')}</span>
                            <span>Grade ${Number(employee.grade || 0)} | ${employee.duty ? 'On Duty' : 'Off Duty'}</span>
                            <span class="business-action-row">
                                <button class="service-mini-btn" type="button" data-employee-action="promote" data-target="${employee.source}">Promote</button>
                                <button class="service-mini-btn" type="button" data-employee-action="demote" data-target="${employee.source}">Demote</button>
                                <button class="service-mini-btn danger" type="button" data-employee-action="fire" data-target="${employee.source}">Fire</button>
                            </span>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
        appendBusinessCard('staff_main', employeeCard);
        employeeCard.querySelectorAll('[data-employee-action]').forEach((button) => {
            button.addEventListener('click', () => {
                postNui('locksmithManageEmployee', {
                    token: window.serviceToken,
                    actionType: button.dataset.employeeAction,
                    targetId: Number(button.dataset.target)
                });
            });
        });
    }

    if (inStaffDrilldown && ownerAccess) {
        const payment = business.payment || {};
        const currentCommission = Number(payment.EmployeeCommissionPercent || 0);
        const maxCommission = Number(payment.MaxCommissionPercent || 100);
        const maxInvoiceCommission = Number(payment.MaxCommissionPerInvoice || 0);
        const commissionCard = document.createElement('article');
        commissionCard.className = 'service-item-card wide';
        commissionCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Employee Commission</div>
                <div class="service-item-copy">Commission is split from the customer total before society deposit. Example: 10% of ${formatMoney(1000)} pays ${formatMoney(100)} to the employee and ${formatMoney(900)} to society.</div>
                <div class="invoice-line static">
                    <span>Current Commission</span>
                    <span>${currentCommission}%</span>
                </div>
                <div class="invoice-line static">
                    <span>Deposit Split</span>
                    <span>Employee ${currentCommission}% | Society ${Math.max(0, 100 - currentCommission)}%</span>
                </div>
                <div class="invoice-line static">
                    <span>Employee Account</span>
                    <span>${escapeHtml(payment.EmployeeCommissionAccount || 'cash')}</span>
                </div>
                ${maxInvoiceCommission > 0 ? `
                    <div class="invoice-line static">
                        <span>Per-Invoice Cap</span>
                        <span>${formatMoney(maxInvoiceCommission)}</span>
                    </div>
                ` : ''}
                <div class="business-action-row">
                    <input class="service-inline-input" id="locksmith-commission-percent" type="number" min="0" max="${maxCommission}" value="${currentCommission}">
                    <button class="service-mini-btn" id="locksmith-save-commission" type="button">Save Commission</button>
                </div>
            </div>
        `;
        appendBusinessCard('staff_main', commissionCard);
        const commissionInput = commissionCard.querySelector('#locksmith-commission-percent');
        commissionCard.querySelector('#locksmith-save-commission').addEventListener('click', () => {
            const percent = Math.max(0, Math.min(maxCommission, Number(commissionInput ? commissionInput.value || 0 : 0)));
            postNui('locksmithSetCommission', {
                token: window.serviceToken,
                percent
            });
        });
    }

    if (inStaffDrilldown && (business.payment || {}).PayrollEnabled !== false && canUseManagement('Payroll')) {
        const payrollCard = document.createElement('article');
        payrollCard.className = 'service-item-card wide';
        const maxPayroll = Number((business.payment || {}).MaxPayrollPayout || 0);
        payrollCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Payroll</div>
                <div class="service-item-copy">Pay online locksmith employees. ${maxPayroll > 0 ? `Server cap: ${formatMoney(maxPayroll)}.` : 'No configured payout cap.'}</div>
                <div class="invoice-line-list">
                    ${employees.map((employee) => `
                        <div class="invoice-line static">
                            <span>${escapeHtml(employee.name || 'Employee')}</span>
                            <span class="business-action-row">
                                <input class="service-inline-input" type="number" min="1" ${maxPayroll > 0 ? `max="${maxPayroll}"` : ''} value="100" data-payroll-amount="${employee.source}">
                                <button class="service-mini-btn" type="button" data-payroll-target="${employee.source}">Pay</button>
                            </span>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
        appendBusinessCard('staff_main', payrollCard);
        payrollCard.querySelectorAll('[data-payroll-target]').forEach((button) => {
            button.addEventListener('click', () => {
                const target = button.dataset.payrollTarget;
                const input = payrollCard.querySelector(`[data-payroll-amount="${target}"]`);
                postNui('locksmithPayEmployee', {
                    token: window.serviceToken,
                    targetId: Number(target),
                    amount: input ? Number(input.value || 0) : 0
                });
            });
        });
    }

    if (inStaffDrilldown && canUseManagement('Candidates')) {
        const candidates = business.candidates || [];
        const hireCard = document.createElement('article');
        hireCard.className = 'service-item-card wide';
        hireCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Nearby Candidates</div>
                <div class="service-item-copy">${candidates.length ? 'Nearby players eligible for hire.' : 'No nearby non-employee candidates.'}</div>
                <div class="invoice-line-list">
                    ${candidates.map((candidate) => `
                        <div class="invoice-line static">
                            <span>${escapeHtml(candidate.name || 'Candidate')}</span>
                            <button class="service-mini-btn" type="button" data-hire-target="${candidate.source}">Hire</button>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
        appendBusinessCard('staff_main', hireCard);
        hireCard.querySelectorAll('[data-hire-target]').forEach((button) => {
            button.addEventListener('click', () => {
                postNui('locksmithManageEmployee', {
                    token: window.serviceToken,
                    actionType: 'hire',
                    targetId: Number(button.dataset.hireTarget)
                });
            });
        });
    }

    const appointments = business.appointments || [];
    const canAnyAppointmentAction = canUseManagement('AppointmentSchedule')
        || canUseManagement('AppointmentComplete')
        || canUseManagement('AppointmentCancel')
        || canUseManagement('AppointmentReminder');
    if (!inBusinessDrilldown && canAnyAppointmentAction) {
        const appointmentCard = document.createElement('article');
        appointmentCard.className = 'service-item-card wide';
        appointmentCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Appointments</div>
                <div class="service-item-copy">${appointments.length ? 'Pending, confirmed, and scheduled customer appointment requests.' : 'No active customer appointment requests.'}</div>
                <div class="invoice-line-list">
                    ${appointments.map((appointment) => `
                        <div class="invoice-line static">
                            <span>${escapeHtml(appointment.contact_name || appointment.customer_name || 'Customer')} | ${escapeHtml(appointment.contact_phone || 'No contact')} | ${escapeHtml(appointment.plate || 'No plate')}</span>
                            <span>${escapeHtml(formatIdentifier(appointment.status || 'pending'))}${appointment.scheduled_for ? ` | ${escapeHtml(appointment.scheduled_for)}` : ''}${appointment.contact_email ? ` | ${escapeHtml(appointment.contact_email)}` : ''} | ${escapeHtml(appointment.schedule_note || appointment.message || '')}</span>
                            ${canUseManagement('AppointmentSchedule') ? `
                                <span class="business-action-row appointment-schedule-fields">
                                    <input class="service-inline-input" type="text" maxlength="100" placeholder="Name" value="${escapeHtml(appointment.contact_name || appointment.customer_name || '')}" data-appointment-field="contactName" data-appointment-id="${escapeHtml(appointment.appointment_id || '')}">
                                    <input class="service-inline-input" type="text" maxlength="80" placeholder="Phone/contact" value="${escapeHtml(appointment.contact_phone || '')}" data-appointment-field="contactPhone" data-appointment-id="${escapeHtml(appointment.appointment_id || '')}">
                                    <input class="service-inline-input" type="text" maxlength="120" placeholder="Email" value="${escapeHtml(appointment.contact_email || '')}" data-appointment-field="contactEmail" data-appointment-id="${escapeHtml(appointment.appointment_id || '')}">
                                    <input class="service-inline-input" type="text" maxlength="40" placeholder="Date" value="${escapeHtml(appointment.scheduled_date || '')}" data-appointment-field="date" data-appointment-id="${escapeHtml(appointment.appointment_id || '')}">
                                    <input class="service-inline-input" type="text" maxlength="40" placeholder="Time" value="${escapeHtml(appointment.scheduled_time || '')}" data-appointment-field="time" data-appointment-id="${escapeHtml(appointment.appointment_id || '')}">
                                    <input class="service-inline-input" type="text" maxlength="255" placeholder="Notes" value="${escapeHtml(appointment.schedule_note || appointment.message || '')}" data-appointment-field="note" data-appointment-id="${escapeHtml(appointment.appointment_id || '')}">
                                </span>
                            ` : ''}
                            <span class="business-action-row">
                                ${appointment.status === 'pending' && canUseManagement('AppointmentSchedule') ? `<button class="service-mini-btn" type="button" data-appointment-action="confirm" data-appointment-id="${escapeHtml(appointment.appointment_id || '')}">Confirm</button>` : ''}
                                ${canUseManagement('AppointmentSchedule') ? `<button class="service-mini-btn" type="button" data-appointment-action="schedule" data-appointment-id="${escapeHtml(appointment.appointment_id || '')}">Schedule</button>` : ''}
                                ${canUseManagement('AppointmentComplete') ? `<button class="service-mini-btn" type="button" data-appointment-action="complete" data-appointment-id="${escapeHtml(appointment.appointment_id || '')}">Complete</button>` : ''}
                                ${canUseManagement('AppointmentCancel') ? `<button class="service-mini-btn danger" type="button" data-appointment-action="cancel" data-appointment-id="${escapeHtml(appointment.appointment_id || '')}">Cancel</button>` : ''}
                                ${canUseManagement('AppointmentReminder') ? `<button class="service-mini-btn" type="button" data-appointment-action="reminder" data-appointment-id="${escapeHtml(appointment.appointment_id || '')}">Remind</button>` : ''}
                            </span>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
        appendBusinessCard('queue', appointmentCard);
        const getAppointmentScheduleData = (appointmentId) => {
            const read = (field) => {
                const input = Array.from(appointmentCard.querySelectorAll('[data-appointment-field]'))
                    .find((element) => element.dataset.appointmentId === appointmentId && element.dataset.appointmentField === field);
                return input ? input.value : '';
            };
            return {
                contactName: read('contactName'),
                contactPhone: read('contactPhone'),
                contactEmail: read('contactEmail'),
                date: read('date'),
                time: read('time'),
                note: read('note')
            };
        };
        appointmentCard.querySelectorAll('[data-appointment-action]').forEach((button) => {
            button.addEventListener('click', () => {
                const appointmentId = button.dataset.appointmentId;
                const scheduleData = button.dataset.appointmentAction === 'schedule' ? getAppointmentScheduleData(appointmentId) : {};
                if (button.dataset.appointmentAction === 'schedule' && (!scheduleData.contactName.trim() || !scheduleData.contactPhone.trim())) return;

                postNui('locksmithManageAppointment', {
                    token: window.serviceToken,
                    appointmentId,
                    actionType: button.dataset.appointmentAction,
                    scheduleData
                });
            });
        });
    }

    if (inReportsDrilldown && canUseManagement('Reports')) {
        const reports = business.reports || {};
        const completedSupplierOrders = supplierOrders.filter((order) => String(order.status || '').toLowerCase() === 'completed');

        const revenueCard = document.createElement('article');
        revenueCard.className = 'service-item-card wide';
        revenueCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Revenue</div>
                <div class="service-summary-grid">
                    <span><strong>${formatMoney(reports.paidTotal || 0)}</strong><small>Paid Revenue</small></span>
                    <span><strong>${Number(reports.paidCount || 0)}</strong><small>Paid Invoices</small></span>
                    <span><strong>${Number(reports.pendingCount || 0)}</strong><small>Open Invoices</small></span>
                </div>
            </div>
        `;
        appendBusinessCard('reports_revenue', revenueCard);

        const invoiceCard = document.createElement('article');
        invoiceCard.className = 'service-item-card wide';
        invoiceCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Invoices</div>
                <div class="service-item-copy">${(reports.recentInvoices || []).length ? 'Recent customer invoices for this location.' : 'No recent invoices found.'}</div>
                <div class="invoice-line-list">
                    ${(reports.recentInvoices || []).map((invoice) => `
                        <div class="invoice-line static">
                            <span>${escapeHtml(invoice.plate || 'UNKNOWN')} | ${escapeHtml(invoice.status || 'pending')}</span>
                            <span>${formatMoney(invoice.total || 0)} | Society ${formatMoney(invoice.society_deposit || 0)}</span>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
        appendBusinessCard('reports_invoices', invoiceCard);

        const ordersReportCard = document.createElement('article');
        ordersReportCard.className = 'service-item-card wide';
        ordersReportCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Completed Supplier Orders</div>
                <div class="service-item-copy">${completedSupplierOrders.length ? 'Completed supplier stock orders for this business.' : 'No completed supplier orders found.'}</div>
                <div class="invoice-line-list">
                    ${completedSupplierOrders.map((order) => `
                        <div class="invoice-line static">
                            <span>${escapeHtml(order.label || order.item_name || 'Stock')} x${Number(order.quantity || 0)}</span>
                            <span>${escapeHtml(formatIdentifier(order.stock_method || 'auto'))} | ${escapeHtml(formatIdentifier(order.status || 'completed'))}</span>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
        appendBusinessCard('reports_orders', ordersReportCard);

        const logsCard = document.createElement('article');
        logsCard.className = 'service-item-card wide';
        logsCard.innerHTML = `
            <div class="service-item-content">
                <div class="service-item-title">Logs</div>
                <div class="service-item-copy">${(reports.recentLogs || []).length ? 'Recent business activity for this location.' : 'No recent log entries found.'}</div>
                <div class="invoice-line-list">
                    ${(reports.recentLogs || []).map((log) => `
                        <div class="invoice-line static">
                            <span>${escapeHtml(log.action || 'event')}</span>
                            <span>${escapeHtml(log.message || '')}</span>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
        appendBusinessCard('reports_logs', logsCard);
    }

    finalizeBusinessTabs();
}

const KEY_TIER_IMAGES = {
    basic: 'assets/basic_vehicle_key.png',
    smart: 'assets/smart_vehicle_key.png',
    advanced: 'assets/advanced_smart_vehicle_key.png',
    oled: 'assets/oled_vehicle_key.png'
};

const KEY_CATEGORY_ICONS = {
    owned: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12l1.4-4.2A2 2 0 0 1 8.3 6.4h7.4a2 2 0 0 1 1.9 1.4L19 12"/><path d="M4.5 12h15v4.5h-15z"/><circle cx="7.5" cy="16.5" r="1.1"/><circle cx="16.5" cy="16.5" r="1.1"/></svg>',
    shared: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="9" cy="8.5" r="3"/><path d="M3.5 19a5.5 5.5 0 0 1 11 0"/><path d="M16.5 8.5H21"/><path d="m18.5 6 2.5 2.5-2.5 2.5"/></svg>',
    sharedOut: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="6.5" cy="12" r="2.3"/><circle cx="17.5" cy="6" r="2.3"/><circle cx="17.5" cy="18" r="2.3"/><path d="M8.6 10.9 15.4 7M8.6 13.1 15.4 17"/></svg>',
    stolen: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 4 3.5 19h17z"/><path d="M12 10.5v4"/><path d="M12 17h.01"/></svg>'
};

function getKeyCategories() {
    return [
        { id: 'owned', title: 'Vehicles I Own', copy: 'Share, copy, re-key, or upgrade.', empty: 'No owned vehicle key records found.' },
        { id: 'shared', title: 'Shared Keys I Have', copy: 'Keys shared with you.', empty: 'No shared keys found.' },
        { id: 'sharedOut', title: 'Keys I Have Shared', copy: 'Keys you shared with others.', empty: 'No outgoing shared keys found.' },
        { id: 'stolen', title: 'Stolen / Possession Keys', copy: 'Possession-based key records.', empty: 'No stolen or possession keys found.' }
    ];
}

function getKeyTierImage(tierName) {
    const menu = window.keyMenu || {};
    const match = (menu.keyTiers || []).find((tier) => tier.tier === tierName);
    return (match && match.image) || KEY_TIER_IMAGES[tierName] || 'assets/blank_key.png';
}

function openKeyMenu(data) {
    window.keyMenu = data || {};
    window.keyMenuToken = data.token;
    window.keyPanel = 'categories';
    window.keySection = null;
    window.selectedKeyRecord = null;

    renderKeyMenu();
    document.getElementById('key-container').style.display = 'block';
}

function getKeyRecords(section) {
    const menu = window.keyMenu || {};
    return menu[section] || [];
}

function getKeyRecordMeta(record) {
    const physical = record.has_physical ? 'Physical key present' : 'No physical key';
    const tier = record.key_tier || 'smart';
    return `${physical} | ${tier} | Version ${record.key_version || 'N/A'}`;
}

function getKeyTierRank(tierName) {
    const menu = window.keyMenu || {};
    const tiers = menu.keyTiers || [];
    const match = tiers.find((tier) => tier.tier === tierName);
    return match ? Number(match.rank || 0) : 0;
}

function getKeyTierChangeLabel(record, tier) {
    const currentRank = getKeyTierRank(record.key_tier || 'smart');
    const targetRank = Number(tier.rank || getKeyTierRank(tier.tier));

    if (record.key_tier === tier.tier) return 'Current';
    if (currentRank > 0 && targetRank > 0 && targetRank < currentRank) return 'Downgrade';
    if (currentRank > 0 && targetRank > 0 && targetRank > currentRank) return 'Upgrade';
    return 'Change';
}

function recordMatches(a, b) {
    return !!(a && b && a.id === b.id && a.plate === b.plate);
}

function selectKeyCategory(section) {
    window.keyPanel = 'grid';
    window.keySection = section;
    window.selectedKeyRecord = null;
    renderKeyMenu();
}

function selectKeyRecord(record) {
    window.keyPanel = 'detail';
    window.selectedKeyRecord = record;
    renderKeyMenu();
}

function backToKeyCategories() {
    window.keyPanel = 'categories';
    window.keySection = null;
    window.selectedKeyRecord = null;
    renderKeyMenu();
}

function backToKeyGrid() {
    window.keyPanel = 'grid';
    window.selectedKeyRecord = null;
    renderKeyMenu();
}

function renderKeyMenu() {
    const list = document.getElementById('key-record-list');
    if (list) {
        list.innerHTML = '';
        list.style.display = 'none';
    }

    renderKeySidebar();

    const detail = document.getElementById('key-record-detail');
    if (!detail) return;

    if (window.keyPanel === 'detail') {
        renderKeyDetail(detail);
    } else if (window.keyPanel === 'grid') {
        renderKeyRecordGrid(detail);
    } else {
        renderKeyCategoryOverview(detail);
    }
}

function renderKeySidebar() {
    const sidebar = document.getElementById('key-sidebar');
    sidebar.innerHTML = '';

    if (window.keyPanel === 'detail') {
        const section = window.keySection || 'owned';
        const category = getKeyCategories().find((item) => item.id === section);
        const records = getKeyRecords(section);

        const back = document.createElement('button');
        back.type = 'button';
        back.className = 'key-back-btn';
        back.innerHTML = `&lt; ${escapeHtml(category ? category.title : 'Keys')}`;
        back.title = 'Back to list';
        back.addEventListener('click', backToKeyGrid);
        sidebar.appendChild(back);

        const heading = document.createElement('div');
        heading.className = 'key-sidebar-heading';
        heading.innerHTML = `
            <div class="key-sidebar-title">${records.length} ${records.length === 1 ? 'Key' : 'Keys'}</div>
            <div class="key-sidebar-copy">Select one to manage</div>
        `;
        sidebar.appendChild(heading);

        records.forEach((record) => {
            const tier = record.key_tier || 'smart';
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'key-record-tab';
            if (recordMatches(window.selectedKeyRecord, record)) button.classList.add('active');
            button.innerHTML = `
                <img class="key-record-tab-icon" src="${getKeyTierImage(tier)}" alt="">
                <span class="key-record-tab-text">
                    <span class="key-record-tab-title">${escapeHtml(record.label || `Vehicle ${record.plate || 'Unknown'}`)}</span>
                    <span class="key-record-tab-meta">${escapeHtml(record.plate || 'UNKNOWN')} &middot; ${escapeHtml(tier)}</span>
                </span>
            `;
            button.addEventListener('click', () => selectKeyRecord(record));
            sidebar.appendChild(button);
        });
        return;
    }

    getKeyCategories().forEach((category) => {
        const count = getKeyRecords(category.id).length;
        const button = document.createElement('button');
        button.type = 'button';
        button.className = `service-tab ${window.keyPanel === 'grid' && window.keySection === category.id ? 'active' : ''}`;
        button.dataset.section = category.id;
        button.innerHTML = `
            <span class="service-tab-title">${category.title}</span>
            <span class="service-tab-copy">${count} ${count === 1 ? 'record' : 'records'}</span>
        `;
        button.addEventListener('click', () => selectKeyCategory(category.id));
        sidebar.appendChild(button);
    });
}

function renderKeyCategoryOverview(detail) {
    detail.innerHTML = `
        <div class="service-detail-header">
            <div>
                <div class="service-detail-title">Key Management</div>
                <div class="service-detail-subtitle">Choose a category to review access, shared keys, possession records, and key services.</div>
            </div>
        </div>
        <div class="key-summary-grid"></div>
    `;

    const grid = detail.querySelector('.key-summary-grid');
    getKeyCategories().forEach((category) => {
        const count = getKeyRecords(category.id).length;
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'key-summary-card';
        button.innerHTML = `
            <span class="key-summary-icon">${KEY_CATEGORY_ICONS[category.id] || ''}</span>
            <span class="key-summary-count">${count}</span>
            <span class="key-summary-text">
                <span class="key-summary-title">${category.title}</span>
                <span class="key-summary-copy">${category.copy}</span>
            </span>
        `;
        button.addEventListener('click', () => selectKeyCategory(category.id));
        grid.appendChild(button);
    });
}

function renderKeyRecordGrid(detail) {
    const section = window.keySection || 'owned';
    const category = getKeyCategories().find((item) => item.id === section);
    const records = getKeyRecords(section);

    detail.innerHTML = `
        <div class="key-grid-head">
            <button class="key-back-btn" type="button">&lt; Categories</button>
            <div class="key-grid-head-text">
                <div class="service-detail-title">${escapeHtml(category ? category.title : 'Keys')}</div>
                <div class="service-detail-subtitle">${records.length} ${records.length === 1 ? 'record' : 'records'} &middot; select a key to manage it</div>
            </div>
        </div>
        <div class="key-record-grid"></div>
    `;
    detail.querySelector('.key-back-btn').addEventListener('click', backToKeyCategories);

    const grid = detail.querySelector('.key-record-grid');
    if (!records.length) {
        grid.innerHTML = `<div class="service-empty wide">${escapeHtml(category ? category.empty : 'No records found.')}</div>`;
        return;
    }

    records.forEach((record) => {
        const tier = record.key_tier || 'smart';
        const card = document.createElement('button');
        card.type = 'button';
        card.className = 'key-card';
        if (recordMatches(window.selectedKeyRecord, record)) card.classList.add('active');
        card.innerHTML = `
            <span class="key-card-media"><img src="${getKeyTierImage(tier)}" alt=""></span>
            <span class="key-card-body">
                <span class="key-card-title">${escapeHtml(record.label || `Vehicle ${record.plate || 'Unknown'}`)}</span>
                <span class="key-card-plate">${escapeHtml(record.plate || 'UNKNOWN')}</span>
                <span class="key-card-chips">
                    <span class="key-chip">${escapeHtml(tier)}</span>
                    <span class="key-chip">v${escapeHtml(record.key_version || 'N/A')}</span>
                    <span class="key-chip ${record.has_physical ? 'ok' : 'muted'}">${record.has_physical ? 'Physical' : 'No Key'}</span>
                </span>
            </span>
            <span class="key-card-go">&rsaquo;</span>
        `;
        card.addEventListener('click', () => selectKeyRecord(record));
        grid.appendChild(card);
    });
}

function buildTierCard(tier, opts) {
    opts = opts || {};
    const paymentOptions = opts.paymentOptions || [{ value: 'cash', label: 'Cash' }];
    const current = opts.current === true;
    const card = document.createElement('div');
    card.className = `key-tier-card${current ? ' current' : ''}`;
    card.innerHTML = `
        ${current ? '<span class="key-tier-badge">Current</span>' : ''}
        <span class="key-tier-media"><img src="${tier.image || getKeyTierImage(tier.tier)}" alt=""></span>
        <span class="key-tier-name">${escapeHtml(tier.label || tier.tier || 'Key System')}</span>
        <span class="key-tier-desc">${escapeHtml(current ? 'Current key system' : (tier.description || 'Change and re-key this vehicle.'))}</span>
        <span class="key-tier-foot">
            <span class="service-price">${formatMoney(tier.price)}</span>
            ${renderPaymentSelector(`tier-${tier.tier}`, paymentOptions)}
            <button class="service-primary-btn" type="button" ${current || opts.disabled ? 'disabled' : ''}>${escapeHtml(current ? 'Active' : (opts.button || 'Change'))}</button>
        </span>
    `;
    attachPaymentHandlers(card);
    if (!current && !opts.disabled && opts.onClick) {
        card.querySelector('.service-primary-btn').addEventListener('click', () => opts.onClick(getSelectedPayment(card)));
    }
    return card;
}

function renderKeyDetail(detail) {
    const record = window.selectedKeyRecord;
    const menu = window.keyMenu || {};
    const section = window.keySection || 'owned';
    const paymentOptions = [{ value: 'cash', label: 'Cash' }, { value: 'bank', label: 'Bank' }];

    detail.innerHTML = '';
    if (!record) {
        detail.innerHTML = '<div class="service-empty wide">Select a key record to view details and available actions.</div>';
        return;
    }

    const tier = record.key_tier || 'smart';
    detail.innerHTML = `
        <div class="key-detail-header">
            <span class="key-detail-media"><img src="${getKeyTierImage(tier)}" alt=""></span>
            <div class="key-detail-info">
                <div class="service-detail-title">${escapeHtml(record.label || 'Vehicle Key')}</div>
                <div class="service-detail-subtitle">Plate ${escapeHtml(record.plate || 'UNKNOWN')} &middot; ${escapeHtml(record.key_type || section)}</div>
                <div class="key-meta-grid">
                    <span class="key-meta-cell">
                        <span class="key-meta-label">Tier</span>
                        <span class="key-meta-value">${escapeHtml(tier)}</span>
                    </span>
                    <span class="key-meta-cell">
                        <span class="key-meta-label">Version</span>
                        <span class="key-meta-value">${escapeHtml(record.key_version || 'N/A')}</span>
                    </span>
                    <span class="key-meta-cell">
                        <span class="key-meta-label">Physical</span>
                        <span class="key-meta-value">${record.has_physical ? 'Present' : 'Not held'}</span>
                    </span>
                </div>
            </div>
            <span class="service-pill">${escapeHtml(record.holder_name || record.owner_name || 'Current Holder')}</span>
        </div>
        <div class="key-actions-grid" id="key-action-list"></div>
        <div id="key-extra-detail"></div>
    `;

    const actions = document.getElementById('key-action-list');

    if (section === 'owned') {
        appendKeyAction(actions, {
            title: 'View Keyholders',
            description: 'See active owner, shared, and possession key records.',
            button: 'View',
            onClick: () => requestKeyMenuAction({ action: 'keyholders', plate: record.plate }, (response) => renderKeyholders(response.keyholders || []))
        });
        appendKeyAction(actions, {
            title: 'Give Shared Key',
            description: 'Share a legal key with a nearby player.',
            button: 'Share',
            onClick: () => requestKeyMenuAction({ action: 'share', plate: record.plate, possession_id: record.possession_id })
        });
        if (menu.copyAllowed !== false) {
            appendKeyAction(actions, {
                title: 'Create Physical Copy',
                description: record.has_physical ? 'You already have a current physical key.' : 'Create a physical key from your owner record.',
                button: 'Create',
                disabled: record.has_physical === true,
                onClick: () => requestKeyMenuAction({ action: 'copy', plate: record.plate })
            });
        } else if (menu.appointmentsAllowed !== false) {
            appendKeyAction(actions, {
                title: 'Request Locksmith',
                description: 'Copy and key services are handled by the player-run locksmith business.',
                button: 'Request',
                onClick: () => requestKeyMenuAction({ action: 'appointment', plate: record.plate, message: 'Customer requested locksmith service from key management.' })
            });
        }

        if (menu.menuRekeyAllowed) {
            appendKeyPaidAction(actions, {
                title: 'Re-Key Vehicle',
                description: 'Invalidate older key versions and create a fresh owner key.',
                price: menu.rekeyFee || 0,
                button: 'Re-Key',
                paymentOptions,
                onClick: (paymentMethod) => requestKeyMenuAction({ action: 'rekey', plate: record.plate, paymentMethod })
            });
        }

        if ((menu.allowTierChange || menu.allowUpgrade) && (menu.keyTiers || []).length) {
            const upgradeWrap = document.createElement('div');
            upgradeWrap.className = 'key-upgrade-section';
            upgradeWrap.innerHTML = '<div class="service-subheading">Change Key System</div><div class="key-tier-grid"></div>';
            const tierGrid = upgradeWrap.querySelector('.key-tier-grid');
            (menu.keyTiers || []).forEach((tier) => {
                tierGrid.appendChild(buildTierCard(tier, {
                    current: record.key_tier === tier.tier,
                    button: getKeyTierChangeLabel(record, tier),
                    paymentOptions,
                    onClick: (paymentMethod) => requestKeyMenuAction({ action: 'upgrade', plate: record.plate, tier: tier.tier, paymentMethod })
                }));
            });
            detail.appendChild(upgradeWrap);
        }
    } else if (section === 'sharedOut') {
        appendKeyAction(actions, {
            title: 'Shared Keyholder',
            description: `${record.holder_name || 'Unknown Holder'} | ${record.key_type || 'shared'} | Version ${record.key_version || 'N/A'}`,
            button: 'View Only',
            disabled: true
        });
    }
}

function appendKeyAction(root, action) {
    const card = document.createElement('div');
    card.className = 'service-action-card';
    card.innerHTML = `
        <div>
            <div class="service-card-title">${action.title}</div>
            <div class="service-card-copy">${action.description || ''}</div>
        </div>
        <div class="service-card-footer">
            <button class="service-primary-btn" type="button" ${action.disabled ? 'disabled' : ''}>${action.button || 'Start'}</button>
        </div>
    `;
    if (!action.disabled && action.onClick) card.querySelector('button').addEventListener('click', action.onClick);
    root.appendChild(card);
}

function appendKeyPaidAction(root, action) {
    const card = document.createElement('div');
    card.className = 'service-action-card';
    card.innerHTML = `
        <div>
            <div class="service-card-title">${action.title}</div>
            <div class="service-card-copy">${action.description || ''}</div>
        </div>
        <div class="service-card-footer">
            <div class="service-price">${formatMoney(action.price)}</div>
            ${renderPaymentSelector(`key-${action.title}`, action.paymentOptions || [{ value: 'cash', label: 'Cash' }])}
            <button class="service-primary-btn" type="button" ${action.disabled ? 'disabled' : ''}>${action.button || 'Start'}</button>
        </div>
    `;
    attachPaymentHandlers(card);
    if (!action.disabled && action.onClick) {
        card.querySelector('.service-primary-btn').addEventListener('click', () => action.onClick(getSelectedPayment(card)));
    }
    root.appendChild(card);
}

function requestKeyMenuAction(payload, onResponse) {
    postNui('keyMenuAction', Object.assign({ token: window.keyMenuToken }, payload))
        .then((response) => response.json ? response.json() : response)
        .then((data) => {
            if (onResponse) onResponse(data || {});
        });
}

function renderKeyholders(keyholders) {
    const detail = document.getElementById('key-extra-detail');
    if (!detail) return;

    if (!keyholders.length) {
        detail.innerHTML = '<div class="service-empty wide">No shared keyholders found for this vehicle.</div>';
        return;
    }

    detail.innerHTML = '<div class="service-subheading">Active Keyholders</div>';
    const wrap = document.createElement('div');
    wrap.className = 'key-holder-grid';
    keyholders.forEach((holder) => {
        const row = document.createElement('div');
        row.className = 'key-holder-card';
        row.innerHTML = `
            <div class="service-detail-title">${escapeHtml(holder.holder_name || 'Unknown Holder')}</div>
            <div class="service-detail-subtitle">${escapeHtml(holder.key_type || 'key')} &middot; Version ${escapeHtml(holder.key_version || 'N/A')}</div>
        `;
        wrap.appendChild(row);
    });
    detail.appendChild(wrap);
}

function openGpsTablet(trackers) {
    window.tabletTrackers = trackers;
    window.selectedTracker = trackers[0] || null;
    const tabletFrame = document.querySelector('.tablet-frame');
    if (tabletFrame) tabletFrame.classList.remove('screen-off');
    renderTrackerList();
    renderTrackerDetail();
    document.getElementById('tablet-container').style.display = 'block';
}

function openSignalFinder(data) {
    const vehicle = data.vehicle || {};
    const trackers = data.trackers || [];
    window.signalVehicle = vehicle;
    window.signalTrackers = trackers;

    const title = document.getElementById('signal-title');
    const status = document.getElementById('signal-status');
    const list = document.getElementById('signal-list');
    const vehicleLabel = vehicle.label && vehicle.label !== 'NULL' ? vehicle.label : 'Nearby Vehicle';

    title.innerText = `${vehicleLabel} | ${vehicle.plate || 'UNKNOWN'}`;
    status.innerText = 'Looking for nearby signals...';
    list.innerHTML = '';
    document.getElementById('signal-container').style.display = 'block';

    if (window.signalScanTimer) clearTimeout(window.signalScanTimer);
    window.signalScanTimer = setTimeout(() => {
        if (!window.signalFinderToken) return;

        status.innerText = trackers.length ? `${trackers.length} hidden signal${trackers.length === 1 ? '' : 's'} detected.` : 'No hidden tracker signals detected.';

        if (!trackers.length) {
            list.innerHTML = '<div class="signal-empty">The sweep is clear. No removable GPS trackers were found on this vehicle.</div>';
            return;
        }

        trackers.forEach((tracker, index) => {
            const row = document.createElement('div');
            row.className = 'signal-row';
            row.innerHTML = `
                <div>
                    <div class="signal-row-title">Tracker ${index + 1}${tracker.own ? ' (Yours)' : ''}</div>
                    <div class="signal-row-copy">${escapeHtml(tracker.tier_label || tracker.tier || 'Tracker')} | ${tracker.own ? 'Registered to your GPS tablet.' : 'Foreign tracker signature detected.'}</div>
                </div>
                <button class="signal-remove" type="button">Remove</button>
            `;
            row.querySelector('.signal-remove').addEventListener('click', () => {
                postNui('signalFinderRemoveTracker', {
                    id: tracker.id,
                    netId: vehicle.netId,
                    plate: vehicle.plate,
                    token: window.signalFinderToken
                });
                closeAllPanels();
                window.signalFinderToken = null;
                window.signalVehicle = null;
                window.signalTrackers = [];
            });
            list.appendChild(row);
        });
    }, 2600);
}

function getTrackerLabel(tracker, index) {
    const note = (tracker.note || '').trim();
    return note || `Tracker ${index + 1}`;
}

function renderTrackerList() {
    const list = document.getElementById('tracker-list');
    list.innerHTML = '';

    (window.tabletTrackers || []).forEach((tracker, index) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'tracker-row';
        if (window.selectedTracker && window.selectedTracker.id === tracker.id) {
            button.classList.add('active');
        }

        const title = document.createElement('span');
        title.className = 'tracker-row-title';
        title.innerText = getTrackerLabel(tracker, index);

        const status = document.createElement('span');
        status.className = `tracker-row-status ${tracker.available ? 'online' : 'offline'}`;
        status.innerText = tracker.available ? 'Signal' : 'No Signal';

        button.appendChild(title);
        button.appendChild(status);
        button.addEventListener('click', () => {
            window.selectedTracker = tracker;
            renderTrackerList();
            renderTrackerDetail();
        });
        list.appendChild(button);
    });
}

function renderTrackerDetail() {
    const tracker = window.selectedTracker;
    const title = document.getElementById('tracker-title');
    const status = document.getElementById('tracker-status');
    const note = document.getElementById('tracker-note');
    const save = document.getElementById('btn-tracker-save');
    const forget = document.getElementById('btn-tracker-forget');
    const track = document.getElementById('btn-tracker-track');

    if (!tracker) {
        title.innerText = 'Select Tracker';
        status.innerText = 'No tracker selected.';
        note.value = '';
        note.disabled = true;
        save.disabled = true;
        forget.disabled = true;
        track.disabled = true;
        return;
    }

    const index = (window.tabletTrackers || []).findIndex((item) => item.id === tracker.id);
    title.innerText = `Tracker ${index + 1}`;
    status.innerText = `${tracker.tier_label || tracker.tier || 'Tracker'} | ${tracker.available ? 'Signal available' : 'Vehicle signal unavailable'}`;
    status.className = `tracker-status ${tracker.available ? 'online' : 'offline'}`;
    note.value = tracker.note || '';
    note.disabled = false;
    save.disabled = false;
    forget.disabled = false;
    track.disabled = !tracker.available;
}

// Button Listeners (Mapped to the 6 physical buttons on the tiered fob images)
document.getElementById('btn-lock').addEventListener('click', () => sendFobAction('lock'));
document.getElementById('btn-unlock').addEventListener('click', () => sendFobAction('unlock'));
document.getElementById('btn-trunk').addEventListener('click', () => sendFobAction('trunk'));
document.getElementById('btn-alarm').addEventListener('click', () => sendFobAction('alarm'));
document.getElementById('btn-lightbulb').addEventListener('click', () => sendFobAction('headlights'));
document.getElementById('btn-info').addEventListener('click', () => sendFobAction('info'));
document.getElementById('btn-remote-engine').addEventListener('click', () => sendFobAction('remote_engine'));
document.getElementById('btn-oled-power').addEventListener('click', toggleOledPower);
document.getElementById('oled-back').addEventListener('click', () => {
    window.oledSection = null;
    renderOledScreen();
});
document.getElementById('oled-home').addEventListener('click', (event) => {
    const button = event.target.closest('[data-oled-section]');
    if (!button) return;
    openOledSection(button.dataset.oledSection);
});
document.getElementById('oled-section-content').addEventListener('click', (event) => {
    const button = event.target.closest('[data-fob-action]');
    if (!button) return;
    sendFobAction(button.dataset.fobAction);
});

document.getElementById('btn-contract-accept').addEventListener('click', () => {
    if (!window.pendingContract) return;

    fetch(`https://${GetParentResourceName()}/signContract`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(window.pendingContract)
    });

    document.getElementById('contract-container').style.display = 'none';
    window.pendingContract = null;
    window.fobToken = null;
    window.gpsTabletToken = null;
});

document.getElementById('btn-contract-cancel').addEventListener('click', () => {
    postNui('closeUI');
    closeAllPanels();
    window.pendingContract = null;
    window.fobToken = null;
    window.gpsTabletToken = null;
});

document.getElementById('btn-tablet-power').addEventListener('click', () => {
    const tabletFrame = document.querySelector('.tablet-frame');
    if (!tabletFrame || document.getElementById('tablet-container').style.display !== 'block') return;

    tabletFrame.classList.toggle('screen-off');
});

document.getElementById('btn-signal-close').addEventListener('click', () => {
    postNui('closeUI');
    closeAllPanels();
    window.signalFinderToken = null;
    window.signalVehicle = null;
    window.signalTrackers = [];
});

document.getElementById('btn-tracker-save').addEventListener('click', () => {
    const tracker = window.selectedTracker;
    if (!tracker) return;

    const note = document.getElementById('tracker-note').value.slice(0, 255);
    tracker.note = note;
    postNui('gpsTabletSaveNote', { id: tracker.id, note, token: window.gpsTabletToken });
    renderTrackerList();
    renderTrackerDetail();
});

document.getElementById('btn-tracker-forget').addEventListener('click', () => {
    const tracker = window.selectedTracker;
    if (!tracker) return;

    postNui('gpsTabletForgetTracker', { id: tracker.id, token: window.gpsTabletToken });
    window.tabletTrackers = (window.tabletTrackers || []).filter((item) => item.id !== tracker.id);
    window.selectedTracker = window.tabletTrackers[0] || null;
    renderTrackerList();
    renderTrackerDetail();
});

document.getElementById('btn-tracker-track').addEventListener('click', () => {
    const tracker = window.selectedTracker;
    if (!tracker || !tracker.available) return;

    postNui('gpsTabletTrack', { id: tracker.id, token: window.gpsTabletToken });
    closeAllPanels();
    window.gpsTabletToken = null;
});

document.getElementById('btn-service-close').addEventListener('click', () => {
    postNui('closeUI');
    closeAllPanels();
    clearServiceState();
});

document.getElementById('btn-key-close').addEventListener('click', () => {
    postNui('closeUI');
    closeAllPanels();
    window.keyMenu = null;
    window.keyMenuToken = null;
});

document.getElementById('btn-locksmith-setup-close').addEventListener('click', () => {
    postNui('closeUI');
    closeAllPanels();
    window.locksmithSetup = null;
    window.locksmithSetupToken = null;
});

document.getElementById('btn-locksmith-setup-finalize').addEventListener('click', () => {
    finalizeCurrentLocksmithSetupLocation();
});

document.getElementById('locksmith-setup-location-name').addEventListener('input', (event) => {
    setLocksmithSetupLocationName(event.target.value.trim() || 'New Locksmith Shop');
    renderLocksmithSetup();
});

document.getElementById('locksmith-setup-job-name').addEventListener('input', () => {
    renderLocksmithSetup();
});

document.getElementById('locksmith-setup-shop-type').addEventListener('change', () => {
    renderLocksmithSetup();
});

document.getElementById('locksmith-setup-stock-method').addEventListener('change', () => {
    renderLocksmithSetup();
});

const setupLocationsTab = document.getElementById('locksmith-setup-tab-locations');
if (setupLocationsTab) {
    setupLocationsTab.addEventListener('click', () => setLocksmithSetupSection('locations'));
}

const setupUniversalTab = document.getElementById('locksmith-setup-tab-universal');
if (setupUniversalTab) {
    setupUniversalTab.addEventListener('click', () => setLocksmithSetupSection('universal'));
}

const setupRecipesTab = document.getElementById('locksmith-setup-tab-recipes');
if (setupRecipesTab) {
    setupRecipesTab.addEventListener('click', () => {
        window.locksmithUniversalPage = 'recipes';
        setLocksmithSetupSection('universal');
    });
}

document.querySelectorAll('.service-tab').forEach((tab) => {
    tab.addEventListener('click', () => setServiceSection(tab.dataset.section));
});

// Escape Hatch
document.addEventListener('keyup', function(event) {
    if (event.key === 'Escape') {
        postNui('closeUI');
        closeAllPanels();
        window.pendingContract = null;
        window.fobToken = null;
        window.gpsTabletToken = null;
        window.signalFinderToken = null;
        clearServiceState();
        window.keyMenu = null;
        window.keyMenuToken = null;
        window.locksmithSetup = null;
        window.locksmithSetupToken = null;
    }
});

// Adaptive UI scaling — keeps every panel proportional on 1080p, 1440p, 4K,
// ultrawide, etc. Scales against a 1920x1080 baseline by the smaller axis
// ratio so panels grow on large displays without ever overflowing.
function updatePartayUiScale() {
    const baseWidth = 1920;
    const baseHeight = 1080;
    const width = window.innerWidth || baseWidth;
    const height = window.innerHeight || baseHeight;
    let scale = Math.min(width / baseWidth, height / baseHeight);
    scale = Math.max(0.8, Math.min(scale, 2.4));
    document.documentElement.style.setProperty('--pk-scale', scale.toFixed(4));
}

window.addEventListener('resize', updatePartayUiScale);
updatePartayUiScale();
