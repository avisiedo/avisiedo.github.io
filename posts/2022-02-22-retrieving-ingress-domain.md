---
title: Retrieving the ingressDomain
categories:
  - kubernetes
tags:
  - kubernetes
  - ingress
  - openshift
published_date: "2022-02-22 12:45:41 +0100"
layout: default.liquid
is_draft: false
---
When we are publishing a service out of our OpenShift cluster, one option
is using a Route object. The `host` field is optional, and can be
used to customize the pattern to be matched when the HTTP request is sent
to our cluster, which is used to dispatch the request to the propper
Service resource. This is made by using a reverse proxy, in the case
of OpenShift, haproxy deployed by the ingress controller.

If we want to take advantage of the required DNS configuration that was used
when deploying the cluster (`*.apps.<basedomain>` but not always as we will
see now), we could want to retrieve this value to compose the value for this
field.

One approach could be to retrieve the base domain that is using our
OpenShift cluster by the command below:

```sh
oc get dnses.config.openshift.io/cluster -o jsonpath='{.spec.baseDomain}'
```

In CodeReadyContainers with the default configuration I get:

```raw
crc.testing
```

Now if we add the `apps.` suffix we get:

```raw
apps.crc.testing
```

Let's see what is the default value in CRC, so we start by creating a
namespace by:

```sh
oc new-project test-ingressdomain
```

Create a route resource by the below (we only want to see the default
`host` field):

```sh
oc create route passthrough my-route --service=frontend --port=https
```

> As the service does not exist, we need to specify the `--port=https` option.

And retrieving the route host by:

```sh
oc get route/my-route -o jsonpath='{.spec.host}'
```

We get:

```raw
my-route-test-ingressdomain.apps-crc.testing
```

which is slightly different from:

```raw
my-route-test-ingressdomain.apps.crc.testing
```

> See `apps-crc` vs `apps.crc` substring.

Then, how do we retrieve properly the value if we want to customize the `host`
field when publishing a service and taking advantage of the DNS resolution to
our cluster?

The response is to use the ingressDomain value instead of the baseDomain.

OpenShift comes with an ingress controller which manage the OpenShift Route
and the Kubernetes Ingress resources. From `oc explain IngressController` we
can read the below:

```raw
KIND:     IngressController
VERSION:  operator.openshift.io/v1

DESCRIPTION:
     IngressController describes a managed ingress controller for the cluster.
     The controller can service OpenShift Route and Kubernetes Ingress
     resources. When an IngressController is created, a new ingress controller
     deployment is created to allow external traffic to reach the services that
     expose Ingress or Route resources. Updating this resource may lead to
     disruption for public facing network connections as a new ingress
     controller revision may be rolled out.
     https://kubernetes.io/docs/concepts/services-networking/ingress-controllers
     Whenever possible, sensible defaults for the platform are used. See each
     field for more details.
```

Now this controller store the configuration into the `Ingress` resource for the
`config.openshift.io/v1` apiVersion and group (do not confuse this with the
`Ingress` resource from the `networking.k8s.io/v1` apiVersion and group). From
the `oc explain --api-version config.openshift.io/v1 ingresses` we can read:

```raw
KIND:     Ingress
VERSION:  config.openshift.io/v1

DESCRIPTION:
     Ingress holds cluster-wide information about ingress, including the default
     ingress domain used for routes. The canonical name is `cluster`.
     Compatibility level 1: Stable within a major release for a minimum of 12
     months or 3 minor releases (whichever is longer).
```

More specifically, we can retrieve the default ingress domain that is used to
compose the default `host` field into the Route objects by:

```sh
oc get ingresses.config/cluster -o jsonpath='{.spec.domain}'
```

From our CRC cluster we get the `apps-crc.testing`, which match the pattern
without any string manipulation, so it is more accurate.

## Bonus track

The above is correct for many situations, but from the documentation we can
read the below for
`oc explain --api-version='config.openshift.io/v1' ingresses.spec`:

```raw
FIELDS:
   appsDomain   <string>
     appsDomain is an optional domain to use instead of the one specified in the
     domain field when a Route is created without specifying an explicit host.
     If appsDomain is nonempty, this value is used to generate default host
     values for Route. Unlike domain, appsDomain may be modified after
     installation. This assumes a new ingresscontroller has been setup with a
     wildcard certificate.

...

   domain       <string>
     domain is used to generate a default host name for a route when the route's
     host name is empty. The generated host name will follow this pattern:
     "<route-name>.<route-namespace>.<domain>". It is also used as the default
     wildcard domain suffix for ingress. The default ingresscontroller domain
     will follow this pattern: "*.<domain>". Once set, changing domain is not
     currently supported.
```

So, when `appsDomain` is defined, it is used for composing the `host` field
into the Route resource by default. This provide the following:

- `domain` store the apps domain based on the DNS records that route the
  default traffic to the cluster.
- `appsDomain` provide an alternative to change how the default domain is
  generated as the `domain` field is immutable and can not be changed. But
  this could require additional DNS name resolution.
  (see [this](https://docs.openshift.com/container-platform/4.9/networking/ingress-operator.html#nw-ingress-controller-configuration-parameters_configuring-ingress)).

By the way, the above explained will works as it will be based into the
DNS registries required for creating an OpenShift cluster.
## Wrap up

To retrieve the value for the ingressDomain that match the DNS
records specified when creating the cluster, and take advantege
of them, we retrieve the value by:

```sh
oc get ingresses.config/cluster -o jsonpath='{.spec.domain}'
```

## References

- [Ingress Operator in OpenShift Container Platform](https://docs.openshift.com/container-platform/4.9/networking/ingress-operator.html).
- [dnsmasq template in CRC](https://github.com/code-ready/crc/blob/master/pkg/crc/services/dns/template.go#L11).
- [Constants for CRC domains](https://github.com/code-ready/crc/blob/master/pkg/crc/constants/constants.go#L40).
