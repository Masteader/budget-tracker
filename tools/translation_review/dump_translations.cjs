// Prints the two dictionaries of a translations.ts as JSON. Usage:
//   node dump_translations.cjs <path to translations.ts>
// Uses the TypeScript compiler web_app already has, so the values are the compiled ones.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ts = require(path.resolve(__dirname, '../../web_app/node_modules/typescript'));

const source = fs.readFileSync(process.argv[2], 'utf8');
const { outputText } = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
});
const sandbox = { exports: {} };
vm.runInNewContext(outputText, sandbox);
process.stdout.write(JSON.stringify({
  translations: sandbox.exports.translations,
  deleteAccountTranslations: sandbox.exports.deleteAccountTranslations ?? null,
}));
