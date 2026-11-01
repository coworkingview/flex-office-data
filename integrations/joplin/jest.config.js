/** @type {import('jest').Config} */
module.exports = {
	testEnvironment: 'node',
	testMatch: ['<rootDir>/tests/**/*.test.ts'],
	modulePathIgnorePatterns: ['<rootDir>/dist/', '<rootDir>/publish/'],
	transform: {
		'^.+\\.ts$': ['ts-jest', {
			tsconfig: {
				esModuleInterop: true,
				module: 'commonjs',
				target: 'es2018',
				strict: true,
			},
		}],
	},
};
