// ESLint 9 flat config для монорепо.
// Phase 0: базові typescript-eslint правила без type-info (швидко на pre-commit).
// Type-checked rules можна підключити пізніше через `parserOptions.projectService`.

import js from "@eslint/js";
import tsParser from "@typescript-eslint/parser";
import tsPlugin from "@typescript-eslint/eslint-plugin";

export default [
  {
    ignores: [
      "**/node_modules/**",
      "**/dist/**",
      "**/.next/**",
      "**/build/**",
      "**/coverage/**",
      "**/.turbo/**",
      "**/migrations/**",
    ],
  },
  js.configs.recommended,
  {
    files: ["**/*.{ts,tsx,mts,cts}"],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        ecmaVersion: "latest",
        sourceType: "module",
      },
    },
    plugins: {
      "@typescript-eslint": tsPlugin,
    },
    rules: {
      ...tsPlugin.configs.recommended.rules,
      // TS-компілятор уже перевіряє undefined символи; ESLint no-undef
      // у TS-файлах призводить до false positives для globals (process, тощо).
      "no-undef": "off",
      "no-console": ["warn", { allow: ["warn", "error", "info"] }],
      "no-unused-vars": "off",
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
      "@typescript-eslint/consistent-type-imports": ["error", { fixStyle: "inline-type-imports" }],
    },
  },
];
