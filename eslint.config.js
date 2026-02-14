const js = require('@eslint/js');
const tseslint = require('typescript-eslint');

module.exports = tseslint.config(
  {
    ignores: ['node_modules', 'build', 'dist', '.react-router', 'coverage'],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['app/**/*.{ts,tsx}', 'scripts/**/*.ts', 'vite.config.ts', 'react-router.config.ts'],
    rules: {
      'no-console': ['warn', { allow: ['warn', 'error'] }],
    },
  }
);
