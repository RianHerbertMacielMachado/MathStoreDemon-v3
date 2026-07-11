/* ── Debug NUI logging (controlled by Config.HudDebugNui) ── */
let _hudDebug = false;
const _origLog = console.log;
console.log = function(...args) {
  if (_hudDebug) _origLog.apply(console, args);
};

/* ── i18n / Locale system ── */
const I18N = {
  'pt-BR': {
    pegar_ambos: 'PEGAR AMBOS', pegar_asa: 'PEGAR ASA', pegar_cauda: 'PEGAR CAUDA',
    asa_fechar: 'ASA FECHAR', asa_abrir: 'ASA ABRIR', asa_bater: 'ASA BATER',
    cauda_a: 'CAUDA A', cauda_f: 'CAUDA F', cauda_b: 'CAUDA B',
    toggle_asa: 'PEGAR ASA', toggle_asa_rem: 'REMOVER ASA',
    toggle_cauda: 'PEGAR CAUDA', toggle_cauda_rem: 'REMOVER CAUDA',
    demon_menu: 'DEMON MENU', modo_edit: 'Modo Edit',
    escolha_asa: 'ESCOLHA SUA ASA', desc_asa: 'Digite o número da asa que deseja equipar',
    placeholder_asa: 'ID da asa', cancelar: 'Cancelar', confirmar: 'Confirmar',
    escolha_cauda: 'ESCOLHA SUA CAUDA', desc_cauda: 'Digite o número da cauda que deseja equipar',
    placeholder_cauda: 'ID da cauda',
    bloqueado: 'BLOQUEADO',
  },
  'en-US': {
    pegar_ambos: 'GET BOTH', pegar_asa: 'GET WINGS', pegar_cauda: 'GET TAIL',
    asa_fechar: 'CLOSE WINGS', asa_abrir: 'OPEN WINGS', asa_bater: 'FLAP WINGS',
    cauda_a: 'TAIL OPEN', cauda_f: 'TAIL WRAP', cauda_b: 'TAIL FLAP',
    toggle_asa: 'GET WINGS', toggle_asa_rem: 'REMOVE WINGS',
    toggle_cauda: 'GET TAIL', toggle_cauda_rem: 'REMOVE TAIL',
    demon_menu: 'DEMON MENU', modo_edit: 'Edit Mode',
    escolha_asa: 'CHOOSE YOUR WINGS', desc_asa: 'Enter the wing number you want to equip',
    placeholder_asa: 'Wing ID', cancelar: 'Cancel', confirmar: 'Confirm',
    escolha_cauda: 'CHOOSE YOUR TAIL', desc_cauda: 'Enter the tail number you want to equip',
    placeholder_cauda: 'Tail ID',
    bloqueado: 'LOCKED',
  },
  'es': {
    pegar_ambos: 'OBTENER AMBOS', pegar_asa: 'OBTENER ALAS', pegar_cauda: 'OBTENER COLA',
    asa_fechar: 'CERRAR ALAS', asa_abrir: 'ABRIR ALAS', asa_bater: 'BATIR ALAS',
    cauda_a: 'COLA ABIERTA', cauda_f: 'COLA ENROLL', cauda_b: 'COLA BATIR',
    toggle_asa: 'OBTENER ALAS', toggle_asa_rem: 'QUITAR ALAS',
    toggle_cauda: 'OBTENER COLA', toggle_cauda_rem: 'QUITAR COLA',
    demon_menu: 'MENÚ DEMON', modo_edit: 'Modo Edición',
    escolha_asa: 'ELIGE TUS ALAS', desc_asa: 'Ingresa el número del ala que deseas equipar',
    placeholder_asa: 'ID del ala', cancelar: 'Cancelar', confirmar: 'Confirmar',
    escolha_cauda: 'ELIGE TU COLA', desc_cauda: 'Ingresa el número de la cola que deseas equipar',
    placeholder_cauda: 'ID de la cola',
    bloqueado: 'BLOQUEADO',
  },
  'fr': {
    pegar_ambos: 'OBTENIR LES DEUX', pegar_asa: 'OBTENIR AILES', pegar_cauda: 'OBTENIR QUEUE',
    asa_fechar: 'FERMER AILES', asa_abrir: 'OUVRIR AILES', asa_bater: 'BATTRE AILES',
    cauda_a: 'QUEUE DROITE', cauda_f: 'QUEUE ENROULÉE', cauda_b: 'QUEUE BATTRE',
    toggle_asa: 'OBTENIR AILES', toggle_asa_rem: 'RETIRER AILES',
    toggle_cauda: 'OBTENIR QUEUE', toggle_cauda_rem: 'RETIRER QUEUE',
    demon_menu: 'MENU DÉMON', modo_edit: 'Mode Édition',
    escolha_asa: 'CHOISISSEZ VOS AILES', desc_asa: 'Entrez le numéro des ailes à équiper',
    placeholder_asa: 'ID des ailes', cancelar: 'Annuler', confirmar: 'Confirmer',
    escolha_cauda: 'CHOISISSEZ VOTRE QUEUE', desc_cauda: 'Entrez le numéro de la queue à équiper',
    placeholder_cauda: 'ID de la queue',
    bloqueado: 'VERROUILLÉ',
  },
  'pt-PT': {
    pegar_ambos: 'OBTER AMBOS', pegar_asa: 'OBTER ASAS', pegar_cauda: 'OBTER CAUDA',
    asa_fechar: 'FECHAR ASAS', asa_abrir: 'ABRIR ASAS', asa_bater: 'BATER ASAS',
    cauda_a: 'CAUDA A', cauda_f: 'CAUDA F', cauda_b: 'CAUDA B',
    toggle_asa: 'OBTER ASAS', toggle_asa_rem: 'REMOVER ASAS',
    toggle_cauda: 'OBTER CAUDA', toggle_cauda_rem: 'REMOVER CAUDA',
    demon_menu: 'MENU DEMON', modo_edit: 'Modo Edição',
    escolha_asa: 'ESCOLHA AS SUAS ASAS', desc_asa: 'Introduza o número da asa que deseja equipar',
    placeholder_asa: 'ID da asa', cancelar: 'Cancelar', confirmar: 'Confirmar',
    escolha_cauda: 'ESCOLHA A SUA CAUDA', desc_cauda: 'Introduza o número da cauda que deseja equipar',
    placeholder_cauda: 'ID da cauda',
    bloqueado: 'BLOQUEADO',
  },
  'th': {
    pegar_ambos: 'รับทั้งสอง', pegar_asa: 'รับปีก', pegar_cauda: 'รับหาง',
    asa_fechar: 'ปิดปีก', asa_abrir: 'เปิดปีก', asa_bater: 'กระพือปีก',
    cauda_a: 'หางตรง', cauda_f: 'หางม้วน', cauda_b: 'หางกระพือ',
    toggle_asa: 'รับปีก', toggle_asa_rem: 'ถอดปีก',
    toggle_cauda: 'รับหาง', toggle_cauda_rem: 'ถอดหาง',
    demon_menu: 'เมนู DEMON', modo_edit: 'โหมดแก้ไข',
    escolha_asa: 'เลือกปีกของคุณ', desc_asa: 'ป้อนหมายเลขปีกที่ต้องการสวม',
    placeholder_asa: 'ID ปีก', cancelar: 'ยกเลิก', confirmar: 'ยืนยัน',
    escolha_cauda: 'เลือกหางของคุณ', desc_cauda: 'ป้อนหมายเลขหางที่ต้องการสวม',
    placeholder_cauda: 'ID หาง',
    bloqueado: 'ล็อค',
  },
};

let currentLocale = 'pt-BR';

function t(key) {
  return (I18N[currentLocale] && I18N[currentLocale][key]) || (I18N['pt-BR'] && I18N['pt-BR'][key]) || key;
}

function applyLocale() {
  document.querySelectorAll('[data-i18n]').forEach(function(el) {
    el.textContent = t(el.dataset.i18n);
  });
  document.querySelectorAll('[data-i18n-placeholder]').forEach(function(el) {
    el.placeholder = t(el.dataset.i18nPlaceholder);
  });
  // Update toggle labels based on current state
  if (btn3Label) btn3Label.textContent = hasWing ? t('toggle_asa_rem') : t('toggle_asa');
  if (btn7Label) btn7Label.textContent = hasTail ? t('toggle_cauda_rem') : t('toggle_cauda');
}

/* ── DOM refs ── */
const items = Array.from(document.querySelectorAll('#menuComAsa .radial-item'));
const scene = document.querySelector('.scene');
const root = document.documentElement;
const editToggle = document.getElementById('editToggle');
const editPanel = document.getElementById('editPanel');
const resetLayout = document.getElementById('resetLayout');
const resetPosition = document.getElementById('resetPosition');
const copyLayout = document.getElementById('copyLayout');
const coreIcon = document.querySelector('#coreComAsa .core-wing');

const controls = {
  menuScale: document.getElementById('ctrlScale'),
  menuOffsetX: document.getElementById('ctrlOffsetX'),
  menuOffsetY: document.getElementById('ctrlOffsetY'),
  radius: document.getElementById('ctrlRadius'),
  rotationOffset: document.getElementById('ctrlRotationOffset'),
  itemSize: document.getElementById('ctrlItemSize'),
  iconSize: document.getElementById('ctrlIconSize'),
  iconOffsetX: document.getElementById('ctrlIconOffsetX'),
  iconOffsetY: document.getElementById('ctrlIconOffsetY'),
  labelSize: document.getElementById('ctrlLabelSize'),
  itemLabelOffsetY: document.getElementById('ctrlItemLabelOffsetY'),
  showItemLabels: document.getElementById('ctrlShowItemLabels'),
  showBadges: document.getElementById('ctrlShowBadges'),
  coreIconSize: document.getElementById('ctrlCoreIconSize'),
  coreIconOffsetY: document.getElementById('ctrlCoreIconOffsetY'),
  coreIconPath: document.getElementById('ctrlCoreIconPath'),
  coreLabelSize: document.getElementById('ctrlCoreLabelSize'),
  coreLabelOffset: document.getElementById('ctrlCoreLabelOffset'),
  showCoreLabel: document.getElementById('ctrlShowCoreLabel'),
  clipItemIcons: document.getElementById('ctrlClipItemIcons'),
  colorRing: document.getElementById('ctrlColorRing'),
  colorItemBorder: document.getElementById('ctrlColorItemBorder'),
  colorActiveBorder: document.getElementById('ctrlColorActiveBorder'),
  colorText: document.getElementById('ctrlColorText'),
};

const checkboxKeys = new Set(['showItemLabels', 'showBadges', 'showCoreLabel', 'clipItemIcons']);

const STORAGE_KEY = 'demonHudLayoutV1';

let hudClosed = true;
let editMode = false;
let hasWing = false;
let hasTail = false;
let canEquipWings = true;
let inWingIdPanel = false;
let inTailIdPanel = false;

// FiveM NUI helper
function postToLua(name, data) {
  return fetch('https://' + GetParentResourceName() + '/' + name, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data || {}),
  }).catch(function() {});
}

const defaults = {
  menuScale: '1.47',
  menuOffsetX: '0',
  menuOffsetY: '0',
  radius: '188',
  rotationOffset: '0',
  itemSize: '114',
  iconSize: '112',
  iconOffsetX: '-1',
  iconOffsetY: '-28',
  labelSize: '0.63',
  itemLabelOffsetY: '-10',
  showItemLabels: '1',
  showBadges: '0',
  coreIconSize: '150',
  coreIconOffsetY: '6',
  coreIconPath: 'assets/img/demon/central3.png',
  coreLabelSize: '0.79',
  coreLabelOffset: '-24',
  showCoreLabel: '0',
  clipItemIcons: '0',
  colorRing: '#3a0808',
  colorItemBorder: '#3a0808',
  colorActiveBorder: '#661515',
  colorText: '#f7e7e7',
};

/* ── Layout system ── */

function toggleEditMode(forceValue) {
  editMode = typeof forceValue === 'boolean' ? forceValue : !editMode;
  editPanel.hidden = !editMode;
  editToggle.setAttribute('aria-expanded', String(editMode));
}

function readLayoutFromControls() {
  const data = {};
  Object.keys(controls).forEach((key) => {
    const control = controls[key];
    if (!control) return;
    if (checkboxKeys.has(key)) {
      data[key] = control.checked ? '1' : '0';
    } else {
      data[key] = control.value;
    }
  });
  return data;
}

function applyLayout(layout) {
  root.style.setProperty('--menu-scale', layout.menuScale);
  root.style.setProperty('--menu-offset-x', `${layout.menuOffsetX}px`);
  root.style.setProperty('--menu-offset-y', `${layout.menuOffsetY}px`);
  root.style.setProperty('--radius', `${layout.radius}px`);
  root.style.setProperty('--rotation-offset', `${layout.rotationOffset || 0}deg`);
  root.style.setProperty('--item-size', `${layout.itemSize}px`);

  const rotValEl = document.getElementById('rotationValue');
  if (rotValEl) rotValEl.textContent = `${layout.rotationOffset || 0}\u00b0`;
  root.style.setProperty('--icon-size', `${layout.iconSize}px`);
  root.style.setProperty('--icon-offset-x', `${layout.iconOffsetX}px`);
  root.style.setProperty('--icon-offset-y', `${layout.iconOffsetY}px`);
  root.style.setProperty('--label-size', `${layout.labelSize}rem`);
  root.style.setProperty('--item-label-offset-y', `${layout.itemLabelOffsetY}px`);
  root.style.setProperty('--core-icon-size', `${layout.coreIconSize}px`);
  root.style.setProperty('--core-icon-offset-y', `${layout.coreIconOffsetY}px`);
  root.style.setProperty('--core-label-size', `${layout.coreLabelSize}rem`);
  root.style.setProperty('--core-label-offset', `${layout.coreLabelOffset}px`);
  root.style.setProperty('--ring-color', layout.colorRing);
  root.style.setProperty('--item-border-color', layout.colorItemBorder);
  root.style.setProperty('--active-border-color', layout.colorActiveBorder);
  root.style.setProperty('--text', layout.colorText);

  if (coreIcon) coreIcon.src = layout.coreIconPath;

  document.body.classList.toggle('hide-item-labels', layout.showItemLabels !== '1');
  document.body.classList.toggle('hide-core-label', layout.showCoreLabel !== '1');
  document.body.classList.toggle('hide-badges', layout.showBadges !== '1');
  document.body.classList.toggle('clip-item-icons', layout.clipItemIcons === '1');
}

function saveLayout(layout) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(layout));
}

function loadLayout() {
  let saved = null;
  try {
    saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null');
  } catch (_err) {
    saved = null;
  }

  const layout = { ...defaults, ...(saved || {}) };

  Object.keys(controls).forEach((key) => {
    const control = controls[key];
    if (!control) return;
    if (checkboxKeys.has(key)) {
      control.checked = layout[key] === '1';
    } else {
      control.value = layout[key];
    }
  });

  applyLayout(layout);
  return layout;
}

function bindEditorControls() {
  Object.keys(controls).forEach((key) => {
    const control = controls[key];
    if (!control) return;
    const handler = () => {
      const layout = readLayoutFromControls();
      applyLayout(layout);
      saveLayout(layout);
    };
    control.addEventListener('input', handler);
    control.addEventListener('change', handler);
  });

  editToggle.addEventListener('click', () => toggleEditMode());

  if (resetPosition) {
    resetPosition.addEventListener('click', () => {
      controls.menuOffsetX.value = '0';
      controls.menuOffsetY.value = '0';
      const layout = readLayoutFromControls();
      applyLayout(layout);
      saveLayout(layout);
    });
  }

  resetLayout.addEventListener('click', () => {
    Object.keys(controls).forEach((key) => {
      const control = controls[key];
      if (!control) return;
      if (checkboxKeys.has(key)) {
        control.checked = defaults[key] === '1';
      } else {
        control.value = defaults[key];
      }
    });
    applyLayout(defaults);
    saveLayout(defaults);
  });

  copyLayout.addEventListener('click', async () => {
    const payload = JSON.stringify(readLayoutFromControls(), null, 2);
    try {
      await navigator.clipboard.writeText(payload);
      copyLayout.textContent = 'Copiado!';
      setTimeout(() => { copyLayout.textContent = 'Copiar JSON'; }, 1200);
    } catch (_err) {
      copyLayout.textContent = 'Falhou';
      setTimeout(() => { copyLayout.textContent = 'Copiar JSON'; }, 1200);
    }
  });
}

/* ── HUD open/close ── */

function openHud() {
  if (!scene || !hudClosed) return;
  scene.style.display = '';
  scene.classList.add('hud-entering');
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      scene.classList.remove('hud-entering');
      scene.classList.remove('hud-hidden');
    });
  });
  hudClosed = false;
}

function closeHud() {
  if (!scene || hudClosed) return;
  scene.classList.add('hud-hidden');
  hudClosed = true;
  postToLua('closeHud');
  scene.addEventListener('transitionend', function handler() {
    scene.removeEventListener('transitionend', handler);
    if (hudClosed) scene.style.display = 'none';
  });
}

function setActiveItem(nextItem) {
  items.forEach((item) => item.classList.remove('is-active'));
  nextItem.classList.add('is-active');
}

/* ── Wing/Tail state ── */

const menuNoAsa = document.getElementById('menuNoAsa');
const menuComAsa = document.getElementById('menuComAsa');
const coreNoAsa = document.getElementById('coreNoAsa');

// NoAsa side buttons
const btnNoAsaAsa = document.getElementById('btnNoAsaAsa');
const btnNoAsaCauda = document.getElementById('btnNoAsaCauda');

// Toggle buttons in menuComAsa
const btn3Label = document.getElementById('btn3Label');
const btn7Label = document.getElementById('btn7Label');

// Wing ID panel
const wingIdPanel = document.getElementById('wingIdPanel');
const wingIdInput = document.getElementById('wingIdInput');
const wingIdConfirm = document.getElementById('wingIdConfirm');
const wingIdCancel = document.getElementById('wingIdCancel');

// Tail ID panel
const tailIdPanel = document.getElementById('tailIdPanel');
const tailIdInput = document.getElementById('tailIdInput');
const tailIdConfirm = document.getElementById('tailIdConfirm');
const tailIdCancel = document.getElementById('tailIdCancel');

// Track what we're opening the ID panel for
let idPanelTarget = 'both'; // 'both', 'wing', 'tail', 'wing-toggle', 'tail-toggle'

function updateDynamicButtons() {
  // Button 3: toggle wing
  if (btn3Label) {
    btn3Label.textContent = hasWing ? t('toggle_asa_rem') : t('toggle_asa');
  }
  // Button 7: toggle tail
  if (btn7Label) {
    btn7Label.textContent = hasTail ? t('toggle_cauda_rem') : t('toggle_cauda');
  }
}

function applyWingState() {
  // Clean up transition classes from ID panels
  menuNoAsa.classList.remove('view-out');
  menuComAsa.classList.remove('view-out');

  // menuNoAsa only shows when NEITHER wing NOR tail equipped
  if (hasWing || hasTail) {
    menuNoAsa.hidden = true;
    menuComAsa.hidden = false;
  } else {
    menuComAsa.hidden = true;
    menuNoAsa.hidden = false;
  }
  wingIdPanel.hidden = true;
  wingIdPanel.classList.remove('view-in');
  inWingIdPanel = false;
  tailIdPanel.hidden = true;
  tailIdPanel.classList.remove('view-in');
  inTailIdPanel = false;

  updateDynamicButtons();
}

/* ── Wing ID Panel ── */

function applyCanEquip() {
  var title = coreNoAsa.querySelector('.core-title');
  if (canEquipWings) {
    coreNoAsa.classList.remove('core-locked');
    if (btnNoAsaAsa) btnNoAsaAsa.classList.remove('core-locked');
    if (btnNoAsaCauda) btnNoAsaCauda.classList.remove('core-locked');
    if (title) title.textContent = t('pegar_ambos');
  } else {
    coreNoAsa.classList.add('core-locked');
    if (btnNoAsaAsa) btnNoAsaAsa.classList.add('core-locked');
    if (btnNoAsaCauda) btnNoAsaCauda.classList.add('core-locked');
    if (title) title.textContent = t('bloqueado');
  }
}

function openWingIdPanel(fromMenu) {
  if (!canEquipWings) return;
  const parentMenu = fromMenu === 'comAsa' ? menuComAsa : menuNoAsa;
  parentMenu.classList.add('view-out');
  wingIdPanel.hidden = false;
  wingIdInput.value = '';
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      wingIdPanel.classList.add('view-in');
      wingIdInput.focus();
    });
  });
  inWingIdPanel = true;
}

function closeWingIdPanel() {
  if (!inWingIdPanel) return;
  wingIdPanel.classList.remove('view-in');
  menuNoAsa.classList.remove('view-out');
  menuComAsa.classList.remove('view-out');
  wingIdPanel.addEventListener('transitionend', function handler() {
    wingIdPanel.removeEventListener('transitionend', handler);
    wingIdPanel.hidden = true;
  });
  inWingIdPanel = false;
}

function confirmWingId() {
  const id = wingIdInput.value.trim();
  if (!id) {
    wingIdInput.focus();
    return;
  }

  if (idPanelTarget === 'both') {
    // Equip both wing + tail with same ID
    postToLua('hudAction', { action: 'pegarambos', wingId: id, tailId: id });
    hasWing = true;
    hasTail = true;
  } else {
    // Equip wing only
    postToLua('hudAction', { action: 'pegarasa', wingId: id });
    hasWing = true;
  }

  inWingIdPanel = false;
  wingIdPanel.classList.remove('view-in');
  wingIdPanel.hidden = true;
  closeHud();
  setTimeout(() => { applyWingState(); }, 300);
}

// Core center click: PEGAR AMBOS
coreNoAsa.addEventListener('click', () => {
  idPanelTarget = 'both';
  openWingIdPanel('noAsa');
});

// Side button: PEGAR ASA only
btnNoAsaAsa.addEventListener('click', () => {
  idPanelTarget = 'wing';
  openWingIdPanel('noAsa');
});

// Side button: PEGAR CAUDA only
btnNoAsaCauda.addEventListener('click', () => {
  idPanelTarget = 'tail';
  openTailIdPanel('noAsa');
});

wingIdCancel.addEventListener('click', closeWingIdPanel);
wingIdConfirm.addEventListener('click', confirmWingId);
wingIdInput.addEventListener('keydown', (e) => {
  e.stopPropagation();
  if (e.key === 'Enter') confirmWingId();
  if (e.key === 'Escape') closeWingIdPanel();
});

/* ── Tail ID Panel ── */

function openTailIdPanel(fromMenu) {
  if (!canEquipWings) return;
  const parentMenu = fromMenu === 'noAsa' ? menuNoAsa : menuComAsa;
  parentMenu.classList.add('view-out');
  tailIdPanel.hidden = false;
  tailIdInput.value = '';
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      tailIdPanel.classList.add('view-in');
      tailIdInput.focus();
    });
  });
  inTailIdPanel = true;
}

function closeTailIdPanel() {
  if (!inTailIdPanel) return;
  tailIdPanel.classList.remove('view-in');
  menuComAsa.classList.remove('view-out');
  menuNoAsa.classList.remove('view-out');
  tailIdPanel.addEventListener('transitionend', function handler() {
    tailIdPanel.removeEventListener('transitionend', handler);
    tailIdPanel.hidden = true;
  });
  inTailIdPanel = false;
}

function confirmTailId() {
  const id = tailIdInput.value.trim();
  if (!id) {
    tailIdInput.focus();
    return;
  }
  postToLua('hudAction', { action: 'pegarcauda', tailId: id });
  hasTail = true;
  inTailIdPanel = false;
  tailIdPanel.classList.remove('view-in');
  tailIdPanel.hidden = true;
  closeHud();
  setTimeout(() => { applyWingState(); }, 300);
}

tailIdCancel.addEventListener('click', closeTailIdPanel);
tailIdConfirm.addEventListener('click', confirmTailId);
tailIdInput.addEventListener('keydown', (e) => {
  e.stopPropagation();
  if (e.key === 'Enter') confirmTailId();
  if (e.key === 'Escape') closeTailIdPanel();
});

/* ── Radial button clicks ── */

items.forEach((item) => {
  item.addEventListener('click', () => {
    const action = item.dataset.action;

    // Button 3: toggle wing (pegar/remover)
    if (action === 'toggleasa') {
      if (hasWing) {
        postToLua('hudAction', { action: 'removerasa' });
        hasWing = false;
        // If neither wing nor tail, go back to initial menu
        if (!hasTail) {
          closeHud();
          setTimeout(() => { applyWingState(); }, 300);
        } else {
          updateDynamicButtons();
          closeHud();
        }
      } else {
        idPanelTarget = 'wing-toggle';
        openWingIdPanel('comAsa');
      }
      return;
    }

    // Button 7: toggle tail (pegar/remover)
    if (action === 'togglecauda') {
      if (hasTail) {
        postToLua('hudAction', { action: 'removercauda' });
        hasTail = false;
        // If neither wing nor tail, go back to initial menu
        if (!hasWing) {
          closeHud();
          setTimeout(() => { applyWingState(); }, 300);
        } else {
          updateDynamicButtons();
          closeHud();
        }
      } else {
        idPanelTarget = 'tail-toggle';
        openTailIdPanel('comAsa');
      }
      return;
    }

    // All other buttons: send action directly
    postToLua('hudAction', { action: action });
    closeHud();
  });
});

/* ── Init ── */

applyWingState();

// Start hidden
if (scene) {
  scene.classList.add('hud-hidden');
  scene.style.display = 'none';
}

bindEditorControls();
loadLayout();
toggleEditMode(false);

/* ── Keyboard ── */

document.addEventListener('keydown', (event) => {
  const targetInsideEditor = event.target && event.target.closest && event.target.closest('.edit-panel');

  if (event.key === 'Escape' || event.code === 'Escape') {
    event.preventDefault();
    event.stopPropagation();
    if (editMode) {
      toggleEditMode(false);
      return;
    }
    if (inWingIdPanel) {
      closeWingIdPanel();
      return;
    }
    if (inTailIdPanel) {
      closeTailIdPanel();
      return;
    }
    closeHud();
    return;
  }

  if (targetInsideEditor) return;

  const currentIndex = items.findIndex((item) => item.classList.contains('is-active'));
  if (currentIndex === -1) return;

  let nextIndex = currentIndex;

  if (event.key === 'ArrowRight' || event.key === 'ArrowDown') {
    nextIndex = (currentIndex + 1) % items.length;
  }

  if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') {
    nextIndex = (currentIndex - 1 + items.length) % items.length;
  }

  if (nextIndex !== currentIndex) {
    event.preventDefault();
    setActiveItem(items[nextIndex]);
  }
});

/* ── FiveM NUI message listener ── */

window.addEventListener('message', function(event) {
  const data = event.data;
  if (data.action === 'openHud') {
    document.body.classList.toggle('black-bg', !!data.hudBlackBg);
    _hudDebug = !!data.hudDebugNui;
    hasWing = !!data.hasWing;
    hasTail = !!data.hasTail;
    canEquipWings = data.canEquip !== false;
    currentLocale = data.locale || 'pt-BR';
    applyLocale();
    applyWingState();
    applyCanEquip();
    openHud();
  } else if (data.action === 'closeHud') {
    closeHud();
    document.body.classList.remove('black-bg');
  }
});
