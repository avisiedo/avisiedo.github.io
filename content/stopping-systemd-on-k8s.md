Title: Stopping systemd workloads in Openshift
Date: 2021-11-28 12:00
Category: kubernetes

# Overview

Are you using systemd workloads? then this article could be of your interest.
Along this article we are going to see how the workloads based on systemd
could be stopped gracefully on kubernetes.

To show what we want to transmit into this article, we are going to do
a hands-on activities by using a simple systemd workload which run an nginx
service; we will see the differences between using the workload in a container
and using the workload in kubernetes. Finally we will see how to overcome the
situation in kubernetes by using container lifecycle hooks.

We are going to use `podman` and `openshift` for this article.

**Prerequisites**

- [Podman](https://podman.io/) is installed into your environment.
- [Openshift client](https://docs.openshift.com/container-platform/4.9/cli_reference/openshift_cli/getting-started-cli.html#installing-openshift-cli) is installed into your environment.
- You have access to an Openshift cluster.

> You can install a SNO by using:
>
> - [kcli](https://github.com/karmab/kcli).
> - [Code Ready Containers](https://github.com/code-ready/crc).

# Defining the workload

We are going to use the following simple Dockerfile to build our workload.

```Dockerfile
FROM quay.io/fedora/fedora:35
RUN dnf -y install procps nginx \
    && dnf clean all \
    && systemctl enable nginx
EXPOSE 80
# https://docs.docker.com/engine/reference/builder/#stopsignal
# https://www.freedesktop.org/software/systemd/man/systemd.html#SIGRTMIN+3
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/sbin/init"]
```

> STOPSIGNAL instruction is not needed by podman as it detects that
> the signal to be sent should be SIGRTMIN+3 when `podman stop` is
> executed.

Now we build the container workload by:

```shell
export IMG="quay.io/avisied0/demos:stopping-systemd"
podman build -t "${IMG}" -f Dockerfile .
```

# Runnning container with podman

Firstly, let's see what happens with the workload when running with podman or
docker:

```shell
CONTAINER_ID=$( podman run -it -d "${IMG}" )
podman logs --follow "${CONTAINER_ID}" &
podman stop "${CONTAINER_ID}"
```

And we get a result like the below:

```raw
[  OK  ] Removed slice Slice /system/getty.
[  OK  ] Removed slice Slice /system/modprobe.
[  OK  ] Stopped target Graphical Interface.
[  OK  ] Stopped target Multi-User System.
[  OK  ] Stopped target Login Prompts.
[  OK  ] Stopped target Timer Units.
[  OK  ] Stopped dnf makecache --timer.
[  OK  ] Stopped Daily rotation of log files.
[  OK  ] Stopped Daily Cleanup of Temporary Directories.
.
.
.
[  OK  ] Stopped target Swaps.
[  OK  ] Reached target System Shutdown.
[  OK  ] Reached target Unmount All Filesystems.
[  OK  ] Reached target Late Shutdown Services.
         Starting System Halt...
Sending SIGTERM to remaining processes...
Sending SIGKILL to remaining processes...
All filesystems, swaps, loop devices, MD devices and DM devices detached.
Halting system.
Exiting container.

[1]+  Done                    podman logs --follow "${CONTAINER_ID}"
```

# What about Openshift?

Let's try now our workload into Openshift; you will need an Openshift cluster
or a Single Node Openshift (you can get one by using
[kcli](https://github.com/karmab/kcli) or
[Code Ready Containers](https://github.com/code-ready/crc)).

- Push the image to your image registry:

```shell
podman push "${IMG}"
```

> Check that the repository is public for pulling the image.

- Access your cluster as a cluster admin and create a new project:.

```shell
oc login -u kubeadmin https://api.crc.testing:6443
oc new-project stopping-systemd
```

- Create a serviceaccount with the necessary permissions for creating and
  running the workload; this is, edit role and anyuid
  SecurityContextConstraint:

```raw
oc create serviceaccount runasanyuid
oc adm policy add-scc-to-user anyuid -z runasanyuid --as system:admin
oc adm policy add-role-to-user edit -z runasanyuid --as system:admin
```

- Create the pod.yaml file as the below:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: systemd-nginx
  labels:
    app: nginx
spec:
  serviceAccount: runasanyuid
  containers:
  - name: nginx
    image: quay.io/avisied0/demos:stopping-systemd
    imagePullPolicy: Always
    command: ["/sbin/init"]
    tty: true
    privileged: false
```

- Create the workload into our cluster by using the above serviceaccount:

```shell
oc create -f pod.yaml --as=runasanyuid
oc get all
```

- Print out and follow the logs in the background.

```shell
oc logs pod/systemd-nginx -f &
```

- Try to stop the workload.

```shell
oc delete -f pod.yaml
```

We get something like the below into the logs, but systemd and the pod is
not stopped after a while:

```raw
pod "systemd-nginx" deleted
systemd-nginx login: systemd v249.7-2.fc35 running in system mode (+PAM +AUDIT +SELINUX -APPARMOR +IMA +SMACK +SECCOMP +GCRYPT +GNUTLS +OPENSSL +ACL +BLKID +CURL +ELFUTILS +FIDO2 +IDN2 -IDN +IPTC +KMOD +LIBCRYPTSETUP +LIBFDISK +PCRE2 +PWQUALITY +P11KIT +QRENCODE +BZIP2 +LZ4 +XZ +ZLIB +ZSTD +XKBCOMMON +UTMP +SYSVINIT default-hierarchy=unified)
Detected virtualization podman.
Detected architecture x86-64.
```

We can see that systemd does not begin the stop sequence as in the case of the
container; this is because kubernetes does not passthrough the STOPSIGNAL
instruction that is found into the Dockerfile. For fix this situation we will
use the [container lifecycle hooks](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/),
and we will explicitely send the SIGRTMIN+3 to the PID 1 (systemd).

- Update the `pod.yaml` file with the content below:

```shell
apiVersion: v1
kind: Pod
metadata:
  name: systemd-nginx
  labels:
    app: nginx
spec:
  serviceAccount: runasanyuid
  containers:
  - name: nginx
    image: quay.io/avisied0/demos:stopping-systemd
    imagePullPolicy: Always
    command: ["/sbin/init"]
    tty: true
    privileged: false
    lifecycle:  # (1)
      preStop:  # (2)
        exec:   # (3)
          command: ["kill", "-RTMIN+3", "1"]   # (4)
```

  1. The lifecycle hooks for that container.
  2. Indicate that will be called before stopping the container.
  3. It will be an exec command.
  4. The command to be executed; the command should exist inside the container.

- Create the pod again:

```shell
oc create -f pod.yaml --as=runasanyuid
```

- Print out and follow the logs in the background:

```shell
oc logs pod/systemd-nginx -f &
```

- Now we delete the pod:

```shell
oc delete -f pod.yaml
```

And finally what we get immeditalty is the below:

```raw
pod "systemd-nginx" deleted
systemd-nginx login: [  OK  ] Removed slice Slice /system/getty.
[  OK  ] Removed slice Slice /system/modprobe.
[  OK  ] Stopped target Graphical Interface.
[  OK  ] Stopped target Multi-User System.
[  OK  ] Stopped target Login Prompts.
[  OK  ] Stopped target Timer Units.
[  OK  ] Stopped dnf makecache --timer.
[  OK  ] Stopped Daily rotation of log files.
[  OK  ] Stopped Daily Cleanup of Temporary Directories.
[  OK  ] Closed Process Core Dump Socket.
         Stopping Console Getty...
         Stopping The nginx HTTP and reverse proxy server...
         Stopping User Login Management...
[  OK  ] Stopped Console Getty.
         Stopping Permit User Sessions...
[  OK  ] Stopped User Login Management.
[  OK  ] Stopped Permit User Sessions.
systemd v249.7-2.fc35 running in system mode (+PAM +AUDIT +SELINUX -APPARMOR +IMA +SMACK +SECCOMP +GCRYPT +GNUTLS +OPENSSL +ACL +BLKID +CURL +ELFUTILS +FIDO2 +IDN2 -IDN +IPTC +KMOD +LIBCRYPTSETUP +LIBFDISK +PCRE2 +PWQUALITY +P11KIT +QRENCODE +BZIP2 +LZ4 +XZ +ZLIB +ZSTD +XKBCOMMON +UTMP +SYSVINIT default-hierarchy=unified)
Detected virtualization podman.
Detected architecture x86-64.
[  OK  ] Stopped The nginx HTTP and reverse proxy server.
[  OK  ] Stopped target Network is Online.
[  OK  ] Stopped target Host and Network Name Lookups.
[  OK  ] Stopped target Remote File Systems.
         Stopping Home Area Activation...
         Stopping Network Name Resolution...
[  OK  ] Stopped Network Name Resolution.
[  OK  ] Stopped Home Area Activation.
         Stopping Home Area Manager...
[  OK  ] Stopped Home Area Manager.
[  OK  ] Stopped target Basic System.
[  OK  ] Stopped target Path Units.
[  OK  ] Stopped Dispatch Password …ts to Console Directory Watch.
[  OK  ] Stopped Forward Password R…uests to Wall Directory Watch.
[  OK  ] Stopped target Slice Units.
[  OK  ] Removed slice User and Session Slice.
[  OK  ] Stopped target Socket Units.
         Stopping D-Bus System Message Bus...
[  OK  ] Stopped D-Bus System Message Bus.
[  OK  ] Closed D-Bus System Message Bus Socket.
[  OK  ] Stopped target System Initialization.
[  OK  ] Stopped target Local Verity Protected Volumes.
[  OK  ] Stopped Update is Completed.
[  OK  ] Stopped Rebuild Dynamic Linker Cache.
[  OK  ] Stopped Rebuild Journal Catalog.
         Stopping Record System Boot/Shutdown in UTMP...
[  OK  ] Stopped Record System Boot/Shutdown in UTMP.
[  OK  ] Stopped Create Volatile Files and Directories.
[  OK  ] Stopped target Local File Systems.
         Unmounting /etc/hostname...
         Unmounting /etc/hosts...
         Unmounting /etc/resolv.conf...
         Unmounting /run/lock...
         Unmounting /run/secrets/kubernetes.io/serviceaccount...
         Unmounting Temporary Directory /tmp...
         Unmounting /var/log/journal...
[  OK  ] Stopped Create System Users.
[FAILED] Failed unmounting /etc/hosts.
[FAILED] Failed unmounting /run/lock.
[FAILED] Failed unmounting /run/sec…/kubernetes.io/serviceaccount.
         Unmounting /run/secrets...
[FAILED] Failed unmounting /etc/resolv.conf.
[FAILED] Failed unmounting Temporary Directory /tmp.
[FAILED] Failed unmounting /var/log/journal.
[FAILED] Failed unmounting /etc/hostname.
[FAILED] Failed unmounting /run/secrets.
[  OK  ] Stopped target Swaps.
[  OK  ] Reached target System Shutdown.
[  OK  ] Reached target Unmount All Filesystems.
[  OK  ] Reached target Late Shutdown Services.
         Starting System Halt...
Sending SIGTERM to remaining processes...
Sending SIGKILL to remaining processes...
All filesystems, swaps, loop devices, MD devices and DM devices detached.
Halting system.
Exiting container.
```

# Wrap up

In this article we have seen that:

- systemd workloads use SIGRTMIN+3 for stopping the workload gracefully.
- Kubernetes does not passthrough the STOPSIGNAL instruction from Dockerfile
  to the container definition.
- We can use a container lifecycle hook for the ones that could require it to
  interact with the workload before stop the container, and for this specific
  scenario, to send the SIGRTMIN+3 signal to PID 1 (systemd). This
  requires the binary inside the container.

# References

- [Systemd SIGRTMIN+3](https://www.freedesktop.org/software/systemd/man/systemd.html#SIGRTMIN+3).
- [Dockerfile - STOPSIGNAL](https://docs.docker.com/engine/reference/builder/#stopsignal).
- [Container Lifecycle Hooks](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/).
- [Attach Handlers to Container Lifecycle Events](https://kubernetes.io/docs/tasks/configure-pod-container/attach-handler-lifecycle-event/).
