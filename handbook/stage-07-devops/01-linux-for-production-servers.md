# Linux for Production Servers

## Introduction

Almost every production backend in the world runs on Linux, and the moment your code leaves
your laptop it becomes a Linux problem: a process that won't stay up, a disk that filled with
logs, a permission that blocks a deploy, a port nothing is listening on. You don't need to be a
kernel hacker, but you do need to operate a Linux server with confidence — because when the
app is down at 2 a.m., there is no framework between you and the machine. This chapter is the
Linux an application engineer actually uses to run production: the process model, the
filesystem and permissions, the service manager, networking, logs, and resource limits — the
mental model that makes the rest of this stage (Docker, Nginx, VPS deploys) comprehensible
instead of magical.

The single most important idea: **a Linux server is a small number of concepts — processes,
files, users/permissions, services, ports, and resources — and almost every production
incident is one of them going wrong.** The app won't start (a process/permission/port
problem), the site is unreachable (a networking/firewall problem), the disk is full (a
resource problem), the service died and didn't come back (a service-manager problem). An
engineer who can name which of these six things is failing can fix nearly anything; one who
treats the server as an opaque box is helpless the instant the happy path breaks.

The judgment this chapter teaches is **operational literacy over memorized commands.** The goal
is not to recite flags — you and your AI assistant can look those up — it's to know what
question you're asking: "is the process running?" (`systemctl status`, `ps`), "what's it
listening on?" (`ss -tlnp`), "who can read this file?" (`ls -l`, permissions), "where did it
go?" (`journalctl`), "what's eating the disk/memory/CPU?" (`df`, `free`, `top`). This is the
foundation the whole stage stands on: Docker runs Linux processes in namespaces, Nginx is a
Linux service on a Linux port, a VPS deploy is these commands over SSH. Get the mental model
and the tools become obvious.

## Why It Matters

Linux fluency is the difference between operating a production system and hoping it keeps
working:

- **Production runs on Linux, and abstractions leak.** Docker, Kubernetes, your PaaS, your CI
  runner — all Linux underneath. When a container won't start, a health check fails, or a
  volume mount is read-only, the error is a Linux error (permission denied, address already in
  use, no space left on device). Without the base layer you can't debug the layers on top.
- **Incidents are a race, and the server is where they're diagnosed.** "The API is down" is
  solved by logging in and asking the six questions: is the process up, is the port bound, is
  the disk full, what do the logs say. An engineer who knows the machine resolves it in
  minutes; one who doesn't escalates and waits.
- **Permissions and users are a security boundary, not a nuisance.** Running everything as
  root, world-writable secrets, an app that can read the whole filesystem — these are how a
  small bug becomes a full compromise. The Linux permission model is the first line of defense
  (deep security hardening is Stage 9; this chapter is the mechanics you build on).
- **Resource exhaustion is the most common silent outage.** Disks fill with logs, memory runs
  out and the OOM killer terminates your app, a file-descriptor limit caps connections. These
  don't throw application errors — the app just dies or hangs. Knowing `df`, `free`, `top`,
  and `ulimit` turns a mystery outage into a one-line diagnosis.
- **Every later chapter assumes it.** Docker is Linux process isolation. Nginx is a Linux
  daemon. The VPS deploy is SSH plus these commands. `systemd` supervises your services. This
  chapter is the vocabulary the rest of the stage speaks.

Get it right — you can log into any Linux box and quickly answer what's running, what it's
listening on, where its logs are, and what's consuming resources — and you can operate,
debug, and secure production. Get it wrong and the server is a black box you pray to, and
every incident is an emergency you can't diagnose.

The AI dimension: assistants generate Linux commands fluently but operate without the machine
in front of them. They run apps as root, `chmod 777` to make a permission error "go away,"
suggest `nohup ... &` where a real service needs `systemd`, and give commands without the
diagnostic reasoning — the *why this command answers this question*. They're excellent at
recalling syntax and terrible at the judgment of what to check and what not to do to a
production box. This chapter is that judgment.

## Mental Model

A production Linux server is six concepts. Almost every incident is one of them:

```
   THE SIX THINGS (name which one is failing, and you can fix almost anything)

   1. PROCESSES        a running program = a process (PID). It has a parent, a user,
                       open files, and a state.  ps aux · top/htop · kill <pid>
                          "is the app running?"  →  ps / systemctl status

   2. FILES & FS       everything is a file; storage is mounted into one tree (/).
                       /etc config · /var/log logs · /home users · /proc kernel view
                          "where is X / is the disk full?"  →  ls · find · df -h · du

   3. USERS & PERMS    every file has owner/group and rwx bits (user·group·other).
                       root = uid 0 (all-powerful). run apps as a NON-root user.
                          "who can touch this?"  →  ls -l · chown · chmod · id

   4. SERVICES         long-running programs supervised by systemd (start on boot,
                       restart on crash, capture logs).  a unit = a .service file.
                          "keep it running"  →  systemctl start/enable/status · journalctl

   5. NETWORK & PORTS  a service listens on a PORT; firewall decides what's reachable.
                       0.0.0.0:8000 = all interfaces · 127.0.0.1:8000 = localhost only
                          "what's listening / why unreachable?"  →  ss -tlnp · ufw · curl

   6. RESOURCES        finite: CPU, memory, disk, file descriptors. exhaustion = outage
                       (OOM killer, ENOSPC, EMFILE) with no application error.
                          "what's being exhausted?"  →  top · free -h · df -h · ulimit

   THE DIAGNOSTIC LOOP (any "it's broken" on a server)
     up?  →  systemctl status / ps        listening?  →  ss -tlnp
     logs? →  journalctl -u <svc>          resources? →  df -h ; free -h ; top
```

Four principles carry the chapter:

**Everything is a process, a file, or a permission.** A running program is a process with a
PID, an owning user, and open files. Configuration, logs, and even kernel state are files in a
single tree. Access is governed by ownership and `rwx` bits. Master these three and Linux stops
being mysterious.

**Long-running programs are services, supervised by `systemd`.** Don't run production processes
with `&` and `nohup` — they die on logout and don't restart on crash. A `systemd` unit starts
your app on boot, restarts it on failure, and streams its logs to `journalctl`. In this stage,
Docker Compose or systemd is what keeps Invoicely alive.

**Run as a non-root user, with least privilege.** `root` can do anything, which is exactly why
your application must not run as it. A dedicated service user that owns only what it needs
contains the blast radius of any bug or breach. `chmod 777` is not a fix; it's removing the
lock because you lost the key.

**Resource limits are real and silent.** Disk, memory, CPU, and file descriptors are finite;
running out doesn't raise an application exception — the process is killed or blocked. Watching
`df`, `free`, and `top` is how you catch the outage that has no stack trace.

## Production Example

**Invoicely** is deployed on a single Ubuntu 24.04 LTS VPS (the full deploy is Chapter 06). At
this stage we operate the box directly: the FastAPI backend runs as a non-root `invoicely`
service user, PostgreSQL and Redis run as their own service users, Nginx fronts the app on
ports 80/443, and everything is supervised so it survives reboots and crashes. The scenario
that grounds this chapter: **the API went down, and you have to find out why with nothing but
an SSH session.**

The engineer logs in and runs the diagnostic loop rather than guessing. `systemctl status
invoicely` shows the service `failed`. `journalctl -u invoicely -n 50` shows the last lines
before it died: `sqlalchemy ... could not connect to server: Connection refused`. So the app
is fine — its dependency is down. `systemctl status postgresql` confirms Postgres is not
running; `journalctl -u postgresql` shows `could not write ... No space left on device`.
`df -h` shows `/` at 100% — an unrotated log file filled the disk, Postgres couldn't write its
WAL and stopped, and the app crashed behind it. The fix is a chain diagnosed in four commands,
not a reboot-and-pray. That loop — *up? → logs? → dependency? → resources?* — is the skill.

## Folder Structure

The Linux filesystem is a single tree; knowing the handful of directories an application
engineer actually touches turns "where is anything" into a map. This is the layout on the
Invoicely server (a standard Filesystem Hierarchy Standard layout):

```
/                                  the single root — all storage is mounted into this one tree
├── etc/                           system + service CONFIGURATION (text files, version them)
│   ├── nginx/                       Nginx config (Chapter 04)
│   ├── systemd/system/              your service units live here → invoicely.service
│   ├── ssh/sshd_config              SSH server config (harden in Stage 9)
│   └── environment, hosts, ...      global env, hostname resolution
├── var/                            VARiable data — things that grow at runtime
│   ├── log/                          system logs (nginx/, plus journald's store)
│   └── lib/                          service state (postgresql/ data dir, docker/)
├── home/
│   └── invoicely/                    the app's non-root service user home
│       └── app/                        the deployed code + .env (Chapter 06)
├── opt/                            optional/third-party app installs (alt to /home)
├── usr/                            installed programs & libraries (usr/bin, usr/local/bin)
├── tmp/                            ephemeral scratch, wiped on reboot — never store state here
├── proc/  sys/                     kernel's live view as files (process info, tunables) — virtual
└── root/                           the root user's home — your app should never live here
```

Why these and not others:

- **`/etc` is configuration, and configuration is code.** Nginx configs, systemd units, and
  SSH settings live here as plain text — which means they belong in version control and change
  review, not hand-edited on the box and forgotten. Treat `/etc` as the server's source code.
- **`/var/log` and `/var/lib` are where the truth and the state live.** Logs (what happened)
  and service data (Postgres's data directory) both grow at runtime — and both are why disks
  fill. `/var` is the first place to look in a disk-space incident.
- **`/home/invoicely` isolates the app under its own user.** The application, its virtualenv or
  container, and its `.env` live under a dedicated non-root user's home, so the app can't read
  the rest of the system and a breach is contained.
- **`/proc` and `/sys` are the kernel as files.** `cat /proc/loadavg`, `/proc/meminfo` — the
  live machine state is readable as files, which is why so many tools are "just" reading them.
- **`/tmp` is a trap for state.** It's wiped on reboot and world-accessible; anything you can't
  afford to lose or expose does not go there.

## Implementation

The "implementation" here is the working command vocabulary — grouped by the six concepts, each
answering a specific operational question. These are the commands you run on Invoicely's server;
learn the *question each answers*, not the flags.

### Processes — "is it running, and what is it doing?"

```bash
ps aux | grep uvicorn          # find the app's processes (user, PID, CPU%, MEM%, command)
top          # or: htop        # live view: what's using CPU/memory right now, sorted
kill 4123                      # ask PID 4123 to terminate (SIGTERM — graceful)
kill -9 4123                   # force-kill (SIGKILL) — last resort; no cleanup
pgrep -af invoicely            # PIDs + full command line matching a pattern
```

The key distinction: `SIGTERM` (default `kill`) asks a process to shut down cleanly — flush,
close connections, exit. `SIGKILL` (`kill -9`) is the kernel yanking it; the process gets no
chance to clean up. Reach for `-9` only when a process is truly stuck, and know that data loss
is possible.

### Files, permissions & ownership — "who can touch this?"

```bash
ls -l app/.env
# -rw------- 1 invoicely invoicely 812 Jul 14 09:20 .env
#  │└┬┘└┬┘└┬┘   └───┬──┘ └───┬──┘
#  │ u   g  o      owner    group        rwx for user / group / other
#  └ file type (- file, d dir, l link)

chmod 600 app/.env             # owner read/write only — correct for a secrets file
chown invoicely:invoicely app/.env   # set owner and group
id invoicely                   # what uid/gid/groups a user has
```

Read `-rw-------` as three triplets — **u**ser, **g**roup, **other** — each `r`(4) `w`(2)
`x`(1). `600` = owner `rw`, group nothing, other nothing: exactly what a `.env` full of
secrets should be, and the reason `chmod 777` (everyone can do everything) on anything is a red
flag. Directories need `x` to be *entered*, not just read. This ownership model is why the app
runs as `invoicely` and can't read `/etc/shadow`.

### Services with systemd — "keep it running, on boot and after a crash"

A `systemd` unit is how a production process is supervised. This is the Invoicely backend as a
native service (the containerized version is Chapter 03; the mechanism is the same idea):

```ini
# /etc/systemd/system/invoicely.service
[Unit]
Description=Invoicely API
After=network.target postgresql.service        # start after the network and DB are up
Requires=postgresql.service

[Service]
User=invoicely                                 # NON-root service user (least privilege)
Group=invoicely
WorkingDirectory=/home/invoicely/app
EnvironmentFile=/home/invoicely/app/.env       # load secrets from a 600 file, not the unit
ExecStart=/home/invoicely/app/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=on-failure                             # auto-restart if it crashes
RestartSec=3
LimitNOFILE=65536                              # raise the file-descriptor ceiling

[Install]
WantedBy=multi-user.target                     # start on boot
```

```bash
sudo systemctl daemon-reload         # after editing a unit file
sudo systemctl enable --now invoicely  # start now AND on every boot
systemctl status invoicely           # is it running? recent log lines, last exit
sudo systemctl restart invoicely     # apply new code/config
journalctl -u invoicely -f           # follow this service's logs live
journalctl -u invoicely --since "1 hour ago" -p err   # errors in the last hour
```

The four properties that make this *production* and `nohup ... &` a toy: it **starts on boot**
(`enable`), **restarts on crash** (`Restart=on-failure`), **runs as a non-root user**
(`User=`), and **captures logs** (`journalctl`) with no redirect gymnastics. `bash &` gives you
none of these.

### Network & ports — "what's listening, and why is it unreachable?"

```bash
ss -tlnp                       # TCP (t) listening (l) sockets, numeric (n), with process (p)
# LISTEN 0 511 127.0.0.1:8000  users:(("uvicorn",pid=4123))   ← app: localhost only (good — Nginx fronts it)
# LISTEN 0 511 0.0.0.0:443     users:(("nginx",pid=980))      ← Nginx: all interfaces (public)
curl -I http://127.0.0.1:8000/health    # test the app locally, bypassing Nginx/firewall
sudo ufw status                # firewall rules: what's allowed in
sudo ufw allow 443/tcp         # open a port to the world (only what must be public)
```

The critical distinction is the bind address: `127.0.0.1:8000` means the app is reachable
**only from the machine itself** — correct, because Nginx (Chapter 04) proxies to it and the
app should never be exposed directly. `0.0.0.0:443` means Nginx listens on **all interfaces**,
i.e. the public internet. Binding your app to `0.0.0.0` by accident is how an unauthenticated
service ends up on the internet. Debugging "the site is down": is the app listening
(`ss`)? does it answer locally (`curl 127.0.0.1`)? is the port open (`ufw`)? — each rules out a
layer.

### Resources — "what's being exhausted?"

```bash
df -h                          # disk free per mount — the #1 silent outage. watch for 100% on /
du -sh /var/log/* | sort -h    # what's eating a full disk (largest last)
free -h                        # memory: used / free / available. if available ≈ 0 → OOM risk
top                            # live CPU + memory by process; %CPU, %MEM, load average
ulimit -n                      # this shell's open-file limit (EMFILE = "too many open files")
journalctl --disk-usage        # how much the journal itself is consuming
```

These have no application error to catch — a full disk stops Postgres, an OOM condition makes
the kernel kill your biggest process, an exhausted FD limit refuses new connections. The app
just "goes down." `df -h` and `free -h` are the first two commands in any unexplained outage.

## Engineering Decisions

**Run the app as a dedicated non-root user.** Create an `invoicely` service user that owns only
the app directory and its files. Root is for administration, never for running the application.
This is the single highest-leverage security decision on the box and it costs nothing.
*Rationale:* least privilege — a bug or RCE in the app is confined to what `invoicely` can
touch, not the whole system.

**Supervise with `systemd` (or a container runtime), never `nohup`/`screen`.** Production
processes must survive reboots and restart on crash, with captured logs. `systemd` gives all
three declaratively. *Rationale:* an unsupervised process is an outage waiting for the next
crash or reboot; "it was running when I left" is not an operations model.

**Keep configuration in `/etc` (or the repo) and version it.** Service units, Nginx configs,
and environment templates are code. Edit them in version control and deploy them, don't
hand-edit on the box. *Rationale:* a server you can rebuild from a repo is recoverable; a
hand-tuned pet server is a single point of unrecoverable failure.

**Load secrets from a `600` `EnvironmentFile`, not the unit or the shell history.** The `.env`
is `chmod 600`, owned by the service user, and referenced by the unit. *Rationale:* secrets in
a world-readable file or in shell history leak; file permissions are the cheapest boundary that
works (managed secrets are Stage 9).

**Bind app services to `127.0.0.1`, expose only the proxy.** The app listens on localhost;
only Nginx binds public interfaces. *Rationale:* the app should never be directly reachable —
that's what puts an unauthenticated internal service on the internet.

**Set resource limits and rotate logs before they bite.** Raise `LimitNOFILE` for
connection-heavy services and ensure log rotation (`logrotate`/journald limits) is configured.
*Rationale:* the most common silent outages are disk-full and FD-exhaustion; both are prevented
by configuration, not heroics.

## Trade-offs

**Native service (systemd) vs container (Docker).** Running the app directly under `systemd` is
simpler with fewer moving parts and no image build; containers (Chapters 02–03) give
reproducibility, dependency isolation, and identical dev/prod environments at the cost of a
build step and a runtime. *When native wins:* a single simple service, a small team, minimal
dependencies. *When containers win:* multiple services, "works on my machine" pain, needing
CI-built artifacts. This stage teaches both; most production SaaS lands on containers, with
`systemd`/the Docker daemon as the supervisor underneath.

**One VPS vs managed platform (PaaS).** Operating your own Linux box is cheaper, fully
controllable, and teaches you the machine; a PaaS (Render, Fly, Railway) hides all of this for
a price and less control. *When the VPS wins:* cost sensitivity, learning, control, specific
needs. *When PaaS wins:* you'd rather not be on-call for the OS. Knowing Linux makes you a
better user of a PaaS too — the abstraction still leaks.

**Least privilege vs convenience.** A non-root user with tight permissions occasionally makes a
task need `sudo` or a `chown`; running everything as root is frictionless right up until the
breach. *The trade is always worth it* — the friction is minutes, the alternative is total
compromise. `chmod 777` trades a permanent security hole for saving one minute now.

**Pet server vs cattle.** A carefully hand-tuned server ("pet") can be perfectly optimized but
is unrecoverable if it dies and undocumented for the next engineer; a reproducible-from-repo
server ("cattle") is rebuildable and reviewable but requires the discipline of scripting
everything. *Prefer cattle* — the whole point of this stage is servers you can recreate.

## Common Mistakes

**Running the application as root.** The app, or its container, runs as `root`, so any code-
execution bug is a full-system compromise and every file it writes is root-owned. *Fix:* a
dedicated non-root service user (`User=invoicely`), owning only the app directory.

**`chmod 777` to fix a permission error.** A "permission denied" is met with `chmod -R 777`,
which doesn't fix ownership — it removes security. *Fix:* diagnose with `ls -l` and `id`, then
`chown` to the right user and set the *minimal* mode (`600` secrets, `644` config, `755`
dirs/binaries).

**Backgrounding a process instead of supervising it.** `nohup uvicorn ... &` or a `screen`
session "runs" the app — until logout, a crash, or a reboot kills it and nothing brings it
back. *Fix:* a `systemd` unit (or a container with a restart policy).

**Ignoring disk and log growth until the disk is full.** Logs accumulate in `/var/log` and the
journal until `/` hits 100% and everything that writes (Postgres, the app) fails with no
obvious cause. *Fix:* configure log rotation and journald size limits; make `df -h` a habit.

**Editing config directly on the box.** Nginx and systemd files are tweaked live and never
committed, so the next deploy or rebuild silently reverts them and no one remembers the change.
*Fix:* config lives in the repo and is deployed; the server is reproducible.

**Debugging by guessing instead of running the loop.** Reaching for `reboot` or restarting
random services instead of asking *up? → listening? → logs? → resources?*. *Fix:* run the
diagnostic loop; let the machine tell you what's wrong.

## AI Mistakes

Assistants recall Linux syntax perfectly but operate without the machine, without the security
context, and without the *why*. Review generated ops commands against these failure modes.

### Claude Code: running services as root and over-permissioning

Asked to "get the app running on the server" or write a Dockerfile/unit, Claude Code frequently
produces something that runs as root and files with broad permissions, because it optimizes for
"it works" and root sidesteps every permission question.

**Detect:** a `systemd` unit with no `User=` (defaults to root); a Dockerfile with no
`USER`instruction; setup scripts full of `sudo` for the app itself; `chmod 777`/`chmod -R 755`
on data or secrets; secrets in a world-readable file.

**Fix:** require least privilege explicitly:

> Run the app as a dedicated non-root user (`User=invoicely` in the unit, a `USER` line in the
> Dockerfile). Give files the minimal mode: `600` for `.env`/secrets, `644` for config, `755`
> for directories. Never `chmod 777`. Justify any `sudo` in the app's runtime.

### GPT: `nohup ... &` where a supervised service is required

Asked how to keep a server process running, GPT-family models often suggest `nohup uvicorn ...
&`, `screen`, or `tmux` — which "work" in the demo but give no restart-on-crash, no start-on-
boot, and no log capture.

**Detect:** `nohup`, trailing `&`, `screen`/`tmux` presented as the way to run a production
service; no `systemd` unit or container restart policy; logs redirected to a file with `>
out.log 2>&1` instead of journald.

**Fix:** require real supervision:

> This needs to survive reboots and restart on crash. Give me a `systemd` unit (with
> `Restart=on-failure`, `User=`, `EnvironmentFile=`, and `WantedBy=multi-user.target`) or a
> container with a restart policy — not `nohup`/`screen`.

### Cursor: commands without the diagnostic reasoning

Editing a runbook or troubleshooting inline, Cursor tends to emit a command that "fixes" the
immediate symptom (`sudo systemctl restart`, `reboot`, `kill -9`) without the question it
answers — encouraging cargo-cult restarts instead of diagnosis, and reaching for `kill -9` or
`reboot` where a graceful action or a root-cause check was needed.

**Detect:** `kill -9` as the first resort; `reboot`/restart-everything as a fix; commands with
no explanation of what they diagnose; a "fix" that doesn't identify which of the six things was
failing.

**Fix:** require diagnosis before action:

> Before restarting anything, run the diagnostic loop and tell me the root cause: `systemctl
> status`/`journalctl` (up? why did it exit?), `ss -tlnp` (listening?), `df -h`/`free -h`
> (resources?). Use `SIGTERM` (plain `kill`/`restart`), not `kill -9`, unless the process is
> truly stuck. `reboot` is not a diagnosis.

## Best Practices

**Run the diagnostic loop, not guesses.** On any "it's down," ask in order: is it up
(`systemctl status`/`ps`), what do the logs say (`journalctl`), is it listening (`ss -tlnp`),
are resources exhausted (`df -h`/`free -h`/`top`). Most incidents fall out in four commands.

**Least privilege everywhere.** A dedicated non-root service user; minimal file modes (`600`
secrets, `644` config, `755` dirs); the app bound to `127.0.0.1`; the firewall opening only
what must be public. Contain the blast radius before you need to.

**Supervise every long-running process.** `systemd` (or a container runtime) with restart-on-
failure, start-on-boot, and captured logs. No `nohup`, no `screen`, no un-restarted processes.

**Treat the server as reproducible.** Config in the repo, deployed — not hand-edited on the box.
You should be able to rebuild the server from version control (Chapter 06 automates this).

**Manage disk and logs proactively.** Configure log rotation and journald size limits; monitor
`df -h`. The disk-full outage is entirely preventable and one of the most common.

**Prefer graceful over forceful.** `systemctl restart` over `kill -9`; `SIGTERM` before
`SIGKILL`; diagnose before you `reboot`. Forceful actions lose data and hide root causes.

## Anti-Patterns

**The Root Application.** Everything runs as root "to avoid permission problems," so every bug
is a full compromise and every file is root-owned. The tell: no `User=`/`USER`, `sudo` in the
app's own runtime.

**The `777` Fix.** Permission errors resolved by `chmod 777` instead of `chown` + minimal mode,
turning a lock problem into a security hole. The tell: `777`/`-R 777` anywhere near data or
secrets.

**The Backgrounded Service.** `nohup ... &` or a `screen` session standing in for supervision —
gone on the next crash or reboot, with nothing to restart it. The tell: no unit file, no restart
policy, logs redirected to a flat file.

**The Pet Server.** A lovingly hand-tuned, undocumented box that no one can rebuild and the next
engineer can't touch. The tell: config edited live, nothing in version control, "don't restart
it, we're not sure it'll come back."

**The Full-Disk Surprise.** Logs and data grow unwatched until `/` hits 100% and the whole
system fails with cryptic write errors. The tell: no log rotation, no journald limits, `df` not
in anyone's routine.

**The Reboot Reflex.** Every problem met with `reboot` or restart-everything, so root causes are
never found and the incident recurs. The tell: "have you tried rebooting it" as the operations
strategy.

## Decision Tree

"The service is down / behaving wrong on the server — what do I actually check?"

```
START: run the diagnostic loop, in order — don't guess, don't reboot.

1. IS IT UP?  systemctl status <svc>   (or ps aux | grep <proc>)
     failed/inactive? → journalctl -u <svc> -n 50   → read the last lines before it died
        "Connection refused" to a dependency?  → check THAT service (step 1 on it)
        "Address already in use"?               → something else holds the port → ss -tlnp
        "Permission denied"?                    → ls -l / id → chown, not chmod 777
     running but wrong? → go to step 2

2. IS IT LISTENING WHERE EXPECTED?  ss -tlnp | grep <port>
     nothing on the port?      → the process isn't binding → back to logs (step 1)
     bound to 127.0.0.1 but you need external? → that's for Nginx to proxy (Ch 04), not direct
     bound to 0.0.0.0 by mistake? → a service is publicly exposed → fix the bind

3. CAN YOU REACH IT LOCALLY?  curl -I http://127.0.0.1:<port>/health
     works locally but not externally? → NETWORK/FIREWALL, not the app → ufw status, Nginx, DNS
     fails locally too?               → the app itself → step 1 logs

4. ARE RESOURCES EXHAUSTED?  df -h ; free -h ; top
     disk at 100%?      → du -sh /var/log/* → rotate/clear logs; this stops Postgres & writes
     memory ≈ 0 / OOM?  → journalctl -k | grep -i oom  → the kernel killed a process
     FD limit / EMFILE? → raise LimitNOFILE in the unit

5. ONLY NOW consider a restart — and only after you know WHY.
     graceful first: systemctl restart <svc>   (SIGTERM), not kill -9
     if you can't say what the root cause was, you haven't finished debugging.
```

## Checklist

### Implementation Checklist

- [ ] The application runs as a dedicated **non-root** service user, owning only its own files.
- [ ] Every long-running process is supervised (`systemd` unit or container restart policy) with
      restart-on-failure and start-on-boot.
- [ ] Secrets live in a `600` `EnvironmentFile` owned by the service user, not in the unit or
      shell history.
- [ ] App services bind `127.0.0.1`; only the reverse proxy binds public interfaces.
- [ ] File modes are minimal (`600` secrets, `644` config, `755` dirs); no `777` anywhere.
- [ ] `LimitNOFILE` is raised for connection-heavy services; log rotation/journald limits are set.

### Architecture Checklist

- [ ] Server configuration (units, Nginx, env templates) lives in the repo and is deployed, not
      hand-edited on the box — the server is reproducible.
- [ ] The firewall (`ufw`) opens only ports that must be public (80/443, SSH).
- [ ] A dependency order is declared (`After=`/`Requires=`) so services start in the right order.
- [ ] Disk/log growth is bounded (rotation + journald `SystemMaxUse`), preventing the full-disk
      outage.

### Code Review Checklist

- [ ] No service or container runs as root (`User=`/`USER` present); watch AI-generated units and
      Dockerfiles.
- [ ] No `nohup`/`screen`/`&` standing in for supervision; no `kill -9`/`reboot` as a default fix.
- [ ] No `chmod 777`; permission fixes use `chown` + minimal mode.
- [ ] No app service bound to `0.0.0.0` that should be localhost-only.
- [ ] Ops steps include the *diagnostic reasoning*, not just commands.

### Deployment Checklist

- [ ] `systemctl enable` is set so services return after a reboot; verify with an actual reboot.
- [ ] `df -h` and `free -h` have headroom; alerting on disk/memory is planned (Chapter 07).
- [ ] `journalctl` shows the service's logs (no lost output to a flat file).
- [ ] SSH is key-only and the firewall is on before the box is exposed (hardening detail in
      Stage 9).

## Exercises

**1. Diagnose an outage with the loop.** On a test VPS running Invoicely, stop PostgreSQL
(`systemctl stop postgresql`) and observe the API fail. Without restarting blindly, use
`systemctl status`, `journalctl`, and `ss` to trace the failure from the app's error back to the
stopped dependency, then fix it. The artifact is a short root-cause writeup naming each command
and what it told you.

**2. Write and harden a `systemd` unit.** Take a plainly-run `uvicorn` process and turn it into a
production unit: non-root `User=`, `EnvironmentFile=` from a `600` file, `Restart=on-failure`,
`After=`/`Requires=` on Postgres, `LimitNOFILE`, and `enable`d on boot. Prove it by killing the
process and confirming `systemd` restarts it, and by rebooting and confirming it returns.

**3. Fill the disk on purpose.** On a throwaway VM, write a large file until `df -h` shows `/`
near 100%, observe how Postgres and the app fail (read the logs — the errors won't say "disk
full" from the app's side), then fix it and configure log rotation/journald limits so it can't
recur. The artifact is the before/after `df -h` and the rotation config.

## Further Reading

- **The Linux `man` pages for `systemd.service`, `journalctl`, `ss`, `chmod`, `ps`** (`man
  systemd.service`, etc.) — the authoritative reference for every command in this chapter; learn
  to read them rather than memorize flags.
- **"The Linux Command Line" by William Shotts** (linuxcommand.org, free) — the best from-zero
  grounding in the filesystem, permissions, processes, and the shell that this chapter compresses.
- **Filesystem Hierarchy Standard (FHS 3.0)** (refspecs.linuxfoundation.org) — the specification
  behind `/etc`, `/var`, `/usr`; explains *why* the tree is laid out as it is.
- **"How Linux Works" by Brian Ward** (No Starch Press) — processes, boot, `systemd`, networking,
  and resources at exactly the operational depth an application engineer needs.
- **Stage 7, Chapter 02 — Docker & Containerization** — the next step: packaging the app so this
  same process/permission/port model runs identically everywhere. Docker is Linux isolation, and
  this chapter is the layer it builds on.
</content>
