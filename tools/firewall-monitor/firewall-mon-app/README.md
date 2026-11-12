# FirewallMonApp

Angular 20 single-page application for [az-firewall-mon](../README.md).

## Development server

Run `npm start` (`ng serve`) for a dev server. Navigate to `http://localhost:4200/`. The app will automatically reload if you change any of the source files.

## Build

Run `npm run build` (`ng build`) to build the project using `@angular-builders/custom-webpack:browser` and `extra-webpack.config.js`. Build artifacts are written to `dist/firewall-mon-app/`.

## Running unit tests

Run `npm test` (`ng test --watch=false`) to execute headless unit tests via Angular's `@angular/build:unit-test` builder with [Vitest](https://vitest.dev/) and `jsdom`.

## Further help

To get more help on the Angular CLI use `npx ng help` or check out the [Angular CLI Overview and Command Reference](https://angular.dev/tools/cli).
