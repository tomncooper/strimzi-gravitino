#!/bin/bash
kubectl get secret gravitino-minio-credentials -n metadata -o json | \
  jq 'del(.metadata.namespace, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp)' | \
  jq '.metadata.name = "minio-credentials"' | \
  jq '.metadata.namespace = "product-recommendation"' | \
  kubectl apply -f -
