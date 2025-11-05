const path = require('path');

const systems = {
  kernel: {
    id: 'kernel',
    label: 'KernelScan',
    documentConfig: {
      tokenize: 'forward',
      cache: true,
      document: {
        id: 'id',
        index: ['name', 'pathTokens', 'contentSample'],
        store: ['path', 'name', 'size', 'mtimeMs', 'ext', 'tags', 'parent']
      }
    },
    maxSampleBytes: 16384,
    description: 'Deterministic inode-first traversal with aggressive caching.',
    concurrency: 32
  },
  graph: {
    id: 'graph',
    label: 'GraphPulse',
    documentConfig: {
      tokenize: 'full',
      resolution: 9,
      document: {
        id: 'id',
        index: ['name', 'pathTokens', 'contentSample', 'tagString'],
        store: ['path', 'name', 'size', 'mtimeMs', 'ext', 'tags', 'parent']
      }
    },
    maxSampleBytes: 24576,
    description: 'Captures directory relationships and tag affinities for graph visualisations.',
    concurrency: 24
  },
  neuro: {
    id: 'neuro',
    label: 'NeuroBloom',
    documentConfig: {
      tokenize: 'forward',
      resolution: 5,
      context: true,
      document: {
        id: 'id',
        index: ['name', 'pathTokens', 'contentSample', 'keywordVector'],
        store: ['path', 'name', 'size', 'mtimeMs', 'ext', 'tags', 'parent']
      }
    },
    maxSampleBytes: 8192,
    description: 'Applies adaptive keyword extraction inspired by neural attention heuristics.',
    concurrency: 16
  },
  quanta: {
    id: 'quanta',
    label: 'QuantaWeave',
    documentConfig: {
      tokenize: 'reverse',
      resolution: 12,
      threshold: 0,
      document: {
        id: 'id',
        index: ['name', 'pathTokens', 'contentSample', 'entropicSignature'],
        store: ['path', 'name', 'size', 'mtimeMs', 'ext', 'tags', 'parent']
      }
    },
    maxSampleBytes: 12288,
    description: 'Explores reverse token windows and entropy-weighted sampling.',
    concurrency: 20
  }
};

function resolveSystem(name) {
  if (!name) {
    return systems.kernel;
  }
  const key = name.toLowerCase();
  const match = systems[key] || Object.values(systems).find((sys) => sys.id === key || sys.label.toLowerCase() === key);
  if (!match) {
    const available = Object.values(systems)
      .map((sys) => `${sys.id} (${sys.label})`)
      .join(', ');
    throw new Error(`Unknown system: ${name}. Available systems: ${available}`);
  }
  return match;
}

function defaultIndexPath(baseDir, system) {
  return path.join(baseDir, `${system.id}-index`);
}

module.exports = {
  systems,
  resolveSystem,
  defaultIndexPath
};
