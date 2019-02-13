#!/bin/bash
kubectl create configmap grafana --from-file=config/ --dry-run -o yaml | kubectl replace configmap grafana -f -