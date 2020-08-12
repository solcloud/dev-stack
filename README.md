# Dev stack

Vývojový bash skript pro ulehčení vývoje postavený nad `docker` a `docker-compose`.

# Závislosti

- Bash
- Docker
- Docker-compose

# Instalace

- a) do projektu lokálně přidat composer závislost
- b) "nainstalovat" globálně a do $PATH přidat `bin/dev-stack.sh`
 ideálně symlink pro použití jako příkaz `dev`, např. `ln -s ~/dev-stack/bin/dev-stack.sh ~/bin/dev`

# Spuštění

Nastartování kontejnerů `dev up`.
V projektu kde není `.dev-config` soubor spustit `dev init` a upravit soubor dle potřeb.
Ukončení kontejnerů `dev down`

# Příkazy

- usage: `dev`
- webserver cli: `dev ws`
- composer: `dev composer`
- PHPStan: `dev stan`
- PHPUnit: `dev unit`
- php: `dev php`
- spuštění workera (run.php): `dev worker`
