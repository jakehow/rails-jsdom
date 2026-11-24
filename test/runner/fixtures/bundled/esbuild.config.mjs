const greeting = {
  name: "greeting",
  setup(build) {
    build.onResolve({ filter: /^virtual:greeting$/ }, args => ({ path: args.path, namespace: "greeting" }))
    build.onLoad({ filter: /.*/, namespace: "greeting" }, () => ({ contents: "export default \"Hello from a plugin\"", loader: "js" }))
  }
}

export default async options => ({ ...options, define: { BUILT_BY: "\"the app's esbuild config\"" }, plugins: [greeting, ...options.plugins] })
