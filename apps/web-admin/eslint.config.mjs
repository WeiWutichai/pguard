// pguard v2 scaffold stub — ESLint flat config extending Next.js presets.
// TODO(CLAUDE.md › Web (Next.js)): keep TypeScript strict; App Router only.
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { FlatCompat } from "@eslint/eslintrc";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const compat = new FlatCompat({
  baseDirectory: __dirname,
});

const eslintConfig = [
  ...compat.extends("next/core-web-vitals", "next/typescript"),
  {
    ignores: [".next/**", "node_modules/**", "src/api/generated/**"],
  },
];

export default eslintConfig;
