const searchForm = document.getElementById('search-form');
const searchOutput = document.getElementById('search-results');
const graphForm = document.getElementById('graph-form');
const graphHost = document.getElementById('graph');

async function handleSearch(event) {
  event.preventDefault();
  const domain = document.getElementById('domain').value;
  const query = document.getElementById('query').value.trim();
  const limit = document.getElementById('limit').value;
  if (!query) {
    searchOutput.textContent = 'Enter a query to search.';
    return;
  }
  searchOutput.textContent = 'Loading…';
  try {
    const params = new URLSearchParams({ domain, q: query, limit });
    const res = await fetch(`/search?${params.toString()}`);
    if (!res.ok) {
      throw new Error(`Search failed: ${res.status}`);
    }
    const data = await res.json();
    if (domain === 'files') {
      const lines = data.map((row) => `${row.path}\n  size=${row.size}B mtime=${new Date(row.mtime * 1000).toISOString()}${row.hash ? `\n  hash=${row.hash}` : ''}`);
      searchOutput.textContent = lines.join('\n\n') || 'No results';
    } else {
      const lines = data.map((row) => `[#${row.lang}] ${row.title}\n  ${row.summary ? row.summary.slice(0, 400) : 'No summary available.'}`);
      searchOutput.textContent = lines.join('\n\n') || 'No results';
    }
  } catch (err) {
    searchOutput.textContent = err.message;
  }
}

function renderGraph(payload) {
  graphHost.innerHTML = '';
  const width = graphHost.clientWidth || 600;
  const height = 420;
  const svg = d3.select(graphHost).append('svg').attr('viewBox', `0 0 ${width} ${height}`);

  const nodesMap = new Map();
  const links = [];
  Object.entries(payload.edges).forEach(([src, targets]) => {
    if (!nodesMap.has(src)) nodesMap.set(src, { id: src });
    targets.forEach((tgt) => {
      if (!nodesMap.has(tgt)) nodesMap.set(tgt, { id: tgt });
      links.push({ source: src, target: tgt });
    });
  });
  const nodes = Array.from(nodesMap.values());

  const simulation = d3.forceSimulation(nodes)
    .force('link', d3.forceLink(links).id((d) => d.id).distance(120))
    .force('charge', d3.forceManyBody().strength(-240))
    .force('center', d3.forceCenter(width / 2, height / 2));

  const link = svg.append('g')
    .attr('stroke', '#888')
    .attr('stroke-opacity', 0.6)
    .selectAll('line')
    .data(links)
    .enter()
    .append('line')
    .attr('stroke-width', 1.5);

  const node = svg.append('g')
    .attr('stroke', '#fff')
    .attr('stroke-width', 1.5)
    .selectAll('g')
    .data(nodes)
    .enter()
    .append('g')
    .call(d3.drag()
      .on('start', (event, d) => {
        if (!event.active) simulation.alphaTarget(0.3).restart();
        d.fx = d.x;
        d.fy = d.y;
      })
      .on('drag', (event, d) => {
        d.fx = event.x;
        d.fy = event.y;
      })
      .on('end', (event, d) => {
        if (!event.active) simulation.alphaTarget(0);
        d.fx = null;
        d.fy = null;
      }));

  node.append('circle').attr('r', 10).attr('fill', (d) => (d.id === payload.root ? '#2563eb' : '#22c55e'));
  node.append('text')
    .attr('x', 12)
    .attr('y', 4)
    .text((d) => d.id)
    .attr('font-size', 12)
    .attr('fill', '#1f2933');

  simulation.on('tick', () => {
    link
      .attr('x1', (d) => d.source.x)
      .attr('y1', (d) => d.source.y)
      .attr('x2', (d) => d.target.x)
      .attr('y2', (d) => d.target.y);

    node.attr('transform', (d) => `translate(${d.x}, ${d.y})`);
  });
}

async function handleGraph(event) {
  event.preventDefault();
  const concept = document.getElementById('concept').value.trim();
  const depth = document.getElementById('depth').value;
  const lang = document.getElementById('lang').value.trim();
  if (!concept) {
    graphHost.textContent = 'Enter a concept title.';
    return;
  }
  graphHost.textContent = 'Loading…';
  try {
    const params = new URLSearchParams({ concept, depth });
    if (lang) params.set('lang', lang);
    const res = await fetch(`/graph?${params.toString()}`);
    if (!res.ok) {
      throw new Error(`Graph fetch failed: ${res.status}`);
    }
    const data = await res.json();
    renderGraph(data);
  } catch (err) {
    graphHost.textContent = err.message;
  }
}

searchForm.addEventListener('submit', handleSearch);
graphForm.addEventListener('submit', handleGraph);

// Prime the graph with Linux if already indexed
window.addEventListener('load', () => {
  document.getElementById('concept').value = 'Linux';
});
