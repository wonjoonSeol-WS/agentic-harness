# AGENTS.md — Next.js TypeScript Project

Instructions for AI coding agents working in this Next.js TypeScript codebase.

## Architecture

This project uses Next.js 15+ with the App Router pattern:

- **src/app/** — Pages and layouts using the App Router file convention.
- **src/components/ui/** — Reusable UI components built on Radix UI + shadcn/ui.
- **src/components/** — Feature-specific composite components.
- **src/services/** — API layer with Axios, React Query hooks, and Zod validation.
- **src/stores/** — Client state management with Zustand.
- **src/lib/** — Shared utilities, constants, and type definitions.

## TypeScript Conventions

- **No `any` type.** Use `unknown` and narrow with type guards when the type is uncertain.
- **Zod for validation.** Define schemas in `src/services/{feature}/schema.ts` and infer types from them.
- **Named exports only.** Use barrel exports (`index.ts`) for public module APIs. Default exports are only allowed for Next.js pages and layouts.
- **Relative imports.** Use relative paths, not absolute paths or path aliases that obscure location.
- **Component files use `.tsx`.** Utility and service files use `.ts`.

## React Patterns

- **Server Components by default.** Only add `"use client"` when the component needs interactivity (hooks, event handlers, browser APIs).
- **React Query for server state.** Never fetch data with raw `useEffect` + `useState`. Use `useQuery` / `useMutation` from React Query.
- **Zustand for client state.** UI state that does not come from the server goes in Zustand stores.
- **React Hook Form + Zod** for form handling. Define validation schemas with priority levels (P0: critical, P1: important, P2: optional).

## Styling

- **Tailwind CSS v4** with custom design tokens.
- Follow the existing color and spacing tokens. Do not introduce arbitrary values.
- Use `cn()` utility for conditional class merging.

## Testing

- **Framework:** Vitest + React Testing Library.
- **Mocking:** MSW (Mock Service Worker) for API mocking.
- Run tests: `pnpm test`
- Run type-check: `pnpm type-check`
- Write tests for every new component and service hook. Test user behavior, not implementation details.

## Code Quality

- Run `pnpm lint --fix` before every commit.
- Run `pnpm prettier --write .` to format code.
- Keep components focused. If a component exceeds 150 lines, extract sub-components.
- Remove unused variables and imports.

## Quality Checks

The following commands run automatically after every code change. If any fails, the agent sees the output and self-corrects.

- `pnpm lint --fix` -- ESLint with auto-fix
- `pnpm prettier --write .` -- code formatting
- `pnpm type-check` -- TypeScript type verification
- `pnpm test` -- run all tests
- `pnpm build` -- verify production build
