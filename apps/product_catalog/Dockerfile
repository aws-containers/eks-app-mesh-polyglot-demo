# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# Use an official Python runtime as an image
FROM python:3

RUN mkdir /app
WORKDIR /app

# We copy just the requirements.txt first to leverage Docker cache
COPY requirements.txt /app
RUN pip install -r requirements.txt

COPY . /app

# ENV AGG_APP_URL='http://prodinfo.octank-mesh-ns.svc.cluster.local:3000/productAgreement'

#WORKDIR /docker_app
EXPOSE 8080
ENTRYPOINT ["/app/bootstrap.sh"]