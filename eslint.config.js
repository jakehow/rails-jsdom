"use strict"

const js = require("@eslint/js")
const noComments = require("./eslint/no-comments")

const node = { require: "readonly", setImmediate: "readonly", module: "writable", __dirname: "readonly", process: "readonly", Buffer: "readonly", console: "readonly", setTimeout: "readonly", Headers: "readonly", Request: "readonly", Response: "readonly", structuredClone: "readonly" }
const browser = { window: "readonly", document: "readonly", fetch: "readonly" }

module.exports = [
  { ignores: ["node_modules/**", "vendor/**", "coverage/**", "doc/**", "test/dummy/tmp/**", "test/dummy/log/**", "test/runner/fixtures/app/node_modules/**"] },
  js.configs.recommended,
  {
    files: ["**/*.js"],
    plugins: { "rails-jsdom": { rules: { "no-comments": noComments } } },
    linterOptions: { noInlineConfig: true, reportUnusedDisableDirectives: "error" },
    rules: {
      "rails-jsdom/no-comments": "error",
      "no-unused-vars": ["error", { args: "all", caughtErrors: "all" }],
      "complexity": ["error", 8],
      "max-lines-per-function": ["error", { max: 25, skipBlankLines: true }],
      "max-statements": ["error", 16],
      "max-depth": ["error", 2],
      "max-params": ["error", 4],
      "max-nested-callbacks": ["error", 3],
      "no-nested-ternary": "error",
      "camelcase": ["error", { properties: "never" }],
      "eqeqeq": "error",
      "no-var": "error",
      "prefer-const": "error",
      "semi": ["error", "never"],
      "quotes": ["error", "double", { avoidEscape: true, allowTemplateLiterals: true }],
      "indent": ["error", 2, { SwitchCase: 1 }],
      "comma-dangle": ["error", "never"],
      "eol-last": "error",
      "no-trailing-spaces": "error",
      "no-multiple-empty-lines": ["error", { max: 1, maxEOF: 0 }],
      "object-curly-spacing": ["error", "always"],
      "array-bracket-spacing": ["error", "never"],
      "space-before-function-paren": ["error", { anonymous: "always", named: "never", asyncArrow: "always" }],
      "keyword-spacing": "error",
      "space-infix-ops": "error",
      "arrow-parens": ["error", "as-needed"]
    }
  },
  { files: ["lib/**/*.js", "eslint/**/*.js", "eslint.config.js", "test/runner/*.js", "test/eslint/*.js"], languageOptions: { sourceType: "commonjs", globals: node } },
  { files: ["test/dummy/app/javascript/**/*.js", "test/runner/fixtures/app/{app,vendor}/**/*.js"], languageOptions: { sourceType: "module", globals: browser } },
  { files: ["test/runner/fixtures/app/node_modules/**/*.js"], languageOptions: { sourceType: "commonjs", globals: node } }
]
