# Compliance Rules

This file contains the compliance and code quality rules for this repository.

## 1. Migration Files Must Follow Strict Naming Convention

**Objective:** Ensure database migration files follow the required timestamp-based naming pattern to maintain chronological order and enable proper migration tracking

**Success Criteria:** Migration files in core/server/data/migrations/versions/ (excluding versions 1.x, 2.x, 3.x) match the pattern: YYYY-MM-DD-HH-MM-descriptive-name-with-hyphens (e.g., 2022-04-05-12-00-add-member-alert-setting.js)

**Failure Criteria:** Migration files do not follow the required timestamp format or use underscores, camelCase, or other naming styles

---

## 2. Enforce Module Boundary Between core/shared and core/server

**Objective:** Maintain architectural separation by preventing core/shared modules from depending on core/server code, ensuring shared code remains truly reusable across server and frontend

**Success Criteria:** Files in core/shared/ do not contain require() or import statements that reference core/server/ paths

**Failure Criteria:** Files in core/shared/ import or require modules from core/server/

---

## 3. Enforce Module Boundary Between core/shared and core/frontend

**Objective:** Maintain architectural separation by preventing core/shared modules from depending on core/frontend code, ensuring shared code remains truly reusable across server and frontend

**Success Criteria:** Files in core/shared/ do not contain require() or import statements that reference core/frontend/ paths

**Failure Criteria:** Files in core/shared/ import or require modules from core/frontend/

---

## 4. Database Schema Must Not Include User Audit Fields

**Objective:** Prevent using created_by and updated_by fields in database schema to enforce the use of the action log for tracking user actions, providing better audit trails and separation of concerns

**Success Criteria:** The schema definition in core/server/data/schema/schema.js does not contain properties named 'created_by' or 'updated_by'

**Failure Criteria:** The schema definition includes 'created_by' or 'updated_by' fields

---

## 5. Database Migrations Must Not Use Loop Constructs

**Objective:** Prevent performance issues in database migrations by prohibiting loop constructs (for, while, forEach) that can cause migrations to run slowly or fail on large datasets

**Success Criteria:** Migration files in core/server/data/migrations/versions/ do not contain for statements, for-of statements, for-in statements, while statements, forEach calls, or _.each calls

**Failure Criteria:** Migration files contain any loop constructs including for, for-of, for-in, while, forEach, or _.each

---

## 6. Database Migrations Must Not Use Multiple JOIN Statements

**Objective:** Prevent complex and poorly performing database queries in migrations by prohibiting multiple JOIN operations in a single Knex query block

**Success Criteria:** Migration files do not chain multiple join/innerJoin/leftJoin calls on a single Knex query object

**Failure Criteria:** Migration files contain Knex queries with multiple chained join operations

---

## 7. Database Migrations Must Not Return Early from Loops

**Objective:** Prevent data processing errors in migrations by ensuring all records are processed when loops are used (in legacy migrations or utility functions)

**Success Criteria:** Migration files do not contain return statements inside loop bodies

**Failure Criteria:** Migration files contain return statements within loop constructs

---

## 8. API Endpoint Controllers Must Have Type Annotations

**Objective:** Ensure type safety and IDE support for API endpoint controllers by requiring JSDoc type annotations from @tryghost/api-framework

**Success Criteria:** API endpoint controller objects in core/server/api/endpoints/ include JSDoc type comment '@type {import('@tryghost/api-framework').Controller}'

**Failure Criteria:** API endpoint controllers lack the required JSDoc type annotation

---

## 9. API Endpoints Must Enforce Complexity Limits

**Objective:** Maintain code quality and prevent overly complex API endpoint implementations by enforcing complexity metrics on endpoint handler functions

**Success Criteria:** API endpoint files in core/server/api/endpoints/ pass the 'ghost/ghost-custom/max-api-complexity' ESLint rule

**Failure Criteria:** API endpoint functions exceed the maximum allowed cyclomatic complexity threshold

---

## 10. Internationalization Files Must Use Kebab-Case Naming

**Objective:** Ensure consistent file naming across all i18n translation files to maintain a uniform codebase structure and simplify automated tooling

**Success Criteria:** All files in ghost/i18n/ use kebab-case naming (lowercase letters, numbers, hyphens, and dots only): matching pattern ^[a-z0-9.-]+$

**Failure Criteria:** i18n files use camelCase, PascalCase, snake_case, or contain uppercase letters

---

## 11. Admin React Apps Must Use Kebab-Case File Naming

**Objective:** Enforce consistent kebab-case file naming convention across React admin applications to align with the codebase migration to kebab-case naming standards

**Success Criteria:** All files in apps/admin-x-* directories use kebab-case naming (lowercase letters, numbers, hyphens, and dots only): matching pattern ^[a-z0-9.-]+$

**Failure Criteria:** Admin app files use camelCase, PascalCase, snake_case, or contain uppercase letters

---

## 12. React Components Must Sort JSX Props in Standard Order

**Objective:** Maintain consistent and readable JSX code by enforcing a standard ordering of component props: reserved props first, callbacks last, shorthand props last

**Success Criteria:** JSX elements in React files have props ordered according to: reserved props (key, ref) first, then regular props alphabetically, then callbacks, then shorthand props last

**Failure Criteria:** JSX elements have props in non-standard order (e.g., callbacks before regular props, shorthand before callbacks)

---

## 13. React Button Elements Must Have Explicit Type Attribute

**Objective:** Prevent unintended form submissions and unclear button semantics by requiring all button elements to explicitly specify their type attribute (button, submit, or reset)

**Success Criteria:** All <button> elements in React files include an explicit type attribute

**Failure Criteria:** Button elements lack a type attribute or rely on browser default behavior

---

## 14. React List Rendering Must Not Use Array Index as Key

**Objective:** Prevent rendering bugs and performance issues by prohibiting the use of array indices as React key props, which can cause incorrect component state when lists are reordered or modified

**Success Criteria:** React components rendering lists use stable, unique identifiers (e.g., item.id) as key props, not array indices

**Failure Criteria:** List items use array index as the key prop (e.g., key={index} or key={i})

---

## 15. Tailwind CSS Classes Must Follow Standard Ordering

**Objective:** Ensure consistent and maintainable Tailwind CSS class lists by enforcing the standard ordering convention defined in the Tailwind configuration

**Success Criteria:** Tailwind utility classes in className attributes follow the ordering specified in tailwind.config.cjs (layout, positioning, sizing, spacing, typography, visual, etc.)

**Failure Criteria:** Tailwind classes are in non-standard order or randomly organized

---

## 16. TypeScript Files Must Enable Strict Type Checking

**Objective:** Ensure type safety and catch potential runtime errors at compile time by requiring strict mode and noImplicitAny in all TypeScript configurations

**Success Criteria:** tsconfig.json files include 'strict': true and 'noImplicitAny': true in compilerOptions

**Failure Criteria:** TypeScript configuration files have strict or noImplicitAny set to false or omitted

---

## 17. Code Must Use 4-Space Indentation

**Objective:** Maintain consistent code formatting across the codebase by enforcing 4-space indentation for all source files (except JSON and YAML which use 2 spaces)

**Success Criteria:** All JavaScript, TypeScript, and other source files use 4 spaces for indentation levels

**Failure Criteria:** Source files use tabs, 2-space indentation, or mixed indentation styles

---

## 18. Code Must Use Single Quotes for Strings

**Objective:** Ensure consistent string literal formatting across the codebase by requiring single quotes for all string values (template literals are allowed)

**Success Criteria:** String literals in JavaScript and TypeScript files use single quotes, except when using template literals for interpolation

**Failure Criteria:** String literals use double quotes without justified reason

---

## 19. Code Must Always Use Semicolons

**Objective:** Prevent subtle bugs from automatic semicolon insertion and maintain explicit statement termination by requiring semicolons at the end of all statements

**Success Criteria:** All JavaScript and TypeScript statements end with explicit semicolons

**Failure Criteria:** Statements rely on automatic semicolon insertion (ASI) instead of explicit semicolons

---

## 20. Code Must Use let or const Instead of var

**Objective:** Prevent hoisting-related bugs and unclear variable scoping by prohibiting var declarations in favor of block-scoped let and const

**Success Criteria:** All variable declarations use let (for reassignable variables) or const (for constants), never var

**Failure Criteria:** Code contains var declarations

---

## 21. Code Must Use Strict Equality Operators

**Objective:** Prevent type coercion bugs by requiring strict equality checks (=== and !==) instead of loose equality (== and !=)

**Success Criteria:** All equality comparisons use === or !== operators

**Failure Criteria:** Code contains == or != operators for equality checks

---

## 22. Code Must Not Use console.* Calls

**Objective:** Prevent debug statements from being committed to production code by prohibiting console.log, console.warn, and other console method calls

**Success Criteria:** Source files do not contain console.log, console.warn, console.error, or other console method calls

**Failure Criteria:** Code contains calls to console methods

---

## 23. Package Manager Must Be Yarn v1

**Objective:** Ensure consistent dependency management and workspace functionality by requiring Yarn v1 for all package operations, as the monorepo relies on Yarn workspaces

**Success Criteria:** All package management commands (install, add, remove, run) use yarn, not npm or other package managers

**Failure Criteria:** Code documentation, scripts, or CI configuration references npm or other package managers for dependency management

---

## 24. Node.js Version Must Match Engine Requirement

**Objective:** Ensure compatibility and prevent runtime errors by enforcing the specific Node.js version required by the Ghost application

**Success Criteria:** Development and production environments use Node.js version matching the engines.node specification in ghost/core/package.json (^22.13.1)

**Failure Criteria:** Environment uses a Node.js version outside the specified semver range

---
