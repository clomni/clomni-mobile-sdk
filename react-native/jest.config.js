// The JS layer on its own: react-native is replaced by a small fake (test/react-native.ts) that records what reaches
// the native module, so no simulator, emulator or Metro is needed.
module.exports = {
  testEnvironment: 'node',
  transform: {
    '^.+\\.ts$': ['ts-jest', { tsconfig: { module: 'CommonJS', moduleResolution: 'Node', target: 'ES2020',
      esModuleInterop: true, strict: true, skipLibCheck: true, types: ['jest'] } }],
  },
  roots: ['<rootDir>/src'],
  moduleNameMapper: {
    '^react-native$': '<rootDir>/test/react-native.ts',
  },
  // NativeClomni.ts is codegen's spec; the app never runs it.
  collectCoverageFrom: ['src/**/*.ts', '!src/__tests__/**', '!src/NativeClomni.ts'],
  coverageThreshold: { global: { lines: 90, branches: 85 } },
};
