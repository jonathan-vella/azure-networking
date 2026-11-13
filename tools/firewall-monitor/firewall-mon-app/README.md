# Firewall Monitor Frontend (`firewall-mon-app`)

Angular 22 single-page application (TypeScript 6.0, Angular Material/CDK 22) for [az-firewall-mon](../README.md). See also [INSTALL.md](../INSTALL.md) and the [Labs and tools guide](../../../src/content/docs/06-operations-reviews/labs-and-tools-guide.md).

## Development server

Run `npm start` (`ng serve`) to start the local dev server at `http://localhost:4200/`. Changes to source files trigger live reload automatically.

## Production build

Run `npm run build` (`ng build`) to build the application with Angular's `@angular/build:application` esbuild builder. Output artifacts are written directly to `dist/firewall-mon-app/` (`"browser": ""` in `angular.json`), matching the `outputLocation` configured in [`../bicep/setup.bicep`](../bicep/setup.bicep).

## Unit tests

Run `npm test` (`ng test --watch=false`) to execute the headless unit test suite with Angular's `@angular/build:unit-test` builder, [Vitest 5.1](https://vitest.dev/), and `jsdom`.

## Backend API tests

From the repository root, build the .NET 8 isolated Azure Functions API and run the xUnit test suite:

```bash
dotnet build tools/firewall-monitor/firewall-mon-api/api.csproj --configuration Release
dotnet test tools/firewall-monitor/firewall-mon-api.Tests/firewall-mon-api.Tests.csproj --configuration Release
```

## Angular CLI reference

Run `npx ng help` or see the [Angular CLI reference](https://angular.dev/tools/cli).

