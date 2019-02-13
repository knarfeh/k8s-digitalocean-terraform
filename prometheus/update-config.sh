#!/bin/bash
set -e
kubectl create configmap prometheus --from-file=config/ --dry-run -o yaml | kubectl replace configmap prometheus -f -