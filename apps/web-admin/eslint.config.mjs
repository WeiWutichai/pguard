// ESLint flat config (ESLint 9). eslint-config-next 16 ships a NATIVE flat-config array
// (Linter.Config[]) — spread it directly; FlatCompat is no longer needed (and breaks here).
import next from "eslint-config-next";

const eslintConfig = [
  ...next,
  {
    // Generated client + build output are not hand-edited → not linted.
    ignores: [".next/**", "node_modules/**", "src/api/generated/**"],
  },
];

export default eslintConfig;
