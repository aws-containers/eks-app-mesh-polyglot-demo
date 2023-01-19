# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# Use an official Python runtime as an image
FROM python:3.9-slim

RUN apt-get update \
    && apt-get install curl -y \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir /app
WORKDIR /app

# We copy just the requirements.txt first to leverage Docker cache
COPY requirements.txt /app
RUN pip install -r requirements.txt

RUN opentelemetry-bootstrap --action=install

COPY . /app

# ENV AGG_APP_URL='http://prodinfo.octank-mesh-ns.svc.cluster.local:3000/productAgreement'

#WORKDIR /docker_app
EXPOSE 8080
CMD opentelemetry-instrument \
    # --traces_exporter=console \
    --log_level=debug \
    # --logs_exporter=console \
    # --metrics_exporter=none \
    python3 -m flask run -h 0.0.0.0