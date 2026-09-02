# Route Ansible's privilege escalation at classic sudo, not the system default

Ubuntu 26.04 points `/usr/bin/sudo` at `sudo-rs`, which treats a caller-supplied
`-p` prompt as untrusted: rather than displaying it, it echoes it inside a
`[sudo: ...]` annotation and prompts with its own generic `Password:`. Ansible's
become plugin waits for the exact key-tagged prompt it asked for, never sees it,
and every `make apply` dies with "Timed out waiting for become success or become
password prompt" — with a correct password, and with sudo sitting there ready to
accept it. So `make apply` passes `-e ansible_become_exe=/usr/bin/sudo.ws`,
pointing Ansible at the classic implementation Ubuntu keeps installed alongside,
when that binary exists.

## Considered Options

**Switch the system alternative** (`update-alternatives --set sudo
/usr/bin/sudo.ws`) — rejected. It changes privilege escalation for every program
on the machine to work around one program's prompt parsing, it is machine state
this repo would then need to converge and assert, and it fights the direction the
distribution has chosen rather than sidestepping it for the one caller affected.

**Wait for Ansible to handle sudo-rs** — rejected as the only measure. It is the
right long-term fix and this override should be deleted when it lands, but it
left the repo unusable on a current Ubuntu in the meantime.

## Consequences

The override is conditional on `sudo.ws` being present, so it is a no-op on any
machine without the split and does not need removing to run elsewhere. It also
means CI does **not** exercise this path — GitHub runners have passwordless sudo,
so no prompt is ever parsed — which is why `make doctor` checks the sudo
implementation directly instead.
