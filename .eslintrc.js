module.exports = {
  root: true,
  env: { node: true },
  extends: [
    'eslint:recommended',
    'plugin:vue/essential'
  ],
  rules: {
    "prettier/prettier": [
      "warn",
      {
        "semi": true
      }
    ],
    "no-unused-vars": "off",
    "@typescript-eslint/no-unused-vars": ["warn"]
  },
  parserOptions: {
    parser: '@typescript-eslint/parser'
  },
  plugins: [
   'prettier', '@typescript-eslint', 'vue'
  ]
}
