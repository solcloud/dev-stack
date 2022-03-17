# Dev stack

`Bash` script for ease development built on top of `docker` and `docker-compose`.

You can watch showcase video on [youtube](https://youtu.be/YxJQqU3mXUM) ▶️.

# Install

Add `bin/dev-stack.sh` to your `$PATH`, ideally as `dev` shortcut, something like `ln -s /path/to/solcloud/dev-stack/bin/dev-stack.sh /bin/dev`.

# Activation

Start containers by running `dev up -v` in project working directory. If project don't have `.dev-config` file, run `dev init` to create one and edit as required. To stop containers run `dev down`.

# Config

Only required variable for `.dev-config` is `PPROJECT_NAME`. All others variable are optional, but if you do not specify them they fallback to default values. For example for this `.dev-config` file

```bash
PROJECT_NAME=my_project
```

actual base variables will be these behind scene:

```bash
PROJECT_NAME=my_project
PREFIX=solcloud_
PHP_VERSION=7.4
DOCUMENT_ROOT=
BASE_IMAGE=solcloud/php:${PHP_VERSION}
```

so if you want to use different `BASE_IMAGE` and do not want to use default `solcloud_` prefix with preconfigured services you can use for example this `.dev-config` file:

```bash
PROJECT_NAME=my_project
PREFIX=my_prefix_
BASE_IMAGE=php:8.1.3-apache
```

If `BASE_IMAGE` is not enough and you want absolute image control you can provide `COMPOSE_CONTEXT` variable with path to docker-compose build context folder.

# Commands

- usage: `dev`
- start `dev up`
- stop `dev down`
- status: `dev status`
- webserver cli: `dev ws`
- composer: `dev composer`
- PHPStan: `dev stan`
- PHPUnit: `dev unit`
- php cli: `dev php`
- worker start (run.php): `dev worker`
- Xdebug default enable: `dev xdebug`
- Xdebug cli one shot: `dev debug script.php`
