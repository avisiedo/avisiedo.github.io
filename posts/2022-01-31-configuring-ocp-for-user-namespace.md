---
title: Configuring ocp for user namespace
published_date: "2022-01-31 10:45:58 +0100"
layout: default.liquid
is_draft: false
---
Preparing an OpenShift cluster for using user namespaces involves
several steps and hands-over. To simplify the process we are using
some configurations at [freeipa-kustomize](https://github.com/freeipa/freeipa-kustomize)
that make easier that task.

**Pre-requisites**:

- A 4.9+ OpenShift cluster.
- You are logged in the cluster and you have cluster-admin privileges.
- runc and cri-o rpm patched packages. Credits and thanks to [Fraser Tweedale](https://frasertweedale.github.io/blog-redhat/).
  - [runc-1.0.3-992.rhaos4.10.el8.x86_64.rpm](https://ftweedal.fedorapeople.org/runc-1.0.3-992.rhaos4.10.el8.x86_64.rpm).
  - [cri-o-1.23.0-990.rhaos4.10.git8c7713a.el8.x86_64.rpm](https://ftweedal.fedorapeople.org/cri-o-1.23.0-990.rhaos4.10.git8c7713a.el8.x86_64.rpm).

> **Out of scope**: Build the runc and cri-o rpm packages.

## Setting the configuration node

- Clone freeipa-kustomize repository:

  ```sh
  git clone https://github.com/freeipa/freeipa-kustomize.git
  ```

- Retrieve the machine config pools by:

  ```sh
  oc get mcp
  ```

- Set the POOL environment variables with the names of the machine config pool
  that are going to be configured:

  ```sh
  export POOL="worker"
  ```

  if you want to specify more than one:

  ```sh
  export POOL="worker master"
  ```

- Set the list of RPMs by:

  ```sh
  export RPM_PACKAGES="https://ftweedal.fedorapeople.org/runc-1.0.3-992.rhaos4.10.el8.x86_64.rpm https://ftweedal.fedorapeople.org/cri-o-1.23.0-990.rhaos4.10.git8c7713a.el8.x86_64.rpm"
  ```

  > Note that this RPM will become obsolete in the future; and starting
  > at runc v1.1, the runc package could not be needed to be updated.

- Now we just run:

  ```sh
  make -C config/static/nodes/userns configure
  kustomize build config/static/nodes/userns | oc create -f -
  ```

- Finally await the node state is updated by:

  ```sh
  oc wait mcp/worker --for condition=updated --timeout=-1s
  ```

> It will take a few minutes (5-10minutes) as the configuration is applied node by node,
> evacuate the node, restart the node, and make it available. This
> process is repeated for all impacted nodes. Eventually all the nodes will get a
> Ready state and they could be used.

## How is it structured?

The main overlay at `config/static/nodes/userns` is a composition of smaller
ones, that are divided on:

- `config/static/nodes/cgroup-v2`: Configure cgroup-v2 into the node, enabling
  to mount cgroup v2 filessytem into the node.
- `config/static/nodes/userns-subid`: Configure the necessary subid for the
  user namespaces. Different files can be found at
  `config/static/nodes/userns-subid/files` to spicify the subuid and subgid
  information.
  - `99-crio-userns.conf`: Enable the `io.kubernates.cri-o.userns-mode` annotation
    into the PodSpec.
  - `subuid` and `subgid`: Configure the subordinate ids to be used by the user namespace.
- `config/static/nodes/rpm-overrides`: This configuration handle the RPM
  package installation. This is made by creating a systemd unit, and executing
  the command that install the RPM package. It is generated a resource for each
  RPM and POOL. The package installation is checked before launch the RPM
  command, so that future reboots does not try to install the RPM package
  again. Here this is used for custom runc and cri-o rpm packages, but this
  configuration could work for any RPM that we want to quickly test into our
  OCP **development** cluster.

## Checking that the configuration was applied

Here you will find several commands that are executed from the node. If you
are using CodeReadyContainers you can directly use a ssh command such as:

```sh
ssh -i ~/.crc/machines/crc/id_ecdsa core@192.168.130.11
```

> This could be helpful when the KAS communication is not available.

Or you can just open a terminal into the node and run the command there by:

```sh
# Retrieve node list by:
oc get nodes
# Open the terminal by:
oc debug node/NODE
chroot /host
# Now run your commands here
```

- For the RPM packages check from the node:

  ```sh
  runc --version
  ```

  ```raw
  runc version 1.0.3
  spec: 1.0.2-dev
  go: go1.17.2
  libseccomp: 2.5.1
  ```

  ```sh
  # If you are using code ready containers, you can directly do the below
  ssh -i ~/.crc/machines/crc/id_ecdsa core@192.168.130.11 journalctl -u install-runc.service
  # Or using the oc adm command
  oc adm node-logs -u install-runc.service NODE
  ```

  ```raw
  -- Logs begin at Sat 2021-12-11 13:38:56 UTC, end at Wed 2022-01-26 07:12:23 UTC. --
  Jan 26 06:50:13 crc-hsl9k-master-0 bash[1658]: package runc-1.0.3-992.rhaos4.10.el8.x86_64 is not installed
  Jan 26 06:50:13 crc-hsl9k-master-0 systemd[1]: Started Install custom runc.
  Jan 26 06:50:14 crc-hsl9k-master-0 bash[1658]: Downloading 'https://ftweedal.fedorapeople.org/runc-1.0.3-992.rhaos4.10.el8.x86_64.rpm'... done!
  Jan 26 06:50:16 crc-hsl9k-master-0 bash[1658]: Checking out tree 26d80bc...done
  Jan 26 06:50:16 crc-hsl9k-master-0 bash[1658]: No enabled rpm-md repositories.
  Jan 26 06:50:16 crc-hsl9k-master-0 bash[1658]: Importing rpm-md...done
  Jan 26 06:50:16 crc-hsl9k-master-0 bash[1658]: Resolving dependencies...done
  Jan 26 06:50:16 crc-hsl9k-master-0 bash[1658]: Applying 1 override and 5 overlays
  Jan 26 06:50:16 crc-hsl9k-master-0 bash[1658]: Processing packages...done
  Jan 26 06:50:16 crc-hsl9k-master-0 bash[1658]: Running pre scripts...done
  Jan 26 06:50:16 crc-hsl9k-master-0 bash[1658]: Running post scripts...done
  Jan 26 06:50:17 crc-hsl9k-master-0 bash[1658]: Running posttrans scripts...done
  Jan 26 06:50:17 crc-hsl9k-master-0 bash[1658]: Writing rpmdb...done
  Jan 26 06:50:18 crc-hsl9k-master-0 bash[1658]: Writing OSTree commit...done
  Jan 26 06:50:19 crc-hsl9k-master-0 bash[1658]: Staging deployment...done
  Jan 26 06:50:20 crc-hsl9k-master-0 systemd[1]: Stopping Install custom runc...
  Jan 26 06:50:20 crc-hsl9k-master-0 systemd[1]: install-runc.service: Succeeded.
  Jan 26 06:50:20 crc-hsl9k-master-0 systemd[1]: Stopped Install custom runc.
  Jan 26 06:50:20 crc-hsl9k-master-0 systemd[1]: install-runc.service: Consumed 94ms CPU time
  -- Reboot --
  Jan 26 06:51:10 crc-hsl9k-master-0 bash[1656]: runc-1.0.3-992.rhaos4.10.el8.x86_64
  Jan 26 06:51:09 crc-hsl9k-master-0 systemd[1]: Started Install custom runc.
  Jan 26 06:51:09 crc-hsl9k-master-0 systemd[1]: install-runc.service: Succeeded.
  Jan 26 06:51:09 crc-hsl9k-master-0 systemd[1]: install-runc.service: Consumed 11ms CPU time
  ```

- For the cgroup2, run the below from the node:

  ```sh
  mount | grep cgroup2
  ```

  ```raw
  cgroup2 on /sys/fs/cgroup type cgroup2 (rw,nosuid,nodev,noexec,relatime,seclabel)
  cgroup on /var/lib/containers/storage/overlay/1ec73edf3e99a0772aaab2ba0f27110bb879a9fe86f607acc9de822489a4a9e1/merged/sys/fs/cgroup type cgroup2 (rw,nosuid,nodev,noexec,relatime,seclabel)
  ```

- For the kernelarguments, run the below from the node:

  ```sh
  # check kernel args in the node boot
  cat /proc/cmdline
  ```

  ```raw
  BOOT_IMAGE=(hd0,gpt3)/ostree/rhcos-36fd944867b0e491991a65f6f3b7209c937fe3bd7cdbd855c7c5d5a7070ce570/vmlinuz-4.18.0-305.28.1.el8_4.x86_64 random.trust_cpu=on console=tty0 console=ttyS0,115200n8 ignition.platform.id=qemu ostree=/ostree/boot.1/rhcos/36fd944867b0e491991a65f6f3b7209c937fe3bd7cdbd855c7c5d5a7070ce570/0 root=UUID=91ba4914-fd2b-4a7c-b498-28585a80a40e rw rootflags=prjquota systemd.unified_cgroup_hierarchy=1 cgroup_no_v1=all psi=1
  ```

- For the subid configuration we run the below from the node:

  ```sh
  cat /etc/subuid
  cat /etc/subgid
  ```

  ```raw
  core:100000:65536
  containers:200000:268435456
  ```

  ```raw
  core:100000:65536
  containers:200000:268435456
  ```

  And we can observe that entries for conteinrs user and group exists too:

  ```sh
  getent passwd containers
  getent group containers
  ```

  ```raw
  containers:x:1001:995:User for housing the sub ID range for containers:/var/home/containers:/sbin/nologin
  ```

  ```raw
  containers:x:995:
  ```

- For the cri-o configuration we run the below from the node:

  ```sh
  cat /etc/crio/crio.conf.d/99-crio-userns.conf
  ```

  ```raw
  # https://github.com/cri-o/cri-o/blob/main/docs/crio.conf.5.md#crioruntimeruntimes-table
  [crio.runtime.runtimes.runc]
  allowed_annotations=["io.kubernetes.cri-o.userns-mode"]
  ```

  Now we can use the annotation below to enable user namespaces for a particular Pod:

  ```yaml
  apiVersion: v1
  kind: Pod
  metadata:
    annotations:
      io.kubernetes.cri-o.userns-mode: "auto:size=65536"
  ```

## Wrap up

With this configuration we can quickly set up our OCP cluster to quickly
experiment with and investigate user namespace.

## References

- [Fraser's blog - Demo: namespaced systemd workloads on OpenShift](https://frasertweedale.github.io/blog-redhat/posts/2021-07-22-openshift-systemd-workload-demo.html).
