const fs = require('fs/promises');
const path = require('path');

async function* walk(root, { followSymlinks = false, signal } = {}) {
  const stack = [path.resolve(root)];
  while (stack.length) {
    const current = stack.pop();
    let dir;
    try {
      dir = await fs.opendir(current);
    } catch (error) {
      if (signal?.aborted) return;
      if (error.code === 'ENOTDIR' || error.code === 'ENFILE') {
        yield await describeFile(current);
      }
      continue;
    }

    for await (const dirent of dir) {
      if (signal?.aborted) {
        dir.close();
        return;
      }
      const fullPath = path.join(current, dirent.name);
      if (dirent.isSymbolicLink() && !followSymlinks) {
        continue;
      }
      if (dirent.isDirectory()) {
        stack.push(fullPath);
        continue;
      }
      if (dirent.isFile()) {
        yield await describeFile(fullPath, dirent);
      }
    }
  }
}

async function describeFile(fullPath, dirent) {
  const stats = await fs.stat(fullPath);
  return {
    path: fullPath,
    name: path.basename(fullPath),
    ext: path.extname(fullPath).slice(1).toLowerCase(),
    size: stats.size,
    mtimeMs: stats.mtimeMs,
    birthtimeMs: stats.birthtimeMs
  };
}

module.exports = {
  walk,
  describeFile
};
