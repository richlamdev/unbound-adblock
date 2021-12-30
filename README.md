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
    - preferred practice is to deploy SSH keys

Client:
- OpenBSD (test with v7.0)


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

The steps are essentially the same as above, however, in addition, edit (comment out) the base and unbound\
role in the main.yml file at the root of the repo, prior to running the ansible-playbook command.


