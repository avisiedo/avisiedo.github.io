---
title: Stopping systemd workloads in Openshift
published_date: 2021-11-29 17:00:00 +0100
layout: default.liquid
is_draft: false
categories: ["kubernetes"]
tags: ["kubernetes", "openshift", "cri-o", "sigstop"]
---
Are you using systemd workloads? Then this article could be of interest.
In this article we are going to see how workloads based on systemd
can be stopped gracefully on Openshift.

We are going to do hands-on activities, using a simple systemd workload
which runs an nginx service. We will see the differences between using the
workload in Podman and using the workload in Openshift. Finally we will see
how to overcome the limitation in Openshift by using container lifecycle hooks.

**Prerequisites**

- [Podman](https://podman.io/) is installed in your environment.
- [OpenShift client](https://docs.openshift.com/container-platform/4.9/cli_reference/openshift_cli/getting-started-cli.html#installing-openshift-cli) is installed into your environment.
- You have access to an OpenShift cluster.

> You can install a single node OpenShift using
> [kcli](https://github.com/karmab/kcli) or
> [Code Ready Containers](https://github.com/code-ready/crc).

**Updates**:

- This is happening in Openshift but it will be fixed in 4.10 (verified on
  Openshift 4.10.0-ci-20220107).
- Here is the change at cri-o that fix this situation:
  https://github.com/cri-o/cri-o/pull/5366

## Defining the workload

We are going to use the following simple `Dockerfile.stopsignal-systemd` Dockerfile to build our workload.

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

> The `STOPSIGNAL` instruction is not needed by podman as it detects that
> the signal to be sent by `podman stop` should be `SIGRTMIN+3`,
> because the container process is systemd.

Now we build:

```sh
export IMG="quay.io/avisied0/demos:stopsignal-systemd"
podman build -t "${IMG}" -f Dockerfile.stopsignal-systemd .
```

## Runnning container with podman

Firstly, let's see what happens with the workload when running with podman or
docker:

```sh
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

## What about OpenShift?

Let's try now our workload on OpenShift; you will need an OpenShift cluster
or a single node OpenShift (you can get one by using
[kcli](https://github.com/karmab/kcli) or
[Code Ready Containers](https://github.com/code-ready/crc)).

- Push the image to your image registry:

  ```sh
  # Previously IMG was defined as below:
  # export IMG="quay.io/avisied0/demos:stopsignal-systemd"
  podman push "${IMG}"
  ```

> Ensure the repository is public so that the cluster can pull
> the image.

- Access your cluster as a cluster admin and create a new project:

  ```sh
  oc login -u kubeadmin https://api.crc.testing:6443
  oc new-project stopsignal
  ```

- Create a serviceaccount with the necessary permissions for creating and
  running the workload; this is, edit role and anyuid
  SecurityContextConstraint:

  ```sh
  oc create serviceaccount runasanyuid
  oc adm policy add-scc-to-user anyuid -z runasanyuid --as system:admin
  oc adm policy add-role-to-user edit -z runasanyuid --as system:admin
  ```

- Create the Pod from the following `pod-stopsignal-systemd.yaml` file:

  ```yaml
  apiVersion: v1
  kind: Pod
  metadata:
    name: stopsignal-systemd
    labels:
      app: nginx
  spec:
    serviceAccountName: runasanyuid
    automountServiceAccountToken: false
    containers:
    - name: nginx
      image: quay.io/avisied0/demos:stopsignal-systemd
      imagePullPolicy: Always
      command: ["/sbin/init"]
      tty: true
      privileged: false
  ```

- Create the workload using the new serviceaccount:

  ```sh
  oc create -f pod-stopsignal-systemd.yaml --as system:serviceaccount:stopsignal:runasanyuid
  oc get all
  ```

- Print out and follow the logs in the background.

  ```sh
  oc logs pod/stopsignal-systemd -f --as system:serviceaccount:stopsignal:runasanyuid &
  ```

- Try to stop the workload.

  ```sh
  oc delete -f pod-stopsignal-systemd.yaml --as system:serviceaccount:stopsignal:runasanyuid
  ```

We get something like the below in the log output, but systemd and
the pod are still running:

```raw
pod "systemd-nginx" deleted
systemd-nginx login: systemd v249.7-2.fc35 running in system mode (+PAM +AUDIT +SELINUX -APPARMOR +IMA +SMACK +SECCOMP +GCRYPT +GNUTLS +OPENSSL +ACL +BLKID +CURL +ELFUTILS +FIDO2 +IDN2 -IDN +IPTC +KMOD +LIBCRYPTSETUP +LIBFDISK +PCRE2 +PWQUALITY +P11KIT +QRENCODE +BZIP2 +LZ4 +XZ +ZLIB +ZSTD +XKBCOMMON +UTMP +SYSVINIT default-hierarchy=unified)
Detected virtualization podman.
Detected architecture x86-64.
```

We can see that systemd does not begin the stop sequence as was the
case with podman.  This is because Openshift did not translate the
`STOPSIGNAL` instruction specified in the Dockerfile (this will be fixed
at Openshift 4.10). To work around this situation we will
use [container lifecycle hooks](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/),
to explicitly send `SIGRTMIN+3` to PID 1 (systemd).

## Trying more isolated

Let's see if this happens only for `SIGRTMIN+3` or for any signal
specified via the `STOPSIGNAL` instruction. To investigate that, we
will use the following `Dockerfile.stopsignal-demo` Dockerfile:

```Dockerfile
FROM quay.io/fedora/fedora:35
COPY demo-signal.sh /demo-signal.sh
RUN chmod a+x /demo-signal.sh
STOPSIGNAL SIGINT
CMD ["/demo-signal.sh"]
```

The `demo-signal.sh` should have execute permission. The content is:

```sh
#!/bin/bash

function trap_signal {
  local signal="$1"
  echo -e "\nExiting by ${signal}" >&2
  exit 0
}

for signal in SIGINT SIGTERM SIGUSR1 "SIGRTMIN+3"
do
  trap "trap_signal '${signal}'" "${signal}"
done

while true; do
    echo -n "."
    sleep 1
done
```

> Update: Script updated based on PR at:
  https://github.com/avisiedo/freeipa-kustomize/blob/idmocp-331-stopping-with-kind-and-podman/incubator/013-signalstop/demo-signal.sh

Finally we define a workload with the following `pod-stopsignal-demo.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: stopsignal-demo
  labels:
    app: stopsignals
spec:
  automountServiceAccountToken: false
  containers:
  - name: main
    image: quay.io/avisied0/demos:stopsignal-demo
    imagePullPolicy: Always
    command:
    - /demo-signal.sh
    tty: true
    privileged: false
```

Build the image and push:

```sh
export IMG="quay.io/avisied0/demos:stopsignal-demo"
podman build -t "${IMG}" -f Dockerfile.stopsignal-demo .
podman push "${IMG}"
```

And we try the scenario by:

```sh
oc create -f pod-stopsignal-demo.yaml --as system:serviceaccount:stopsignal:runasanyuid
oc logs pod/stopsignal-demo -f --as system:serviceaccount:stopsignal:runasanyuid &
oc delete -f pod-stopsignal-demo.yaml --as system:serviceaccount:stopsignal:runasanyuid
```

Getting the output below:

```raw
pod "stopsignal-demo" deleted
............
Exiting by SIGINT
```

When the `SIGINT` is specified into the STOPSIGNAL instruction in the Dockerfile
Openshift is sending SIGINT signal to the pod when we delete the resource.

> When the `STOPSIGNAL 37` (`RTMIN+3`) is specified as a numeric value, Openshift
> is sending SIGTERM instead of the expected `SIGRTMIN+3` indicated into the
> Dockerfile file.

**Update**:

> Another test was made in Openshift 4.10 ci build on Wed Jan 5, 2022 and it worked
> as expected, by sending the `SIGRTMIN+3` to the container workload. So this will
> be fixed in future releases.

## Solution: container lifecycle hooks

- Create `pod-stopsignal-lifecycle.yaml` with the content below:

  ```yaml
  apiVersion: v1
  kind: Pod
  metadata:
    name: stopsignal-lifecycle
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

  - (1) The lifecycle hooks for that container.
  - (2) A `preStop` hook is called before stopping the container.
  - (3) It will be an `exec` command.
  - (4) The command to be executed; the executable must exist in the container.

- And we try again by:

  ```sh
  oc create -f pod-stopsignal-lifecycle.yaml --as=system:serviceaccount:stopsignal:runasanyuid
  oc logs pod/stopsignal-lifecycle -f --as=system:serviceaccount:stopsignal:runasanyuid &
  oc delete -f pod-stopsignal-lifecycle.yaml --as=system:serviceaccount:stopsignal:runasanyuid
  ```

And the log output immediately shows the below:

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

## Wrap up

In this article we have seen that:

- systemd workloads need `SIGRTMIN+3` for stopping the workload gracefully.
- OpenShift does not send the signal specified in the container
  image (via the `STOPSIGNAL` instruction). It does starting in Openshift 4.10.
- We can use a container lifecycle hook to
  interact with the workload when stopping the container until the fix is
  available. For this scenario, we can use the `kill` binary (which must exist in the
  container) to send `SIGRTMIN+3` to PID 1 (systemd).

**Updates**:

- The reason the STOPSINAL instruction is not interpreted in Openshift is
  because the signal name RTMIN+3 is not properly parsed. Actually there
  are a fix for this situation ([this PR](https://github.com/cri-o/cri-o/pull/5366)),
  that has been seen that will be included in OpenShift 4.10. Until this
  version is released, the solution above could make the works.

## References

- [How to run systemd in a container](https://developers.redhat.com/blog/2019/04/24/how-to-run-systemd-in-a-container?source=sso#other_cool_features_about_podman_and_systemd).
- [Systemd SIGRTMIN+3](https://www.freedesktop.org/software/systemd/man/systemd.html#SIGRTMIN+3).
- [Dockerfile - STOPSIGNAL](https://docs.docker.com/engine/reference/builder/#stopsignal).
- [Container Lifecycle Hooks](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/).
- [Attach Handlers to Container Lifecycle Events](https://kubernetes.io/docs/tasks/configure-pod-container/attach-handler-lifecycle-event/).
- **UPDATE**: [BZ 2000877](https://bugzilla.redhat.com/show_bug.cgi?id=2000877).
