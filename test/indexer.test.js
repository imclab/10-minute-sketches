const os = require('os');
const path = require('path');
const fs = require('fs/promises');
const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { buildIndex } = require('../src/indexer');
const { searchIndex, visualize } = require('../src/searcher');
const { systems, resolveSystem } = require('../src/systems');

let tempDir;
let indexDir;

beforeEach(async () => {
  tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'multiscan-fixture-'));
  indexDir = path.join(tempDir, 'index');
  await fs.mkdir(indexDir);
  await fs.mkdir(path.join(tempDir, 'docs'));
  await fs.writeFile(path.join(tempDir, 'docs', 'alpha.txt'), 'Alpha file\nNeural attention experiment');
  await fs.writeFile(path.join(tempDir, 'docs', 'beta.md'), 'Beta file\nKernel system metadata');
  await fs.writeFile(path.join(tempDir, 'README.md'), '# Root Readme');
});

afterEach(async () => {
  if (tempDir) {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});

for (const system of Object.values(systems)) {
  test(`indexes and searches with ${system.label}`, async () => {
    const result = await buildIndex({ rootDir: tempDir, outputDir: indexDir, system });
    assert.ok(result.filesIndexed >= 3, 'should index files');
    const matches = await searchIndex({ query: 'alpha', indexPath: indexDir, system, limit: 5 });
    assert.ok(matches.length >= 1, 'should find alpha file');
    const first = matches[0];
    assert.match(first.path, /alpha\.txt$/);
    const graph = await visualize(indexDir);
    assert.ok(Array.isArray(graph.nodes));
    assert.ok(graph.nodes.length >= 3);
  });
}

test('resolveSystem throws on unknown system', () => {
  assert.throws(() => resolveSystem('unknown-variant'));
});
