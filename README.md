# Ansible Playbook for unbound-adblock

## Introduction

The is an Ansible playbook implementiation of the unbound-adblock project for OpenBSD, created by Jordan Geoghegan.

[unbound-adblock - The Ultimate DNS Firewall!](https://www.geoghegan.ca/unbound-adblock.html)

Thank you, Jordan!

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
    - to install sshpass on Debian based Linux ```sudo apt install sshpass```

Client:
- OpenBSD (tested with v7.0)
- Python3, if the unbound-adblock role is deployed independent of the base role here
  - the base role will check for Python 3, if it's not installed, it will proceed to install it
- SSH server enabled
  - non-privilege user access
  - root access

### For newly installed OpenBSD server

```git clone https://github.com/richlamdev/unbound-adblock.git```

```cd unbound-adblock```

Edit inventory file at the root of the repo to reflect the hostname and/or IP to have this playbook applied to.

Edit the vars file at role/unbound/vars/main.yml, to appropriately reflect the network device of the server you\
will be deploying to.

```ansible-playbook main.yml -bkKu <username>```

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

A great resource for unbound configuration is here:

[Unbound DNS Tutorial](https://calomel.org/unbound_dns.html)


#### Unbound Adblock role

Installs unblock-adblock per the instructions here:
https://www.geoghegan.ca/pub/unbound-adblock/latest/install/openbsd.txt
This role is not idempotent when run in with the unbound role above.  This role could be modified to\
be idempotent by amalgamating the unbound and unbound-adblock role.  This was not implemented as\
unbound configurations are subject to your own requirements and/or use case.


## Notes, General Information & Considerations

1. Aside from the objective to deploy unbound-adblock, a secondary goal was to minimize installation of additional software.\
The intention was to remain aligned with OpenBSD principle's of security first. (less software, less potential for vulnerabilities)

2. As mentioned above, sudo is not installed or assumed to be installed for the execution of this playbook.  Privilege\
escalation is achieved via su.  During testing, doas privilege escalation via Ansible did not work.\
(I was unsuccessful in my attempts.)

3. Python is a requirement for Ansible.  (to use the full potential of modules, which will enable idempotency)
Refer to information provided under base role above.

4. If you are considering to use this playbook as a starting point to deploy an OpenBSD server, there are\
several features and services you should consider.  (pf firewall, ntp, syslog, dhcp etc).  In addition, review the DNS servers\
configured to send DNS over TLS queries in the template file, main.yml located at unbound-adblock/rols/unbound/templates/.

5. This [Vagrant file](https://github.com/richlamdev/vagrant-files/blob/main/openbsd/Vagrantfile) works with this repo to start an OpenBSD virtual machine for testing.
This Vagrant file can be amended to create a Ubuntu 20.04 virtual machine on the same network (subnet) to test DNS queries (allows/blocks) via the configured OpenBSD test virtual machine.
Uncomment the bottom part of the Vagrant file.
The setup.sh forces the root password of each virtual machine to be password1. (obviously not secure, but for the purposes of testing and life of these virtual machines, not so much an issue)

Naturally, you will need Vagrant and VirtualBox, information beyond the scope of this repo.
