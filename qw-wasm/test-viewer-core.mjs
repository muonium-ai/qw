import assert from 'node:assert/strict';
import { TextEncoder } from 'node:util';

import {
  DEFAULT_THEME,
  THEMES,
  analyzeFile,
  coerceTheme,
  renderTextDocument,
} from './www/viewer-core.mjs';

const encoder = new TextEncoder();

function testTextAnalysis() {
  const swiftSource = [
    'import Foundation',
    'struct Greeter {',
    '  let name = "QW"',
    '  func greet() -> String {',
    '    return "Hello, \\(name)"',
    '  }',
    '}',
    '',
  ].join('\n');

  const bytes = encoder.encode(swiftSource);
  const analysis = analyzeFile('Greeter.swift', bytes, '{"name":"Text File"}');

  assert.equal(analysis.canShowText, true);
  assert.equal(analysis.preferredView, 'text');
  assert.equal(analysis.language, 'swift');
  assert.equal(analysis.canHighlight, true);
  assert.equal(analysis.lineCount, swiftSource.split('\n').length);

  const html = renderTextDocument(analysis.text, analysis.language, {
    highlight: analysis.canHighlight,
  });
  assert.match(html, /token-keyword/);
  assert.match(html, /token-string/);
  assert.match(html, /text-line-number/);
}

function testBinaryAnalysis() {
  const pngBytes = new Uint8Array([
    0x89, 0x50, 0x4E, 0x47,
    0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D,
  ]);

  const analysis = analyzeFile('image.bin', pngBytes, '{"name":"PNG Image"}');

  assert.equal(analysis.canShowText, false);
  assert.equal(analysis.preferredView, 'binary');
  assert.equal(analysis.availableViews.binary, true);
  assert.equal(analysis.binaryLabel, 'PNG Image');
}

function testThemes() {
  assert.deepEqual(
    THEMES.map((theme) => theme.id),
    ['mocha', 'light', 'solarized-dark', 'dracula'],
  );
  assert.equal(coerceTheme('dracula'), 'dracula');
  assert.equal(coerceTheme('unknown-theme'), DEFAULT_THEME);
}

testTextAnalysis();
testBinaryAnalysis();
testThemes();

console.log('viewer-core smoke tests passed');
