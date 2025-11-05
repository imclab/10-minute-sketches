#!/usr/bin/env node
const path = require('path');
const { performance } = require('perf_hooks');
const { buildIndex } = require('../src/indexer');
const { searchIndex, visualize } = require('../src/searcher');
const { resolveSystem, defaultIndexPath, systems } = require('../src/systems');
const { green, cyan, yellow, red } = require('kleur');

function parseArgs(argv) {
  const [, , command, ...rest] = argv;
  const options = { _: [] };
  let key;
  for (const token of rest) {
    if (token.startsWith('--')) {
      key = token.replace(/^--/, '');
      options[key] = true;
    } else if (key) {
      options[key] = token;
      key = null;
    } else {
      options._.push(token);
    }
  }
  return { command, options };
}

function printHelp() {
  console.log(`Usage: multiscan <command> [options]\n`);
  console.log(`Commands:\n`);
  console.log(`  index <target>         Indexes the target directory using the chosen system.`);
  console.log(`  search <query>         Executes a search against the previously indexed data.`);
  console.log(`  visualize              Prints the graph-friendly export for the index.`);
  console.log(`  systems                Lists available competitive indexing systems.`);
  console.log(`\nOptions:\n`);
  console.log(`  --system <name>        Selects the system variant (default: kernel).`);
  console.log(`  --output <dir>         Directory to store index artifacts (default: ./data/<system>-index).`);
  console.log(`  --limit <n>            Limits search results (default: 20).`);
}

async function handleIndex(target, { system: systemName, output }) {
  const system = resolveSystem(systemName);
  const baseDir = output ? path.resolve(output) : defaultIndexPath(path.resolve('data'), system);
  const indexDir = path.resolve(baseDir);
  console.log(cyan(`→ ${system.label}: indexing ${target} ...`));
  const start = performance.now();
  const result = await buildIndex({ rootDir: target, outputDir: indexDir, system });
  const duration = ((performance.now() - start) / 1000).toFixed(2);
  console.log(green(`✓ Indexed ${result.filesIndexed} files in ${duration}s`));
  console.log(green(`  Index artifacts stored in ${indexDir}`));
}

async function handleSearch(query, { system: systemName, output, limit }) {
  const system = resolveSystem(systemName);
  const baseDir = output ? path.resolve(output) : defaultIndexPath(path.resolve('data'), system);
  const results = await searchIndex({ query, indexPath: baseDir, system, limit: Number(limit) || 20 });
  if (!results.length) {
    console.log(yellow('No results. Consider re-indexing or broadening your query.'));
    return;
  }
  for (const [idx, entry] of results.entries()) {
    console.log(`${green(`#${idx + 1}`)} ${entry.path}`);
    console.log(`   score=${entry.score.toFixed(3)} size=${entry.size}B modified=${new Date(entry.mtimeMs).toISOString()}`);
    if (entry.tags?.length) {
      console.log(`   tags=${entry.tags.join(', ')}`);
    }
  }
}

async function handleVisualize({ system: systemName, output }) {
  const system = resolveSystem(systemName);
  const baseDir = output ? path.resolve(output) : defaultIndexPath(path.resolve('data'), system);
  const graph = await visualize(baseDir);
  console.log(JSON.stringify(graph, null, 2));
}

function listSystems() {
  console.log('Available systems:');
  for (const system of Object.values(systems)) {
    console.log(` - ${cyan(system.label)} [${system.id}] → ${system.description}`);
  }
}

async function main() {
  const { command, options } = parseArgs(process.argv);
  try {
    switch (command) {
      case 'index': {
        const target = options._[0];
        if (!target) throw new Error('Missing target directory to index.');
        await handleIndex(path.resolve(target), options);
        break;
      }
      case 'search': {
        const query = options._.join(' ');
        if (!query) throw new Error('Missing query.');
        await handleSearch(query, options);
        break;
      }
      case 'visualize':
        await handleVisualize(options);
        break;
      case 'systems':
        listSystems();
        break;
      default:
        printHelp();
        process.exitCode = 1;
    }
  } catch (error) {
    console.error(red(`Error: ${error.message}`));
    process.exitCode = 1;
  }
}

main();
