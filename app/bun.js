#!/usr/bin/env bun

/**
 * Entry point used to run the preview server with Bun.
 *
 * The Node.js entry point (app/index.js) boots the server through a custom
 * vm/Module loader (see src/app/load.ts), needed by the pre built `pkg` binary
 * to resolve the modules bundled inside its snapshot. Bun ships only a partial
 * `node:vm` implementation, so instead of reusing that loader we require the
 * server bundle directly, letting Bun resolve the modules from node_modules.
 */

const path = require('path')

const PATH_FLAG = '--path'
const VERSION_FLAG = '--version'

const argv = process.argv.slice(2)

const scriptPath =
  argv[0] === PATH_FLAG && argv[1]
    ? path.resolve(argv[1])
    : path.join(__dirname, 'server.js')

// the server resolves `out/` and `_static/` relative to the app directory,
// resolve the script path before changing the working directory
process.chdir(__dirname)

if (argv[0] === VERSION_FLAG) {
  // keep the same version as the version printed by app/index.js
  console.log(require('../package.json').version)
} else {
  require(scriptPath).run()
}
