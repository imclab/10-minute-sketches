10-minute-sketches
==================

A collection of Rybotron's short brain exercises for creative and technical stimulation. Sometimes created in 10 minutes or less and sometimes more. Example sketch types (hopefully) will be Quartz Composer, After Effects, Cinema 4D, Touch Designer, and Processing.

Check out www.rybotron.com or www.facebook.com/rybotronic for more information and images of the sketches.

## Multiscan Toolkit

This repository now ships with `multiscan`, a Node.js based competitive indexing and
search orchestrator featuring four self-competing strategies (KernelScan, GraphPulse,
NeuroBloom, QuantaWeave). It can rapidly index local directories, execute flexible
search queries, and export graph-friendly data for visualisations.

### Quick start

```bash
npm install
npm run start -- systems
npm run start -- index .
npm run start -- search kernel system
```

Each system stores its index under `data/<system>-index` by default. Use
`--output` to customise the destination and `--system <name>` to switch
variants.

### Automated verification

Run the full test suite (covering every strategy end-to-end) with:

```bash
npm test
```
