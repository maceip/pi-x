---
name: typescript-expert
description: Advanced TypeScript architecture, strict typing, generics, type-level programming, ESM module resolution, type narrowing, and modern TS best practices. Use when writing, refactoring, or debugging TypeScript code.
---

# TypeScript Expert Skill

High-performance, idiomatic, and strictly-typed TypeScript engineering guidelines.

## Core Directives

1. **Strict Type Safety**: Always enable and maintain `"strict": true`, `"noImplicitAny": true`, `"strictNullChecks": true`, and `"exactOptionalPropertyTypes": true` where possible. Avoid `any`; use `unknown` with type predicates or validation schemas (Zod / TypeBox / ArkType).
2. **Discriminated Unions & Pattern Matching**: Use tagged unions with distinct literal discriminator keys (`type`, `kind`, `tag`) for state and event handling.
3. **Type Narrowing & Predicates**: Use user-defined type predicates (`function isX(val: unknown): val is X`) and `asserts` functions for runtime boundary checks.
4. **Const Type Parameters & Narrow Inferences**: Leverage `as const` and `satisfies` operator to validate object structures without losing literal types.
5. **ESM & Module System**: Use NodeNext/Bundler module resolution, explicit `.js` extensions for local imports when targeting NodeNext ESM, and avoid namespace pollution.

## High-Performance Idioms

### 1. Discriminated Unions for Complex State & Events
```typescript
export type AsyncState<T, E = Error> =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "success"; data: T }
  | { status: "error"; error: E };

export function matchState<T, R>(
  state: AsyncState<T>,
  handlers: {
    idle: () => R;
    loading: () => R;
    success: (data: T) => R;
    error: (err: Error) => R;
  }
): R {
  switch (state.status) {
    case "idle": return handlers.idle();
    case "loading": return handlers.loading();
    case "success": return handlers.success(state.data);
    case "error": return handlers.error(state.error);
  }
}
```

### 2. Type-Safe Exhaustiveness Checking
```typescript
export function assertNever(x: never, message = "Unexpected unreachable code branch"): never {
  throw new Error(`${message}: ${JSON.stringify(x)}`);
}
```

### 3. Builder & Options Pattern with `satisfies`
```typescript
export interface ClientConfig {
  readonly endpoint: string;
  readonly timeoutMs: number;
  readonly headers?: Readonly<Record<string, string>>;
}

export const defaultConfig = {
  endpoint: "http://127.0.0.1:8000/v1",
  timeoutMs: 30000,
  headers: { "x-client": "pi-coding-agent" },
} as const satisfies ClientConfig;
```
