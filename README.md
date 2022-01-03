# Dev stack

`Bash` script for ease development built on top of `docker` and `docker-compose`.

You can watch showcase video on [youtube](https://youtu.be/YxJQqU3mXUM) ▶️.

# Install

Add `bin/dev-stack.sh` to your `$PATH`, ideally as `dev` shortcut, something like `ln -s /path/to/solcloud/dev-stack/bin/dev-stack.sh /bin/dev`.

# Activation

Start containers by running `dev up -v` in project working directory. If project don't have `.dev-config` file, run `dev init` to create one and edit as required. To stop containers run `dev down`.

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
