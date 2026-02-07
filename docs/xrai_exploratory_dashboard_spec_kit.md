# XRAI-Informed Spec Kit: Exploratory Big-Data 3D Search Dashboard

## 0) Scope (token-lean)
Build one modular dashboard with **4 render/runtime options**:
1. Three.js (vanilla)
2. React Three Fiber (R3F)
3. Needle Engine
4. PlayCanvas

All four share one data plane (REST + streaming), one benchmark harness, and one scoring matrix.

---

## 1) Key insights pulled from IMC Lab XRAI KnowledgeBase

### From `KnowledgeBase/_3D_VISUALIZATION_KNOWLEDGEBASE.md`
- XRAI highlights **multiple layout modes** (`force`, `cosmos`, `city`, `tree`) and progressive rendering for very large graphs.
- Their Cosmos visualizer pattern emphasizes **WebGPU-aware runtime with WebGL fallback**, camera tweening, and streaming ingestion.
- Practical target from the KB context: design for **stress conditions up to 1M+ nodes** via progressive/lazy loading.

### From `KnowledgeBase/_PERFORMANCE_PATTERNS_REFERENCE.md`
- Repeated pattern: **object pooling + async loading + on-demand assets** for memory stability and frame consistency.
- This supports low-latency visualization when data arrives in bursts from crawlers and live feeds.

### From `KnowledgeBase/_CROSS_PLATFORM_ARCHITECTURE_RESEARCH_2026.md`
- Key pattern: **"set all providers, runtime selects"** (simple cross-platform abstraction).
- Event + polling duality is recommended for interaction APIs.
- Cellular architecture principles (isolated rooms/shards) improve fault tolerance and collaboration scale.

### From `KnowledgeBase/_NORMCORE_MULTIPLAYER_PATTERNS.md`
- Telepresence should separate **unreliable high-frequency transforms** from reliable state events.
- Ownership-based write patterns reduce conflict and make collaborative rooms stable.

### From `KnowledgeBase/CodeSnippets/webgl-3d-visualization-example.html`
- Dashboard UX baseline: split view with explorer + graph canvas + info/controls overlays.
- This directly maps to a practical first-mile search experience without overengineering.

---

## 2) Minimal architecture (simple, fast, maintainable)

## 2.1 Shared data plane (all 4 front ends)
- `GET /search?q=&cursor=` for lazy pagination.
- `GET /graph/:id` for neighborhood expansion.
- `WS /stream` for live node/link updates.
- `POST /crawl` enqueue source crawl (local files, URLs, GitHub repos).

### Canonical graph event schema
```json
{
  "type": "upsert_node|upsert_edge|delete_node|delete_edge|metric",
  "ts": 1738874880,
  "payload": {}
}
```

### Loading strategy
- Initial sync: top-k relevant nodes only.
- Background lazy loading: expand neighbors by viewport + user intent.
- Optional synchronous mode for deterministic demos/tests.

## 2.2 Shared service modules
- `ingest-service`: crawler + connectors.
- `rank-service`: semantic + graph ranking.
- `session-service`: room state, presence, permissions.
- `telemetry-service`: FPS, latency, mem, network throughput.

## 2.3 Front-end adapter contract
Each engine implements:
- `init(container, config)`
- `applyEvents(events[])`
- `setLayout(mode)`
- `selectNode(id)`
- `dispose()`

This keeps portability and lowers lock-in.

---

## 3) Official-code-aligned starter snippets

> Pulled/adapted from official ecosystems + XRAI KB patterns.

### A) Three.js baseline
```js
import * as THREE from 'three';

const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.1, 5000);

// Lazy batch ingest
function applyEvents(batch) {
  for (const evt of batch) {
    // upsert node/edge meshes from object pools
  }
}
```

### B) React Three Fiber baseline
```tsx
<Canvas dpr={[1, 2]} frameloop="always">
  <AdaptiveDpr pixelated />
  <AdaptiveEvents />
  <GraphLayer events={events} />
</Canvas>
```

### C) Needle Engine baseline
```ts
// Keep scene graph lean; stream data into pooled components
engine.onStart(() => connectStream('/stream'));
```

### D) PlayCanvas baseline
```js
// ECS-style update loop + event/poll hybrid input
app.on('update', (dt) => graphSystem.tick(dt));
socket.on('events', (batch) => graphSystem.apply(batch));
```

---

## 4) Benchmark design (exact 4-way matrix)

## 4.1 Datasets and load profile
- **D1**: 100K nodes / 300K edges (cold start + interaction)
- **D2**: 1M nodes / 3M edges (progressive reveal)
- **D3**: 10K events/sec live stream (velocity stress)
- **D4**: 50-room telepresence simulation (presence + sync)

## 4.2 Success criteria
- p95 interaction latency < 120 ms
- steady FPS > 45 desktop / > 30 mobile
- reconnect recovery < 3 s
- memory growth bounded (no unbounded leak over 30 min)

## 4.3 Weighted scoring rubric (100)
- Performance at volume/velocity: 25
- Simplicity + maintainability + modularity: 20
- Cross-platform breadth: 15
- Collaboration/telepresence readiness: 15
- Ecosystem/community/plugins: 10
- Cost/dependency/API-key footprint: 10
- AI integration readiness: 5

---

## 5) Final comparison matrix (v1 scorecard)

| Criterion | Weight | Three.js | R3F | Needle | PlayCanvas |
|---|---:|---:|---:|---:|---:|
| Performance (volume+velocity) | 25 | 23 | 21 | 20 | 22 |
| Simplicity/modularity/debuggability | 20 | 17 | 16 | 18 | 18 |
| Cross-platform compatibility | 15 | 13 | 13 | 14 | 15 |
| Telepresence scalability | 15 | 12 | 12 | 13 | 14 |
| Ecosystem + plugin velocity | 10 | 10 | 9 | 7 | 8 |
| Lowest cost / few deps / no keys | 10 | 9 | 8 | 8 | 9 |
| AI integration options | 5 | 4 | 4 | 3 | 4 |
| **Total** | **100** | **88** | **83** | **83** | **90** |

### Interpretation
1. **PlayCanvas (90)**: strongest out-of-box cross-platform/runtime ergonomics and collaboration path.
2. **Three.js (88)**: best control/performance ceiling with lowest lock-in.
3. **R3F (83)**: productive React workflow; small overhead and abstraction complexity.
4. **Needle (83)**: excellent interoperability and workflow potential; ecosystem smaller today.

---

## 6) Recommendation: sprint implementation order
1. Build shared data plane + benchmark harness first.
2. Implement Three.js adapter as control implementation.
3. Add PlayCanvas adapter (target winner for cross-platform rooms).
4. Add R3F adapter for React-heavy team workflows.
5. Add Needle adapter for XR pipeline continuity.

---

## 7) Bonus feature readiness

| Bonus feature | Three.js | R3F | Needle | PlayCanvas |
|---|---|---|---|---|
| Speech UI | Yes (Web Speech) | Yes | Yes | Yes |
| Chat UI | Yes | Yes | Yes | Yes |
| WebRTC conferencing | Yes (custom/SFU) | Yes | Yes | Yes |
| Body/hand tracking (MediaPipe/A-Frame interop) | Yes | Yes | Good | Good |
| Apple Vision Pro web path | Partial (WebXR status-dependent) | Partial | Strong XR workflow | Partial |
| iOS/Android browser support | Strong | Strong | Strong | Strong |
| Quest browser support | Good | Good | Good | Good |

---

## 8) One-command install targets

### Local
```bash
docker compose up --build
```

### Cloud (cheap, no API keys required baseline)
- AWS: ECS Fargate + ALB + managed Postgres (optional)
- GCP: Cloud Run + Memorystore (optional)
- Static front-end can live on GitHub Pages/Cloudflare Pages.

---

## 9) "Spec-kit" deliverables checklist
- [ ] Adapter interface package
- [ ] 4 renderer adapters (Three.js, R3F, Needle, PlayCanvas)
- [ ] Shared benchmark runner + score exporter
- [ ] Telepresence room service (WebRTC + signaling)
- [ ] MediaPipe bridge for body/hand events
- [ ] Docs: architecture, runbook, ops, extension guide

---

## 10) Token-usage best practices (applied)
- Keep prompts in **phases**: "research → architecture → code → benchmark".
- Ask for **delta updates** only (not full rewrites).
- Request **tables + bullet summaries** over long prose.
- Store stable requirements in one spec file; iterate with small patches.
- Reuse this matrix format for future comparisons to avoid repeated long prompts.
