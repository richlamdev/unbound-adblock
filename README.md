# Ansible Playbook for unbound-adblock

## Introduction

The is an Ansible playbook implementiation of the unbound-adblock project for OpenBSD, created by Jordan Geoghegan.

[unbound-adblock - The Ultimate DNS Firewall!](https://www.geoghegan.ca/unbound-adblock.html)

The primary objective is to enable an existing OpenBSD system with unbound-adblock.

unbound-adblock is very similar to the [Pi-Hole project](https://pi-hole.net).

## How to use

### Prerequisites

Server:
- Ansible (tested with v2.9.6)
- sshpass
  - notes:
    - sshpass has potential security concerns, and is not a best practice to use
    - preferred practice is to deploy and utilize SSH keys (assuming minimum Ansible requirements are met)

Client:
- OpenBSD (tested with v7.0)
- Python3 package installed, if the unbound-adblock role is deployed independently
- SSH server enabled
  - non-privilege user access
  - root access

### For newly installed OpenBSD server

```git clone https://github.com/richlamdev/unbound-adblock.git```

```cd unbound-adblock```

Edit inventory file at the root of the repo to reflect the hostname and/or IP to have this playbook applied to.

Edit the vars file at role/unbound/vars/main.yml, to appropriately reflect the network device of the server you\
will be deploying to.

```ansible-playbook main.yml -kKu <username>```

Enter the <username> password when prompted:

**SSH password:**


Enter the root password when prompted:

**BECOME password[defaults to SSH password]:**

*NOTE: This playbook was designed for standard OpenBSD deployment.  OpenBSD, by convention, does not have\
sudo installed, consequently, privilege escalation is achieved via su, as opposed to sudo.  Therefore the connection\
is established via non-privileged user by SSH, followed by the root password for privilege escalation.  See below\
considerations section for potential implementation options.*

### For existing OpenBSD server

The steps are essentially the same as above, however, in addition, edit (comment out) the unbound role
in the main.yml file at the root of the repo, prior to running the ansible-playbook command.


### Brief explanation of each role

#### Base role

Checks presence of Python 3, will install install Python 3, if it is not already installed.
This role is idempotent.

#### Unbound role

Installs unbound recursive DNS server with DNSSEC enabled.  This role is not idempotent when\
executed with the unbound-adblock role.

#### Unbound Adblock role

Installs unblock-adblock per the instructions here:
https://www.geoghegan.ca/pub/unbound-adblock/latest/install/openbsd.txt
This role is not idempotent when run in with the unbound role above.  This role could be modified to\
be idempotent by amalgamating the unbound and unbound-adblock role.  This was not implemented as\
unbound configurations are subject to your own requirement/use case/environment.

## Notes, General Information & Considerations

1. Aside from the objective to deploy unbound-adblock, a secondary goal was to minimize installation of additional software.\
The intention was to remain aligned with OpenBSD principle's of security first. (less software, less potential for vulnerabilities)

2. As mentioned above, sudo is not installed or assumed to be installed for the execution of this playbook.  Privilege\
escalation is achieved via su.  During testing, doas privilege escalation via Ansible did not work.\
(I was unsuccessful in my attempts.)

3. Python is a requirement for Ansible.  (to use the full potential of modules, which will enable idempotency)
Refer to information provided under base role above.

4. If you considering to use this playbook as a starting point to deploy an OpenBSD server, there are\
several features and services you should consider.  (pf firewall, ntp, syslog, dhcp etc)
