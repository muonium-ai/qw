// QW Hex Viewer — Browser UI
// Expects WASM module at ../pkg/qw_wasm.js

import init, {
  detect_file_type,
  format_hex_row,
  decode_bytes,
  get_file_info,
} from '../pkg/qw_wasm.js';

// ─── State ───────────────────────────────────────────────────
const state = {
  fileData: null,       // Uint8Array
  fileName: '',
  fileSize: 0,
  fileType: '',
  totalRows: 0,
  cursor: -1,           // selected byte offset (-1 = none)
  littleEndian: true,
  wasmReady: false,
  rowHeight: 22,        // must match CSS --row-height
  bytesPerRow: 16,
  visibleRows: [],      // currently rendered row indices
  scrollTop: 0,
};

// ─── DOM refs ────────────────────────────────────────────────
const $ = (sel) => document.querySelector(sel);
const dropZone       = $('#drop-zone');
const hexViewer      = $('#hex-viewer');
const scrollContainer = $('#hex-scroll-container');
const scrollContent  = $('#hex-scroll-content');
const hexHeader      = $('#hex-header');
const inspectorEl    = $('#inspector-content');
const aiPanelContent = $('#ai-panel-content');
const statusFileName = $('#status-file-name');
const statusFileSize = $('#status-file-size');
const statusCursor   = $('#status-cursor-offset');
const statusType     = $('#status-detected-type');
const fileTypeBadge  = $('#file-type-badge');
const fileSizeInfo   = $('#file-size-info');
const fileRowsInfo   = $('#file-rows-info');
const apiKeyModal    = $('#api-key-modal');
const apiKeyInput    = $('#api-key-input');
const fileInput      = $('#file-input');

// ─── Init WASM ───────────────────────────────────────────────
async function initWasm() {
  try {
    await init();
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
    const magic = Array.from(bytes.slice(0, 4)).map(b => b.toString(16).padStart(2, '0')).join(' ');
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
    // Check if mostly ASCII text
    let textCount = 0;
    const check = Math.min(bytes.length, 512);
    for (let i = 0; i < check; i++) {
      if ((bytes[i] >= 32 && bytes[i] < 127) || bytes[i] === 10 || bytes[i] === 13 || bytes[i] === 9) textCount++;
    }
    if (textCount / check > 0.85) return 'Text File';
    return 'Binary File';
  },

  format_hex_row(bytes, offset) {
    // Returns JSON string matching WASM interface
    const hex = [];
    const ascii = [];
    const types = [];
    for (let i = 0; i < 16; i++) {
      if (i < bytes.length) {
        const b = bytes[i];
        hex.push(b.toString(16).padStart(2, '0'));
        ascii.push((b >= 32 && b < 127) ? String.fromCharCode(b) : '.');
        if (b === 0) types.push('null');
        else if (b < 32) types.push('control');
        else if (b < 127) types.push('printable');
        else if (b === 0x09 || b === 0x0a || b === 0x0d || b === 0x20) types.push('whitespace');
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
    const result = {};
    result.offset = '0x' + offset.toString(16).padStart(8, '0');
    result.uint8 = view.getUint8(0);
    result.int8 = view.getInt8(0);
    result.binary = view.getUint8(0).toString(2).padStart(8, '0');
    result.ascii = (result.uint8 >= 32 && result.uint8 < 127) ? String.fromCharCode(result.uint8) : 'N/A';
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
      // int64 as BigInt
      const lo = view.getUint32(0, littleEndian);
      const hi = view.getInt32(4, littleEndian);
      if (littleEndian) {
        result.int64 = (BigInt(hi) << 32n) | BigInt(lo >>> 0);
      } else {
        const hiBE = view.getInt32(0, false);
        const loBE = view.getUint32(4, false);
        result.int64 = (BigInt(hiBE) << 32n) | BigInt(loBE >>> 0);
      }
      result.int64 = result.int64.toString();
    }
    return JSON.stringify(result);
  },

  get_file_info(bytes) {
    return JSON.stringify({
      size: bytes.length,
      type: fallback.detect_file_type(bytes),
      rows: Math.ceil(bytes.length / 16),
    });
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

function callDecodeBytes(bytes, offset, le) {
  if (state.wasmReady) return decode_bytes(bytes, offset, le);
  return fallback.decode_bytes(bytes, offset, le);
}

function callGetFileInfo(bytes) {
  if (state.wasmReady) return get_file_info(bytes);
  return fallback.get_file_info(bytes);
}

// ─── File loading ────────────────────────────────────────────
function loadFile(file) {
  state.fileName = file.name;
  const reader = new FileReader();
  reader.onload = (e) => {
    state.fileData = new Uint8Array(e.target.result);
    state.fileSize = state.fileData.length;
    state.totalRows = Math.ceil(state.fileSize / state.bytesPerRow);
    state.cursor = -1;

    // Detect file type
    const headerBytes = state.fileData.slice(0, Math.min(512, state.fileData.length));
    state.fileType = callDetectFileType(headerBytes);

    // Update UI
    showHexViewer();
    updateFileInfo();
    updateStatusBar();
    buildHeader();
    renderVisibleRows();

    $('#btn-ai-explain').disabled = false;
  };
  reader.readAsArrayBuffer(file);
}

function showHexViewer() {
  dropZone.classList.add('hidden');
  hexViewer.classList.remove('hidden');
  // Set scroll content total height for virtual scrolling
  scrollContent.style.height = (state.totalRows * state.rowHeight) + 'px';
}

function updateFileInfo() {
  fileTypeBadge.textContent = state.fileType;
  fileSizeInfo.textContent = formatSize(state.fileSize);
  fileRowsInfo.textContent = state.totalRows.toLocaleString() + ' rows';
}

function updateStatusBar() {
  statusFileName.textContent = state.fileName;
  statusFileSize.textContent = formatSize(state.fileSize);
  statusType.textContent = state.fileType;
  if (state.cursor >= 0) {
    statusCursor.textContent = 'Offset: 0x' + state.cursor.toString(16).toUpperCase().padStart(8, '0');
  } else {
    statusCursor.textContent = '';
  }
}

function formatSize(bytes) {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
  if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
}

// ─── Column header ───────────────────────────────────────────
function buildHeader() {
  let html = '<span class="header-offset">Offset</span><span class="header-hex">';
  for (let i = 0; i < 16; i++) {
    const gap = (i === 8) ? ' style="margin-left:8px"' : '';
    html += `<span style="display:inline-block;width:24px;text-align:center"${gap}>${i.toString(16).toUpperCase()}</span>`;
  }
  html += '</span><span class="header-ascii">ASCII</span>';
  hexHeader.innerHTML = html;
}

// ─── Virtual scroll rendering ────────────────────────────────
function renderVisibleRows() {
  if (!state.fileData) return;

  const containerHeight = scrollContainer.clientHeight;
  const scrollTop = scrollContainer.scrollTop;
  const overscan = 5;

  const firstVisible = Math.max(0, Math.floor(scrollTop / state.rowHeight) - overscan);
  const lastVisible = Math.min(
    state.totalRows - 1,
    Math.ceil((scrollTop + containerHeight) / state.rowHeight) + overscan
  );

  // Remove rows outside visible range
  const existing = scrollContent.querySelectorAll('.hex-row');
  const existingMap = new Map();
  existing.forEach(el => {
    const idx = parseInt(el.dataset.row, 10);
    if (idx < firstVisible || idx > lastVisible) {
      el.remove();
    } else {
      existingMap.set(idx, el);
    }
  });

  // Add missing rows
  const fragment = document.createDocumentFragment();
  for (let row = firstVisible; row <= lastVisible; row++) {
    if (existingMap.has(row)) continue;
    const el = createRowElement(row);
    fragment.appendChild(el);
  }
  scrollContent.appendChild(fragment);
}

function createRowElement(rowIndex) {
  const offset = rowIndex * state.bytesPerRow;
  const end = Math.min(offset + state.bytesPerRow, state.fileSize);
  const rowBytes = state.fileData.slice(offset, end);

  // Call WASM/fallback
  const rowData = JSON.parse(callFormatHexRow(rowBytes, offset));

  const div = document.createElement('div');
  div.className = 'hex-row';
  div.dataset.row = rowIndex;
  div.style.top = (rowIndex * state.rowHeight) + 'px';

  // Offset column
  let html = `<span class="row-offset">${offset.toString(16).toUpperCase().padStart(8, '0')}</span>`;

  // Hex bytes
  html += '<span class="row-hex">';
  for (let i = 0; i < 16; i++) {
    const byteOffset = offset + i;
    const hexVal = rowData.hex[i] || '  ';
    const byteType = rowData.types[i] || 'null';
    const isSelected = byteOffset === state.cursor;
    const gapClass = (i === 7) ? ' gap-after' : '';
    const selClass = isSelected ? ' selected' : '';
    const isEmpty = (i >= rowBytes.length) ? ' style="visibility:hidden"' : '';
    html += `<span class="hex-byte byte-${byteType}${gapClass}${selClass}" data-offset="${byteOffset}"${isEmpty}>${hexVal}</span>`;
  }
  html += '</span>';

  // ASCII column
  html += '<span class="row-ascii">';
  for (let i = 0; i < 16; i++) {
    const byteOffset = offset + i;
    const ch = rowData.ascii[i] || ' ';
    const isSelected = byteOffset === state.cursor;
    const selClass = isSelected ? ' selected' : '';
    if (i < rowBytes.length) {
      html += `<span class="ascii-byte${selClass}" data-offset="${byteOffset}">${escapeHtml(ch)}</span>`;
    } else {
      html += '<span class="ascii-byte"> </span>';
    }
  }
  html += '</span>';

  div.innerHTML = html;
  return div;
}

function escapeHtml(ch) {
  if (ch === '<') return '&lt;';
  if (ch === '>') return '&gt;';
  if (ch === '&') return '&amp;';
  if (ch === '"') return '&quot;';
  return ch;
}

// ─── Selection & Inspector ───────────────────────────────────
function selectByte(offset) {
  if (offset < 0 || offset >= state.fileSize) return;
  state.cursor = offset;
  updateStatusBar();
  refreshSelection();
  updateInspector();

  // Ensure cursor row is visible
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
  // Re-render all visible rows to update selection state
  scrollContent.innerHTML = '';
  renderVisibleRows();
}

function updateInspector() {
  if (state.cursor < 0 || !state.fileData) return;

  const decoded = JSON.parse(callDecodeBytes(state.fileData, state.cursor, state.littleEndian));
  let html = '';

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

  for (const [label, value] of fields) {
    if (value === undefined || value === null) continue;
    html += `<div class="inspector-row"><span class="inspector-label">${label}</span><span class="inspector-value">${value}</span></div>`;
  }

  inspectorEl.innerHTML = html;
}

// ─── AI Explain ──────────────────────────────────────────────
function showApiKeyModal() {
  const savedKey = localStorage.getItem('qw_claude_api_key') || '';
  apiKeyInput.value = savedKey;
  apiKeyModal.classList.remove('hidden');
  apiKeyInput.focus();
}

function hideApiKeyModal() {
  apiKeyModal.classList.add('hidden');
}

async function aiExplain(apiKey) {
  if (!state.fileData) return;

  // Store key
  localStorage.setItem('qw_claude_api_key', apiKey);

  // Open AI panel
  $('#ai-panel').classList.remove('collapsed');
  $('#btn-toggle-ai-panel').classList.add('active');

  // Build hex string of first 256 bytes
  const sample = state.fileData.slice(0, Math.min(256, state.fileData.length));
  let hexStr = '';
  for (let i = 0; i < sample.length; i++) {
    hexStr += sample[i].toString(16).padStart(2, '0');
    if ((i + 1) % 16 === 0) hexStr += '\n';
    else hexStr += ' ';
  }

  aiPanelContent.innerHTML = '<span class="ai-loading">Analyzing file...</span>';

  try {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-dangerous-direct-browser-access': 'true',
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024,
        stream: true,
        system: 'You are a binary file analyst. Explain the structure of this file based on its hex bytes and detected type. Be concise.',
        messages: [{
          role: 'user',
          content: `File: ${state.fileName}\nDetected type: ${state.fileType}\nSize: ${formatSize(state.fileSize)}\n\nFirst ${sample.length} bytes (hex):\n${hexStr}\n\nExplain the structure of this file.`,
        }],
      }),
    });

    if (!response.ok) {
      const errBody = await response.text();
      aiPanelContent.textContent = `API Error ${response.status}: ${errBody}`;
      return;
    }

    // Stream response
    aiPanelContent.textContent = '';
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      // Parse SSE events
      const lines = buffer.split('\n');
      buffer = lines.pop(); // keep incomplete line

      for (const line of lines) {
        if (line.startsWith('data: ')) {
          const data = line.slice(6).trim();
          if (data === '[DONE]') continue;
          try {
            const event = JSON.parse(data);
            if (event.type === 'content_block_delta' && event.delta?.text) {
              aiPanelContent.textContent += event.delta.text;
              aiPanelContent.scrollTop = aiPanelContent.scrollHeight;
            }
          } catch {
            // skip unparseable lines
          }
        }
      }
    }
  } catch (err) {
    aiPanelContent.textContent = 'Error: ' + err.message;
  }
}

// ─── Event handlers ──────────────────────────────────────────

// Drag & drop
document.addEventListener('dragover', (e) => {
  e.preventDefault();
  dropZone.classList.add('drag-over');
});

document.addEventListener('dragleave', (e) => {
  if (!e.relatedTarget || e.relatedTarget === document.documentElement) {
    dropZone.classList.remove('drag-over');
  }
});

document.addEventListener('drop', (e) => {
  e.preventDefault();
  dropZone.classList.remove('drag-over');
  const file = e.dataTransfer?.files?.[0];
  if (file) loadFile(file);
});

// Browse button
$('#btn-browse').addEventListener('click', () => fileInput.click());
fileInput.addEventListener('change', () => {
  const file = fileInput.files[0];
  if (file) loadFile(file);
});

// Virtual scroll
scrollContainer.addEventListener('scroll', () => {
  requestAnimationFrame(renderVisibleRows);
});

// Click on hex byte
scrollContent.addEventListener('click', (e) => {
  const target = e.target.closest('[data-offset]');
  if (target) {
    const offset = parseInt(target.dataset.offset, 10);
    selectByte(offset);
  }
});

// Endianness toggle
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

// Panel toggles
$('#btn-toggle-inspector').addEventListener('click', () => {
  const panel = $('#data-inspector');
  panel.classList.toggle('collapsed');
  $('#btn-toggle-inspector').classList.toggle('active');
});

$('#btn-toggle-ai-panel').addEventListener('click', () => {
  const panel = $('#ai-panel');
  panel.classList.toggle('collapsed');
  $('#btn-toggle-ai-panel').classList.toggle('active');
});

$('#btn-close-ai-panel').addEventListener('click', () => {
  $('#ai-panel').classList.add('collapsed');
  $('#btn-toggle-ai-panel').classList.remove('active');
});

// AI explain
$('#btn-ai-explain').addEventListener('click', () => {
  const key = localStorage.getItem('qw_claude_api_key');
  if (key) {
    aiExplain(key);
  } else {
    showApiKeyModal();
  }
});

$('#btn-save-api-key').addEventListener('click', () => {
  const key = apiKeyInput.value.trim();
  if (key) {
    hideApiKeyModal();
    aiExplain(key);
  }
});

$('#btn-cancel-api-key').addEventListener('click', hideApiKeyModal);

$('.modal-backdrop')?.addEventListener('click', hideApiKeyModal);

// Keyboard navigation
document.addEventListener('keydown', (e) => {
  if (!state.fileData) return;
  if (apiKeyModal && !apiKeyModal.classList.contains('hidden')) return;

  const { cursor, bytesPerRow, fileSize } = state;
  if (cursor < 0 && ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key)) {
    selectByte(0);
    e.preventDefault();
    return;
  }

  switch (e.key) {
    case 'ArrowRight':
      e.preventDefault();
      selectByte(Math.min(cursor + 1, fileSize - 1));
      break;
    case 'ArrowLeft':
      e.preventDefault();
      selectByte(Math.max(cursor - 1, 0));
      break;
    case 'ArrowDown':
      e.preventDefault();
      selectByte(Math.min(cursor + bytesPerRow, fileSize - 1));
      break;
    case 'ArrowUp':
      e.preventDefault();
      selectByte(Math.max(cursor - bytesPerRow, 0));
      break;
    case 'Escape':
      clearSelection();
      break;
    case 'Home':
      e.preventDefault();
      selectByte(0);
      break;
    case 'End':
      e.preventDefault();
      selectByte(fileSize - 1);
      break;
    case 'PageDown':
      e.preventDefault();
      selectByte(Math.min(cursor + bytesPerRow * 20, fileSize - 1));
      break;
    case 'PageUp':
      e.preventDefault();
      selectByte(Math.max(cursor - bytesPerRow * 20, 0));
      break;
  }
});

// Window resize
window.addEventListener('resize', () => {
  if (state.fileData) renderVisibleRows();
});

// ─── Bootstrap ───────────────────────────────────────────────
initWasm().then(() => {
  console.log('[QW] Hex Viewer ready');
});
