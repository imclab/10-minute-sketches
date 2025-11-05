const fs = require('fs/promises');
const path = require('path');
const { Document } = require('flexsearch');

async function loadSerializedIndex(indexPath, system) {
  const metadata = JSON.parse(await fs.readFile(path.join(indexPath, 'metadata.json'), 'utf8'));
  const documents = JSON.parse(await fs.readFile(path.join(indexPath, 'documents.json'), 'utf8'));
  const document = new Document(system.documentConfig);
  for (const payload of documents) {
    document.add(payload);
  }
  return { document, metadata };
}

function normalizeResults(rawResults) {
  const scores = new Map();
  for (const fieldResult of rawResults) {
    for (const entry of fieldResult.result) {
      const current = scores.get(entry.id);
      if (!current || entry.score < current.score) {
        scores.set(entry.id, { id: entry.id, score: entry.score });
      }
    }
  }
  return Array.from(scores.values()).sort((a, b) => a.score - b.score);
}

async function searchIndex({ query, indexPath, system, limit = 20 }) {
  const { document, metadata } = await loadSerializedIndex(indexPath, system);
  const rawResults = await document.search(query, { enrich: true, limit });
  const normalized = normalizeResults(rawResults).slice(0, limit);
  return normalized.map(({ id, score }) => ({
    id,
    score,
    ...metadata[id]
  }));
}

async function visualize(indexPath) {
  const metadata = JSON.parse(await fs.readFile(path.join(indexPath, 'metadata.json'), 'utf8'));
  const graph = JSON.parse(await fs.readFile(path.join(indexPath, 'graph.json'), 'utf8'));
  const nodes = Object.entries(metadata).map(([id, data]) => ({ id, label: data.name, path: data.path, size: data.size }));
  return { nodes, edges: graph.edges };
}

module.exports = {
  searchIndex,
  visualize,
  loadSerializedIndex
};
