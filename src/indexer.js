const fs = require('fs/promises');
const path = require('path');
const crypto = require('crypto');
const { Document } = require('flexsearch');
const { walk } = require('./fileWalker');

function tokenizePathSegments(filePath) {
  return filePath
    .split(path.sep)
    .filter(Boolean)
    .map((segment) => segment.replace(/[^\w\d]+/g, ' ').trim())
    .filter(Boolean);
}

function deriveTags(fileInfo) {
  const tokens = tokenizePathSegments(fileInfo.path);
  const extToken = fileInfo.ext ? [fileInfo.ext] : [];
  return [...new Set([...tokens.slice(-4), ...extToken])];
}

function keywordsFromContent(sample) {
  if (!sample) return [];
  return sample
    .toLowerCase()
    .replace(/[^\w\s]+/g, ' ')
    .split(/\s+/)
    .filter((token) => token.length > 3)
    .slice(0, 32);
}

async function readSample(fullPath, { maxBytes }) {
  try {
    const fileHandle = await fs.open(fullPath, 'r');
    const buffer = Buffer.allocUnsafe(maxBytes);
    const { bytesRead } = await fileHandle.read(buffer, 0, maxBytes, 0);
    await fileHandle.close();
    return buffer.slice(0, bytesRead).toString('utf8');
  } catch (error) {
    if (error.code === 'EISDIR' || error.code === 'EACCES') {
      return '';
    }
    throw error;
  }
}

async function ensureDirectory(dir) {
  await fs.mkdir(dir, { recursive: true });
}

async function exportDocument(document) {
  const payload = {};
  await document.export((key, data) => {
    payload[key] = data;
  });
  return payload;
}

async function buildIndex({
  rootDir,
  outputDir,
  system,
  followSymlinks = false,
  signal
}) {
  const indexStart = Date.now();
  await ensureDirectory(outputDir);
  const document = new Document(system.documentConfig);
  const metadata = new Map();
  const documentsPayload = [];
  const graphEdges = [];
  let count = 0;

  const inFlight = new Set();

  const schedule = async (fileInfo) => {
    const task = (async () => {
      const id = crypto.createHash('sha1').update(fileInfo.path).digest('hex');
      const parent = path.dirname(fileInfo.path);
      const contentSample = await readSample(fileInfo.path, { maxBytes: system.maxSampleBytes });
      const tags = deriveTags(fileInfo);
      const keywords = keywordsFromContent(contentSample);
      const documentPayload = {
        id,
        path: fileInfo.path,
        name: fileInfo.name,
        pathTokens: tokenizePathSegments(fileInfo.path),
        contentSample,
        tagString: tags.join(' '),
        keywordVector: keywords.join(' '),
        entropicSignature: `${tags.join(' ')} ${keywords.join(' ')}`,
        size: fileInfo.size,
        mtimeMs: fileInfo.mtimeMs,
        ext: fileInfo.ext,
        tags,
        parent
      };
      document.add(documentPayload);
      documentsPayload.push(documentPayload);
      metadata.set(id, {
        path: fileInfo.path,
        name: fileInfo.name,
        size: fileInfo.size,
        mtimeMs: fileInfo.mtimeMs,
        ext: fileInfo.ext,
        tags,
        parent
      });
      graphEdges.push({ from: parent, to: fileInfo.path });
      count += 1;
    })()
      .catch((error) => {
        if (error.code !== 'EACCES') {
          throw error;
        }
      })
      .finally(() => inFlight.delete(task));
    inFlight.add(task);
    if (inFlight.size >= system.concurrency) {
      await Promise.race(inFlight);
    }
  };

  for await (const fileInfo of walk(rootDir, { followSymlinks, signal })) {
    await schedule(fileInfo);
  }

  await Promise.allSettled(inFlight);

  const serialized = await exportDocument(document);
  const metaObject = Object.fromEntries(metadata.entries());
  await fs.writeFile(path.join(outputDir, 'index.flex'), JSON.stringify(serialized), 'utf8');
  await fs.writeFile(path.join(outputDir, 'metadata.json'), JSON.stringify(metaObject, null, 2), 'utf8');
  await fs.writeFile(path.join(outputDir, 'documents.json'), JSON.stringify(documentsPayload, null, 2), 'utf8');
  await fs.writeFile(path.join(outputDir, 'graph.json'), JSON.stringify({ edges: graphEdges }, null, 2), 'utf8');

  return {
    filesIndexed: count,
    durationMs: Date.now() - indexStart,
    indexPath: outputDir
  };
}

module.exports = {
  buildIndex
};
