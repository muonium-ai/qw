const TEXT_DECODER = new TextDecoder('utf-8', { fatal: true });

export const DEFAULT_THEME = 'mocha';
export const HIGHLIGHT_CHAR_LIMIT = 250_000;

export const THEMES = [
  { id: 'mocha', label: 'Mocha' },
  { id: 'light', label: 'Light' },
  { id: 'solarized-dark', label: 'Solarized Dark' },
  { id: 'dracula', label: 'Dracula' },
];

const EXTENSION_LANGUAGE_MAP = {
  txt: 'plain',
  text: 'plain',
  log: 'plain',
  cfg: 'plain',
  conf: 'plain',
  ini: 'plain',
  md: 'markdown',
  markdown: 'markdown',
  json: 'json',
  yaml: 'yaml',
  yml: 'yaml',
  py: 'python',
  pyw: 'python',
  js: 'javascript',
  mjs: 'javascript',
  cjs: 'javascript',
  jsx: 'javascript',
  ts: 'javascript',
  tsx: 'javascript',
  html: 'html',
  htm: 'html',
  xml: 'html',
  svg: 'html',
  css: 'css',
  swift: 'swift',
};

const LANGUAGE_LABELS = {
  plain: 'Plain',
  markdown: 'Markdown',
  json: 'JSON',
  yaml: 'YAML',
  python: 'Python',
  javascript: 'JavaScript',
  html: 'HTML',
  css: 'CSS',
  swift: 'Swift',
};

const KEYWORDS = {
  javascript: new Set([
    'break', 'case', 'catch', 'class', 'const', 'continue', 'default', 'delete',
    'do', 'else', 'export', 'extends', 'finally', 'for', 'function', 'if',
    'import', 'in', 'instanceof', 'let', 'new', 'return', 'super', 'switch',
    'this', 'throw', 'try', 'typeof', 'var', 'void', 'while', 'yield', 'await',
  ]),
  python: new Set([
    'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue', 'def',
    'del', 'elif', 'else', 'except', 'False', 'finally', 'for', 'from', 'global',
    'if', 'import', 'in', 'is', 'lambda', 'None', 'nonlocal', 'not', 'or',
    'pass', 'raise', 'return', 'True', 'try', 'while', 'with', 'yield',
  ]),
  swift: new Set([
    'actor', 'as', 'associatedtype', 'async', 'await', 'break', 'case', 'catch',
    'class', 'continue', 'default', 'defer', 'do', 'else', 'enum', 'extension',
    'fallthrough', 'for', 'func', 'guard', 'if', 'import', 'in', 'init', 'inout',
    'let', 'mutating', 'nonmutating', 'protocol', 'repeat', 'return', 'struct',
    'subscript', 'switch', 'throw', 'throws', 'try', 'typealias', 'var', 'where',
    'while',
  ]),
  css: new Set([
    '@media', '@supports', '@layer', '@font-face', '@keyframes', '@import',
    '@charset', '@container',
  ]),
};

const TYPES = {
  javascript: new Set(['Array', 'Boolean', 'Date', 'JSON', 'Map', 'Number', 'Object', 'Promise', 'Set', 'String']),
  python: new Set(['dict', 'float', 'int', 'list', 'set', 'str', 'tuple']),
  swift: new Set(['Bool', 'Data', 'Date', 'Double', 'Float', 'Int', 'String', 'URL', 'UUID']),
};

const CONSTANTS = new Set(['true', 'false', 'null', 'nil', 'True', 'False', 'None']);
const FUNCTION_NAME = /^[A-Za-z_][A-Za-z0-9_]*(?=\s*\()/;
const IDENTIFIER = /^[A-Za-z_][A-Za-z0-9_]*/;
const NUMBER_PATTERN = /^(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/;
const OPERATOR_PATTERN = /^(?:===|!==|==|!=|<=|>=|=>|->|\.\.\.|&&|\|\||[+\-*/%=&|<>!?]+)/;
const PUNCTUATION_PATTERN = /^[()[\]{}.,:;]/;

export function coerceTheme(themeName) {
  if (THEMES.some((theme) => theme.id === themeName)) {
    return themeName;
  }
  return DEFAULT_THEME;
}

export function normalizeDetectedType(raw) {
  if (!raw) {
    return { name: 'Unknown', description: '' };
  }

  if (typeof raw === 'object' && raw.name) {
    return raw;
  }

  const text = String(raw).trim();
  if (!text || text === '{}' || text === 'Unknown') {
    return { name: 'Unknown', description: '' };
  }

  if (text.startsWith('{')) {
    try {
      const parsed = JSON.parse(text);
      if (parsed && parsed.name) {
        return parsed;
      }
    } catch {
      // Fall through to plain string handling.
    }
  }

  return { name: text, description: '' };
}

export function detectLanguageFromFileName(fileName = '', detectedType = { name: 'Unknown' }) {
  const extension = getExtension(fileName);
  if (extension && EXTENSION_LANGUAGE_MAP[extension]) {
    return EXTENSION_LANGUAGE_MAP[extension];
  }

  const detectedName = (detectedType?.name || '').toLowerCase();
  if (detectedName.includes('json')) return 'json';
  if (detectedName.includes('xml') || detectedName.includes('html')) return 'html';
  if (detectedName.includes('yaml')) return 'yaml';
  if (detectedName.includes('text')) return 'plain';

  return 'plain';
}

export function languageLabel(language) {
  return LANGUAGE_LABELS[language] || 'Plain';
}

export function analyzeFile(fileName, bytes, detectedTypeRaw) {
  const detectedType = normalizeDetectedType(detectedTypeRaw);
  const language = detectLanguageFromFileName(fileName, detectedType);
  const decodedText = decodeUtf8(bytes);

  let canShowText = false;
  let text = '';

  if (decodedText !== null) {
    const likelyTextByExtension = language !== 'plain' || isKnownTextExtension(fileName);
    const likelyTextByContent = !looksBinary(bytes);
    const likelyTextByType = ['json document', 'xml document'].includes(detectedType.name.toLowerCase())
      || detectedType.name.toLowerCase().includes('text');

    canShowText = likelyTextByExtension || likelyTextByContent || likelyTextByType;
    if (canShowText) {
      text = decodedText.replace(/\r\n?/g, '\n');
    }
  }

  const canHighlight = canShowText && language !== 'plain' && text.length <= HIGHLIGHT_CHAR_LIMIT;
  const lineCount = canShowText ? text.split('\n').length : 0;

  let note = '';
  if (canShowText && language === 'plain') {
    note = 'Showing plain text because no syntax rules are defined for this file type.';
  } else if (canShowText && text.length > HIGHLIGHT_CHAR_LIMIT) {
    note = 'Showing plain text because syntax highlighting is disabled for very large text files.';
  }

  return {
    detectedType,
    language,
    languageLabel: languageLabel(language),
    canShowText,
    canHighlight,
    textMode: canHighlight ? 'highlighted' : 'plain',
    text,
    lineCount,
    note,
    availableViews: {
      text: canShowText,
      binary: true,
    },
    preferredView: canShowText ? 'text' : 'binary',
    binaryLabel: detectedType.name !== 'Unknown' ? detectedType.name : 'Binary File',
    textLabel: `${languageLabel(language)} Text`,
  };
}

export function renderTextDocument(text, language, { highlight = true } = {}) {
  const lines = text.split('\n');
  const state = createTokenizerState(language);

  return lines.map((line, index) => {
    const lineHtml = highlight ? renderHighlightedLine(line, language, state) : escapeHtml(line);
    return [
      '<div class="text-line">',
      `<span class="text-line-number">${index + 1}</span>`,
      `<span class="text-line-content">${lineHtml || '&nbsp;'}</span>`,
      '</div>',
    ].join('');
  }).join('');
}

function getExtension(fileName) {
  const parts = fileName.toLowerCase().split('.');
  return parts.length > 1 ? parts.pop() : '';
}

function isKnownTextExtension(fileName) {
  const extension = getExtension(fileName);
  return Boolean(extension && EXTENSION_LANGUAGE_MAP[extension]);
}

function decodeUtf8(bytes) {
  try {
    return TEXT_DECODER.decode(bytes);
  } catch {
    return null;
  }
}

function looksBinary(bytes) {
  const sample = bytes.subarray(0, Math.min(bytes.length, 4096));
  if (!sample.length) return false;

  let controlCount = 0;
  let printableCount = 0;

  for (const value of sample) {
    if (value === 0x00) {
      return true;
    }

    const isWhitespace = value === 0x09 || value === 0x0A || value === 0x0D;
    const isPrintable = value >= 0x20 && value <= 0x7E;
    if (isWhitespace || isPrintable) {
      printableCount += 1;
    } else if (value < 0x20 || value === 0x7F) {
      controlCount += 1;
    }
  }

  const controlRatio = controlCount / sample.length;
  const printableRatio = printableCount / sample.length;
  return controlRatio > 0.1 && printableRatio < 0.85;
}

function createTokenizerState(language) {
  return {
    inBlockComment: false,
    inHtmlComment: false,
    inMarkdownFence: false,
    markdownFence: null,
    language,
  };
}

function renderHighlightedLine(line, language, state) {
  switch (language) {
    case 'json':
      return renderTokens(tokenizeJsonLine(line));
    case 'yaml':
      return renderTokens(tokenizeYamlLine(line));
    case 'html':
      return renderTokens(tokenizeHtmlLine(line, state));
    case 'markdown':
      return renderTokens(tokenizeMarkdownLine(line, state));
    case 'javascript':
      return renderTokens(tokenizeCodeLine(line, state, {
        lineComment: /^\/\/.*/,
        blockCommentStart: '/*',
        blockCommentEnd: '*/',
        keywords: KEYWORDS.javascript,
        types: TYPES.javascript,
        allowBackticks: true,
      }));
    case 'python':
      return renderTokens(tokenizeCodeLine(line, state, {
        lineComment: /^#.*/,
        keywords: KEYWORDS.python,
        types: TYPES.python,
        allowBackticks: false,
        decorators: true,
      }));
    case 'swift':
      return renderTokens(tokenizeCodeLine(line, state, {
        lineComment: /^\/\/.*/,
        blockCommentStart: '/*',
        blockCommentEnd: '*/',
        keywords: KEYWORDS.swift,
        types: TYPES.swift,
        allowBackticks: false,
      }));
    case 'css':
      return renderTokens(tokenizeCodeLine(line, state, {
        blockCommentStart: '/*',
        blockCommentEnd: '*/',
        keywords: KEYWORDS.css,
        types: new Set(),
        allowBackticks: false,
      }));
    default:
      return escapeHtml(line);
  }
}

function renderTokens(tokens) {
  return tokens.map((token) => {
    const text = escapeHtml(token.text);
    if (!text) return '';
    if (!token.type || token.type === 'plain') {
      return text;
    }
    return `<span class="token-${token.type}">${text}</span>`;
  }).join('');
}

function tokenizeCodeLine(line, state, config) {
  const tokens = [];
  let remaining = line;

  while (remaining.length > 0) {
    if (state.inBlockComment) {
      const endIndex = remaining.indexOf(config.blockCommentEnd);
      if (endIndex === -1) {
        tokens.push({ type: 'comment', text: remaining });
        return tokens;
      }
      tokens.push({ type: 'comment', text: remaining.slice(0, endIndex + config.blockCommentEnd.length) });
      remaining = remaining.slice(endIndex + config.blockCommentEnd.length);
      state.inBlockComment = false;
      continue;
    }

    const whitespace = remaining.match(/^\s+/);
    if (whitespace) {
      tokens.push({ type: 'plain', text: whitespace[0] });
      remaining = remaining.slice(whitespace[0].length);
      continue;
    }

    if (config.lineComment) {
      const comment = remaining.match(config.lineComment);
      if (comment) {
        tokens.push({ type: 'comment', text: comment[0] });
        return tokens;
      }
    }

    if (config.blockCommentStart && remaining.startsWith(config.blockCommentStart)) {
      const endIndex = remaining.indexOf(config.blockCommentEnd, config.blockCommentStart.length);
      if (endIndex === -1) {
        tokens.push({ type: 'comment', text: remaining });
        state.inBlockComment = true;
        return tokens;
      }
      tokens.push({ type: 'comment', text: remaining.slice(0, endIndex + config.blockCommentEnd.length) });
      remaining = remaining.slice(endIndex + config.blockCommentEnd.length);
      continue;
    }

    if (config.decorators) {
      const decorator = remaining.match(/^@[A-Za-z_][A-Za-z0-9_.]*/);
      if (decorator) {
        tokens.push({ type: 'attribute', text: decorator[0] });
        remaining = remaining.slice(decorator[0].length);
        continue;
      }
    }

    const stringToken = matchString(remaining, config.allowBackticks);
    if (stringToken) {
      tokens.push({ type: 'string', text: stringToken });
      remaining = remaining.slice(stringToken.length);
      continue;
    }

    const numberToken = remaining.match(NUMBER_PATTERN);
    if (numberToken) {
      tokens.push({ type: 'number', text: numberToken[0] });
      remaining = remaining.slice(numberToken[0].length);
      continue;
    }

    const word = remaining.match(IDENTIFIER);
    if (word) {
      const value = word[0];
      const nextChunk = remaining.slice(value.length);
      if (CONSTANTS.has(value)) {
        tokens.push({ type: 'number', text: value });
      } else if (config.keywords.has(value)) {
        tokens.push({ type: 'keyword', text: value });
      } else if (config.types.has(value)) {
        tokens.push({ type: 'type', text: value });
      } else if (/^\s*\(/.test(nextChunk)) {
        tokens.push({ type: 'function', text: value });
      } else {
        tokens.push({ type: 'plain', text: value });
      }
      remaining = remaining.slice(value.length);
      continue;
    }

    const operator = remaining.match(OPERATOR_PATTERN);
    if (operator) {
      tokens.push({ type: 'punctuation', text: operator[0] });
      remaining = remaining.slice(operator[0].length);
      continue;
    }

    const punctuation = remaining.match(PUNCTUATION_PATTERN);
    if (punctuation) {
      tokens.push({ type: 'punctuation', text: punctuation[0] });
      remaining = remaining.slice(punctuation[0].length);
      continue;
    }

    tokens.push({ type: 'plain', text: remaining[0] });
    remaining = remaining.slice(1);
  }

  return tokens;
}

function tokenizeJsonLine(line) {
  const tokens = [];
  let remaining = line;

  while (remaining.length > 0) {
    const whitespace = remaining.match(/^\s+/);
    if (whitespace) {
      tokens.push({ type: 'plain', text: whitespace[0] });
      remaining = remaining.slice(whitespace[0].length);
      continue;
    }

    const property = remaining.match(/^"(?:\\.|[^"\\])*"(?=\s*:)/);
    if (property) {
      tokens.push({ type: 'property', text: property[0] });
      remaining = remaining.slice(property[0].length);
      continue;
    }

    const stringToken = matchString(remaining, false);
    if (stringToken) {
      tokens.push({ type: 'string', text: stringToken });
      remaining = remaining.slice(stringToken.length);
      continue;
    }

    const numberToken = remaining.match(NUMBER_PATTERN);
    if (numberToken) {
      tokens.push({ type: 'number', text: numberToken[0] });
      remaining = remaining.slice(numberToken[0].length);
      continue;
    }

    const constant = remaining.match(/^(?:true|false|null)\b/);
    if (constant) {
      tokens.push({ type: 'keyword', text: constant[0] });
      remaining = remaining.slice(constant[0].length);
      continue;
    }

    const punctuation = remaining.match(/^[{}\[\],:]/);
    if (punctuation) {
      tokens.push({ type: 'punctuation', text: punctuation[0] });
      remaining = remaining.slice(punctuation[0].length);
      continue;
    }

    tokens.push({ type: 'plain', text: remaining[0] });
    remaining = remaining.slice(1);
  }

  return tokens;
}

function tokenizeYamlLine(line) {
  const tokens = [];
  let remaining = line;
  let sawMeaningfulToken = false;

  while (remaining.length > 0) {
    const whitespace = remaining.match(/^\s+/);
    if (whitespace) {
      tokens.push({ type: 'plain', text: whitespace[0] });
      remaining = remaining.slice(whitespace[0].length);
      continue;
    }

    if (remaining.startsWith('#')) {
      tokens.push({ type: 'comment', text: remaining });
      return tokens;
    }

    if (!sawMeaningfulToken) {
      const listMarker = remaining.match(/^-\s+/);
      if (listMarker) {
        tokens.push({ type: 'punctuation', text: listMarker[0] });
        remaining = remaining.slice(listMarker[0].length);
        sawMeaningfulToken = true;
        continue;
      }
    }

    const property = remaining.match(/^[A-Za-z0-9_.-]+(?=\s*:)/);
    if (property) {
      tokens.push({ type: 'property', text: property[0] });
      remaining = remaining.slice(property[0].length);
      sawMeaningfulToken = true;
      continue;
    }

    const stringToken = matchString(remaining, false);
    if (stringToken) {
      tokens.push({ type: 'string', text: stringToken });
      remaining = remaining.slice(stringToken.length);
      sawMeaningfulToken = true;
      continue;
    }

    const constant = remaining.match(/^(?:true|false|null|yes|no|on|off)\b/i);
    if (constant) {
      tokens.push({ type: 'keyword', text: constant[0] });
      remaining = remaining.slice(constant[0].length);
      sawMeaningfulToken = true;
      continue;
    }

    const numberToken = remaining.match(NUMBER_PATTERN);
    if (numberToken) {
      tokens.push({ type: 'number', text: numberToken[0] });
      remaining = remaining.slice(numberToken[0].length);
      sawMeaningfulToken = true;
      continue;
    }

    const punctuation = remaining.match(/^[:[\]{}|>,]/);
    if (punctuation) {
      tokens.push({ type: 'punctuation', text: punctuation[0] });
      remaining = remaining.slice(punctuation[0].length);
      sawMeaningfulToken = true;
      continue;
    }

    tokens.push({ type: 'plain', text: remaining[0] });
    remaining = remaining.slice(1);
    sawMeaningfulToken = true;
  }

  return tokens;
}

function tokenizeHtmlLine(line, state) {
  const tokens = [];
  let remaining = line;

  while (remaining.length > 0) {
    if (state.inHtmlComment) {
      const endIndex = remaining.indexOf('-->');
      if (endIndex === -1) {
        tokens.push({ type: 'comment', text: remaining });
        return tokens;
      }
      tokens.push({ type: 'comment', text: remaining.slice(0, endIndex + 3) });
      remaining = remaining.slice(endIndex + 3);
      state.inHtmlComment = false;
      continue;
    }

    const whitespace = remaining.match(/^\s+/);
    if (whitespace) {
      tokens.push({ type: 'plain', text: whitespace[0] });
      remaining = remaining.slice(whitespace[0].length);
      continue;
    }

    if (remaining.startsWith('<!--')) {
      const endIndex = remaining.indexOf('-->', 4);
      if (endIndex === -1) {
        tokens.push({ type: 'comment', text: remaining });
        state.inHtmlComment = true;
        return tokens;
      }
      tokens.push({ type: 'comment', text: remaining.slice(0, endIndex + 3) });
      remaining = remaining.slice(endIndex + 3);
      continue;
    }

    const tag = remaining.match(/^<\/?[A-Za-z][A-Za-z0-9:-]*/);
    if (tag) {
      tokens.push({ type: 'tag', text: tag[0] });
      remaining = remaining.slice(tag[0].length);
      continue;
    }

    const tagEnd = remaining.match(/^\/?>/);
    if (tagEnd) {
      tokens.push({ type: 'punctuation', text: tagEnd[0] });
      remaining = remaining.slice(tagEnd[0].length);
      continue;
    }

    const attribute = remaining.match(/^[A-Za-z_:][A-Za-z0-9:._-]*(?=\=)/);
    if (attribute) {
      tokens.push({ type: 'attribute', text: attribute[0] });
      remaining = remaining.slice(attribute[0].length);
      continue;
    }

    const stringToken = matchString(remaining, false);
    if (stringToken) {
      tokens.push({ type: 'string', text: stringToken });
      remaining = remaining.slice(stringToken.length);
      continue;
    }

    const entity = remaining.match(/^&[A-Za-z0-9#]+;/);
    if (entity) {
      tokens.push({ type: 'number', text: entity[0] });
      remaining = remaining.slice(entity[0].length);
      continue;
    }

    const textChunk = remaining.match(/^[^<>&"'=\s]+/);
    if (textChunk) {
      tokens.push({ type: 'plain', text: textChunk[0] });
      remaining = remaining.slice(textChunk[0].length);
      continue;
    }

    tokens.push({ type: 'plain', text: remaining[0] });
    remaining = remaining.slice(1);
  }

  return tokens;
}

function tokenizeMarkdownLine(line, state) {
  const trimmed = line.trimStart();

  if (state.inMarkdownFence) {
    if (trimmed.startsWith(state.markdownFence)) {
      state.inMarkdownFence = false;
      state.markdownFence = null;
    }
    return [{ type: 'code-block', text: line }];
  }

  const fence = trimmed.match(/^(```|~~~)/);
  if (fence) {
    state.inMarkdownFence = true;
    state.markdownFence = fence[1];
    return [{ type: 'code-block', text: line }];
  }

  if (/^\s*#{1,6}\s+/.test(line)) {
    return [{ type: 'heading', text: line }];
  }

  if (/^\s*>\s?/.test(line)) {
    return [{ type: 'comment', text: line }];
  }

  const listMatch = line.match(/^(\s*(?:[-*+]|\d+\.)\s+)/);
  const tokens = [];
  let remaining = line;

  if (listMatch) {
    tokens.push({ type: 'punctuation', text: listMatch[1] });
    remaining = line.slice(listMatch[1].length);
  }

  while (remaining.length > 0) {
    const whitespace = remaining.match(/^\s+/);
    if (whitespace) {
      tokens.push({ type: 'plain', text: whitespace[0] });
      remaining = remaining.slice(whitespace[0].length);
      continue;
    }

    const inlineCode = remaining.match(/^`[^`]+`/);
    if (inlineCode) {
      tokens.push({ type: 'code-block', text: inlineCode[0] });
      remaining = remaining.slice(inlineCode[0].length);
      continue;
    }

    const link = remaining.match(/^\[[^\]]+\]\([^)]+\)/);
    if (link) {
      tokens.push({ type: 'link', text: link[0] });
      remaining = remaining.slice(link[0].length);
      continue;
    }

    const emphasis = remaining.match(/^(?:\*\*[^*]+\*\*|\*[^*]+\*|_[^_]+_)/);
    if (emphasis) {
      tokens.push({ type: 'emphasis', text: emphasis[0] });
      remaining = remaining.slice(emphasis[0].length);
      continue;
    }

    const textChunk = remaining.match(/^[^`[*_]+/);
    if (textChunk) {
      tokens.push({ type: 'plain', text: textChunk[0] });
      remaining = remaining.slice(textChunk[0].length);
      continue;
    }

    tokens.push({ type: 'plain', text: remaining[0] });
    remaining = remaining.slice(1);
  }

  return tokens;
}

function matchString(source, allowBackticks) {
  const patterns = [
    /^"(?:\\.|[^"\\])*"/,
    /^'(?:\\.|[^'\\])*'/,
  ];

  if (allowBackticks) {
    patterns.push(/^`(?:\\.|[^`\\])*`/);
  }

  for (const pattern of patterns) {
    const match = source.match(pattern);
    if (match) {
      return match[0];
    }
  }

  return null;
}

function escapeHtml(text) {
  return text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}
