import {
  DEFAULT_THEME,
  THEMES,
  analyzeFile,
  coerceTheme,
  renderTextDocument,
} from './viewer-core.mjs';

// QW WASM Viewer browser UI
// WASM module loaded dynamically and falls back to JS helpers if pkg/ is not built.

let wasmInit;
let detect_file_type;
let format_hex_row;
let decode_bytes;

// ─── State ───────────────────────────────────────────────────
const state = {
  fileData: null,
  fileName: '',
  fileSize: 0,
  fileType: '',
  totalRows: 0,
  cursor: -1,
  littleEndian: true,
  wasmReady: false,
  rowHeight: 22,
  bytesPerRow: 16,
  activeView: 'binary',
  analysis: null,
  theme: loadStoredTheme(),
  renderedTextHtml: '',
};

// ─── DOM refs ────────────────────────────────────────────────
const $ = (sel) => document.querySelector(sel);
const body = document.body;
const dropZone = $('#drop-zone');
const hexViewer = $('#hex-viewer');
const binaryViewer = $('#binary-viewer');
const textViewer = $('#text-viewer');
const textViewNote = $('#text-view-note');
const textScrollContainer = $('#text-scroll-container');
const textContent = $('#text-content');
const scrollContainer = $('#hex-scroll-container');
const scrollContent = $('#hex-scroll-content');
const hexHeader = $('#hex-header');
const dataInspector = $('#data-inspector');
const inspectorEl = $('#inspector-content');
const btnToggleInspector = $('#btn-toggle-inspector');
const btnViewText = $('#btn-view-text');
const btnViewBinary = $('#btn-view-binary');
const viewToggle = $('#view-toggle');
const themeSelect = $('#theme-select');
const statusFileName = $('#status-file-name');
const statusFileSize = $('#status-file-size');
const statusCursor = $('#status-cursor-offset');
const statusType = $('#status-detected-type');
const fileTypeBadge = $('#file-type-badge');
const fileModeInfo = $('#file-mode-info');
const fileSizeInfo = $('#file-size-info');
const fileRowsInfo = $('#file-rows-info');
const fileInput = $('#file-input');

// ─── Init WASM ───────────────────────────────────────────────
async function initWasm() {
  try {
    const wasm = await import('../pkg/qw_wasm.js');
    wasmInit = wasm.default;
    detect_file_type = wasm.detect_file_type;
    format_hex_row = wasm.format_hex_row;
    decode_bytes = wasm.decode_bytes;
    await wasmInit();
    state.wasmReady = true;
    console.log('[QW] WASM module loaded');
  } catch (err) {
    console.warn('[QW] WASM module not available, using JS fallback:', err.message);
    state.wasmReady = false;
  }
}

// ─── JS Fallbacks (when WASM not built yet) ──────────────────
const fallback = {
  detect_file_type(bytes) {
    if (!bytes || bytes.length < 4) return 'Unknown';
    const sig = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    const sig2 = (bytes[0] << 8) | bytes[1];
    if (sig === 0x89504e47) return 'PNG Image';
    if (sig2 === 0xffd8) return 'JPEG Image';
    if (sig === 0x47494638) return 'GIF Image';
    if (sig === 0x25504446) return 'PDF Document';
    if (sig2 === 0x504b) return 'ZIP Archive';
    if (sig2 === 0x4d5a) return 'PE Executable';
    if (sig === 0x7f454c46) return 'ELF Binary';
    if (sig === 0xcafebabe || sig === 0xfeedface || sig === 0xfeedfacf) return 'Mach-O Binary';
    if (bytes[0] === 0x52 && bytes[1] === 0x61 && bytes[2] === 0x72) return 'RAR Archive';
    if (sig === 0x1f8b0800 || sig2 === 0x1f8b) return 'Gzip Archive';

    let textCount = 0;
    const check = Math.min(bytes.length, 512);
    for (let i = 0; i < check; i += 1) {
      if ((bytes[i] >= 32 && bytes[i] < 127) || bytes[i] === 10 || bytes[i] === 13 || bytes[i] === 9) {
        textCount += 1;
      }
    }
    if (check > 0 && textCount / check > 0.85) return 'Text File';
    return 'Binary File';
  },

  format_hex_row(bytes, offset) {
    const hex = [];
    const ascii = [];
    const types = [];

    for (let i = 0; i < 16; i += 1) {
      if (i < bytes.length) {
        const value = bytes[i];
        hex.push(value.toString(16).padStart(2, '0'));
        ascii.push(value >= 32 && value < 127 ? String.fromCharCode(value) : '.');
        if (value === 0) types.push('null');
        else if (value === 0x09 || value === 0x0A || value === 0x0D || value === 0x20) types.push('whitespace');
        else if (value < 32) types.push('control');
        else if (value < 127) types.push('printable');
        else types.push('high');
      } else {
        hex.push('  ');
        ascii.push(' ');
        types.push('null');
      }
    }

    return JSON.stringify({ offset, hex, ascii, types });
  },

  decode_bytes(bytes, offset, littleEndian) {
    if (!bytes || offset < 0 || offset >= bytes.length) return '{}';

    const remaining = bytes.length - offset;
    const view = new DataView(bytes.buffer, bytes.byteOffset + offset, Math.min(remaining, 8));
    const result = {
      offset: `0x${offset.toString(16).padStart(8, '0')}`,
      uint8: view.getUint8(0),
      int8: view.getInt8(0),
    };

    result.binary = result.uint8.toString(2).padStart(8, '0');
    result.ascii = result.uint8 >= 32 && result.uint8 < 127 ? String.fromCharCode(result.uint8) : 'N/A';

    if (remaining >= 2) {
      result.uint16 = view.getUint16(0, littleEndian);
      result.int16 = view.getInt16(0, littleEndian);
    }

    if (remaining >= 4) {
      result.uint32 = view.getUint32(0, littleEndian);
      result.int32 = view.getInt32(0, littleEndian);
      result.float32 = view.getFloat32(0, littleEndian);
    }

    if (remaining >= 8) {
      result.float64 = view.getFloat64(0, littleEndian);
      const low = littleEndian ? view.getUint32(0, true) : view.getUint32(4, false);
      const high = littleEndian ? view.getInt32(4, true) : view.getInt32(0, false);
      result.int64 = ((BigInt(high) << 32n) | BigInt(low >>> 0)).toString();
    }

    return JSON.stringify(result);
  },
};

// ─── Wrappers (WASM with JS fallback) ───────────────────────
function callDetectFileType(bytes) {
  if (state.wasmReady) return detect_file_type(bytes);
  return fallback.detect_file_type(bytes);
}

function callFormatHexRow(rowBytes, offset) {
  if (state.wasmReady) return format_hex_row(rowBytes, offset);
  return fallback.format_hex_row(rowBytes, offset);
}

function callDecodeBytes(bytes, offset, littleEndian) {
  if (state.wasmReady) return decode_bytes(bytes, offset, littleEndian);
  return fallback.decode_bytes(bytes, offset, littleEndian);
}

// ─── File loading ────────────────────────────────────────────
function loadFile(file) {
  state.fileName = file.name;

  const reader = new FileReader();
  reader.onload = (event) => {
    state.fileData = new Uint8Array(event.target.result);
    state.fileSize = state.fileData.length;
    state.totalRows = Math.ceil(state.fileSize / state.bytesPerRow);
    state.cursor = -1;
    state.renderedTextHtml = '';
    scrollContainer.scrollTop = 0;
    textScrollContainer.scrollTop = 0;

    const headerBytes = state.fileData.slice(0, Math.min(4096, state.fileData.length));
    const detectedTypeRaw = callDetectFileType(headerBytes);
    state.analysis = analyzeFile(state.fileName, state.fileData, detectedTypeRaw);
    state.fileType = detectedTypeLabel();

    showViewer();
    buildHeader();
    setActiveView(state.analysis.preferredView);
  };

  reader.readAsArrayBuffer(file);
}

function showViewer() {
  dropZone.classList.add('hidden');
  hexViewer.classList.remove('hidden');
}

function renderCurrentView() {
  if (!state.fileData || !state.analysis) return;

  const isText = state.activeView === 'text' && state.analysis.availableViews.text;
  textViewer.classList.toggle('hidden', !isText);
  binaryViewer.classList.toggle('hidden', isText);
  btnToggleInspector.classList.toggle('hidden', isText);

  if (isText) {
    renderTextView();
    return;
  }

  renderBinaryView();
}

function renderBinaryView() {
  scrollContent.style.height = `${state.totalRows * state.rowHeight}px`;
  scrollContent.innerHTML = '';
  renderVisibleRows();

  if (state.cursor >= 0) {
    updateInspector();
  } else {
    inspectorEl.innerHTML = '<p class="inspector-placeholder">Click a byte to inspect</p>';
  }
}

function renderTextView() {
  const { analysis } = state;
  if (!analysis || !analysis.canShowText) return;

  if (!state.renderedTextHtml) {
    state.renderedTextHtml = renderTextDocument(analysis.text, analysis.language, {
      highlight: analysis.canHighlight,
    });
  }

  textContent.innerHTML = state.renderedTextHtml;
  textViewNote.textContent = analysis.note;
  textViewNote.classList.toggle('hidden', !analysis.note);
}

function setActiveView(view) {
  if (!state.fileData || !state.analysis) return;

  const wantsText = view === 'text' && state.analysis.availableViews.text;
  state.activeView = wantsText ? 'text' : 'binary';

  updateViewToggle();
  updateFileInfo();
  updateStatusBar();
  renderCurrentView();
}

function updateViewToggle() {
  const canShowText = Boolean(state.analysis?.availableViews.text);
  viewToggle.classList.toggle('hidden', !canShowText);
  btnViewText.classList.toggle('active', canShowText && state.activeView === 'text');
  btnViewBinary.classList.toggle('active', state.activeView === 'binary');
  btnViewText.disabled = !canShowText;
}

function updateFileInfo() {
  if (!state.analysis) return;

  const textModeSuffix = state.analysis.canHighlight ? 'highlighted' : 'plain';
  fileTypeBadge.textContent = detectedTypeLabel();
  fileModeInfo.textContent = state.activeView === 'text'
    ? `${state.analysis.textLabel} · ${textModeSuffix}`
    : 'Binary view · hex + ASCII';
  fileSizeInfo.textContent = formatSize(state.fileSize);
  fileRowsInfo.textContent = state.activeView === 'text'
    ? `${state.analysis.lineCount.toLocaleString()} lines`
    : `${state.totalRows.toLocaleString()} rows`;
}

function updateStatusBar() {
  statusFileName.textContent = state.fileName || 'No file loaded';
  statusFileSize.textContent = state.fileData ? formatSize(state.fileSize) : '';

  if (!state.fileData || !state.analysis) {
    statusCursor.textContent = '';
    statusType.textContent = '';
    return;
  }

  if (state.activeView === 'binary') {
    statusCursor.textContent = state.cursor >= 0
      ? `Offset 0x${state.cursor.toString(16).toUpperCase().padStart(8, '0')}`
      : `${state.totalRows.toLocaleString()} rows`;
  } else {
    statusCursor.textContent = `${state.analysis.lineCount.toLocaleString()} lines`;
  }

  const themeLabel = THEMES.find((theme) => theme.id === state.theme)?.label || DEFAULT_THEME;
  const viewLabel = state.activeView === 'text'
    ? `${state.analysis.textLabel}${state.analysis.canHighlight ? '' : ' (plain)'}`
    : 'Binary hex viewer';
  statusType.textContent = `${viewLabel} · ${detectedTypeLabel()} · ${themeLabel}`;
}

function detectedTypeLabel() {
  if (!state.analysis) {
    return 'Unknown';
  }

  const detected = state.analysis.detectedType?.name;
  if (detected && detected !== 'Unknown') {
    return detected;
  }

  return state.analysis.canShowText ? 'Text File' : 'Binary File';
}

function loadStoredTheme() {
  try {
    return coerceTheme(window.localStorage.getItem('qw-viewer-theme'));
  } catch {
    return DEFAULT_THEME;
  }
}

function applyTheme(themeName) {
  const theme = coerceTheme(themeName);
  state.theme = theme;
  body.dataset.theme = theme;
  themeSelect.value = theme;

  try {
    window.localStorage.setItem('qw-viewer-theme', theme);
  } catch {
    // Ignore storage access failures.
  }

  if (state.fileData) {
    updateStatusBar();
  }
}

function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

// ─── Column header ───────────────────────────────────────────
function buildHeader() {
  let html = '<span class="header-offset">Offset</span><span class="header-hex">';
  for (let i = 0; i < 16; i += 1) {
    const gap = i === 8 ? ' style="margin-left:8px"' : '';
    html += `<span style="display:inline-block;width:24px;text-align:center"${gap}>${i.toString(16).toUpperCase()}</span>`;
  }
  html += '</span><span class="header-ascii">ASCII</span>';
  hexHeader.innerHTML = html;
}

// ─── Virtual scroll rendering ────────────────────────────────
function renderVisibleRows() {
  if (!state.fileData || state.activeView !== 'binary') return;

  const containerHeight = scrollContainer.clientHeight;
  const scrollTop = scrollContainer.scrollTop;
  const overscan = 5;

  const firstVisible = Math.max(0, Math.floor(scrollTop / state.rowHeight) - overscan);
  const lastVisible = Math.min(
    state.totalRows - 1,
    Math.ceil((scrollTop + containerHeight) / state.rowHeight) + overscan,
  );

  const existing = scrollContent.querySelectorAll('.hex-row');
  const existingMap = new Map();
  existing.forEach((element) => {
    const index = Number.parseInt(element.dataset.row, 10);
    if (index < firstVisible || index > lastVisible) {
      element.remove();
    } else {
      existingMap.set(index, element);
    }
  });

  const fragment = document.createDocumentFragment();
  for (let row = firstVisible; row <= lastVisible; row += 1) {
    if (existingMap.has(row)) continue;
    fragment.appendChild(createRowElement(row));
  }
  scrollContent.appendChild(fragment);
}

function createRowElement(rowIndex) {
  const offset = rowIndex * state.bytesPerRow;
  const end = Math.min(offset + state.bytesPerRow, state.fileSize);
  const rowBytes = state.fileData.slice(offset, end);
  const rowData = JSON.parse(callFormatHexRow(rowBytes, offset));

  const row = document.createElement('div');
  row.className = 'hex-row';
  row.dataset.row = rowIndex;
  row.style.top = `${rowIndex * state.rowHeight}px`;

  let html = `<span class="row-offset">${offset.toString(16).toUpperCase().padStart(8, '0')}</span>`;

  html += '<span class="row-hex">';
  for (let i = 0; i < 16; i += 1) {
    const byteOffset = offset + i;
    const hexValue = rowData.hex[i] || '  ';
    const byteType = rowData.types[i] || 'null';
    const isSelected = byteOffset === state.cursor;
    const gapClass = i === 7 ? ' gap-after' : '';
    const selectedClass = isSelected ? ' selected' : '';
    const isEmpty = i >= rowBytes.length ? ' style="visibility:hidden"' : '';
    html += `<span class="hex-byte byte-${byteType}${gapClass}${selectedClass}" data-offset="${byteOffset}"${isEmpty}>${hexValue}</span>`;
  }
  html += '</span>';

  html += '<span class="row-ascii">';
  for (let i = 0; i < 16; i += 1) {
    const byteOffset = offset + i;
    const character = rowData.ascii[i] || ' ';
    const isSelected = byteOffset === state.cursor;
    const selectedClass = isSelected ? ' selected' : '';
    if (i < rowBytes.length) {
      html += `<span class="ascii-byte${selectedClass}" data-offset="${byteOffset}">${escapeHtml(character)}</span>`;
    } else {
      html += '<span class="ascii-byte"> </span>';
    }
  }
  html += '</span>';

  row.innerHTML = html;
  return row;
}

function escapeHtml(text) {
  return text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

// ─── Selection & Inspector ───────────────────────────────────
function selectByte(offset) {
  if (state.activeView !== 'binary' || offset < 0 || offset >= state.fileSize) return;

  state.cursor = offset;
  updateStatusBar();
  refreshSelection();
  updateInspector();

  const row = Math.floor(offset / state.bytesPerRow);
  const rowTop = row * state.rowHeight;
  const rowBottom = rowTop + state.rowHeight;

  if (rowTop < scrollContainer.scrollTop) {
    scrollContainer.scrollTop = rowTop;
  } else if (rowBottom > scrollContainer.scrollTop + scrollContainer.clientHeight) {
    scrollContainer.scrollTop = rowBottom - scrollContainer.clientHeight;
  }
}

function clearSelection() {
  state.cursor = -1;
  updateStatusBar();
  refreshSelection();
  inspectorEl.innerHTML = '<p class="inspector-placeholder">Click a byte to inspect</p>';
}

function refreshSelection() {
  if (state.activeView !== 'binary') return;
  scrollContent.innerHTML = '';
  renderVisibleRows();
}

function updateInspector() {
  if (state.activeView !== 'binary' || state.cursor < 0 || !state.fileData) return;

  const decoded = JSON.parse(callDecodeBytes(state.fileData, state.cursor, state.littleEndian));
  const fields = [
    ['Offset', decoded.offset],
    ['Uint8', decoded.uint8],
    ['Int8', decoded.int8],
    ['Binary', decoded.binary],
    ['ASCII', decoded.ascii],
    ['Uint16', decoded.uint16],
    ['Int16', decoded.int16],
    ['Uint32', decoded.uint32],
    ['Int32', decoded.int32],
    ['Float32', decoded.float32 !== undefined ? decoded.float32.toPrecision(7) : undefined],
    ['Int64', decoded.int64],
    ['Float64', decoded.float64 !== undefined ? decoded.float64.toPrecision(15) : undefined],
  ];

  inspectorEl.innerHTML = fields
    .filter(([, value]) => value !== undefined && value !== null)
    .map(([label, value]) => (
      `<div class="inspector-row"><span class="inspector-label">${label}</span><span class="inspector-value">${value}</span></div>`
    ))
    .join('');
}

// ─── Event handlers ──────────────────────────────────────────
document.addEventListener('dragover', (event) => {
  event.preventDefault();
  dropZone.classList.add('drag-over');
});

document.addEventListener('dragleave', (event) => {
  if (!event.relatedTarget || event.relatedTarget === document.documentElement) {
    dropZone.classList.remove('drag-over');
  }
});

document.addEventListener('drop', (event) => {
  event.preventDefault();
  dropZone.classList.remove('drag-over');
  const file = event.dataTransfer?.files?.[0];
  if (file) loadFile(file);
});

$('#btn-browse').addEventListener('click', () => fileInput.click());
fileInput.addEventListener('change', () => {
  const file = fileInput.files[0];
  if (file) loadFile(file);
  fileInput.value = '';
});

scrollContainer.addEventListener('scroll', () => {
  if (state.activeView === 'binary') {
    requestAnimationFrame(renderVisibleRows);
  }
});

scrollContent.addEventListener('click', (event) => {
  const target = event.target.closest('[data-offset]');
  if (target) {
    selectByte(Number.parseInt(target.dataset.offset, 10));
  }
});

$('#btn-le').addEventListener('click', () => {
  state.littleEndian = true;
  $('#btn-le').classList.add('active');
  $('#btn-be').classList.remove('active');
  if (state.cursor >= 0) updateInspector();
});

$('#btn-be').addEventListener('click', () => {
  state.littleEndian = false;
  $('#btn-be').classList.add('active');
  $('#btn-le').classList.remove('active');
  if (state.cursor >= 0) updateInspector();
});

btnToggleInspector.addEventListener('click', () => {
  dataInspector.classList.toggle('collapsed');
  btnToggleInspector.classList.toggle('active');
});

btnViewText.addEventListener('click', () => setActiveView('text'));
btnViewBinary.addEventListener('click', () => setActiveView('binary'));
themeSelect.addEventListener('change', (event) => applyTheme(event.target.value));

document.addEventListener('keydown', (event) => {
  if (!state.fileData || state.activeView !== 'binary') return;

  const { cursor, bytesPerRow, fileSize } = state;
  if (cursor < 0 && ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(event.key)) {
    selectByte(0);
    event.preventDefault();
    return;
  }

  switch (event.key) {
    case 'ArrowRight':
      event.preventDefault();
      selectByte(Math.min(cursor + 1, fileSize - 1));
      break;
    case 'ArrowLeft':
      event.preventDefault();
      selectByte(Math.max(cursor - 1, 0));
      break;
    case 'ArrowDown':
      event.preventDefault();
      selectByte(Math.min(cursor + bytesPerRow, fileSize - 1));
      break;
    case 'ArrowUp':
      event.preventDefault();
      selectByte(Math.max(cursor - bytesPerRow, 0));
      break;
    case 'Escape':
      clearSelection();
      break;
    case 'Home':
      event.preventDefault();
      selectByte(0);
      break;
    case 'End':
      event.preventDefault();
      selectByte(fileSize - 1);
      break;
    case 'PageDown':
      event.preventDefault();
      selectByte(Math.min(cursor + bytesPerRow * 20, fileSize - 1));
      break;
    case 'PageUp':
      event.preventDefault();
      selectByte(Math.max(cursor - bytesPerRow * 20, 0));
      break;
    default:
      break;
  }
});

window.addEventListener('resize', () => {
  if (state.fileData && state.activeView === 'binary') {
    renderVisibleRows();
  }
});

// ─── Bootstrap ───────────────────────────────────────────────
applyTheme(state.theme);
initWasm().then(() => {
  console.log('[QW] WASM Viewer ready');
});
