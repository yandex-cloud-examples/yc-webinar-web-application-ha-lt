FROM hashicorp/terraform:light as terraform

FROM alpine:3.18 as base

ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV PYTHONPATH /opt/lib/python3.11/site-packages
ENV PATH "${PATH}:/opt/bin"

RUN set -x \
    && apk add -q --no-cache curl python3 py3-setuptools \
    && adduser -D devops \
    && :

FROM base as build

COPY --from=terraform /bin/terraform /opt/bin/terraform
COPY wait-for-app.sh /opt/bin/
COPY run-test.py /opt/bin/
COPY requirements.txt /tmp/

RUN set -x \
    && apk add -q --no-cache bash jq gettext py3-pip \
    && curl -f -s -L "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o /opt/bin/kubectl \
    && chmod +x /opt/bin/kubectl \
    && curl -f -s -L https://storage.yandexcloud.net/yandexcloud-yc/install.sh -o /tmp/install.sh \
    && bash /tmp/install.sh -i /opt/yandex-cloud -n \
    && ln -s /opt/yandex-cloud/bin/yc /opt/bin/yc \
    && chmod +x /opt/bin/wait-for-app.sh \
    && python3 -m pip install --prefix /opt/ -r /tmp/requirements.txt \
    && chmod +x /opt/bin/run-test.py \
    && :

FROM base

COPY --from=build /opt/ /opt/

USER devops
#    - yc config profile create sa-profile
#    - yc config set service-account-key key.json
#    - yc managed-kubernetes cluster get-credentials --id $cluster_id --external --kubeconfig kube_$CP_CLUSTER_NAME --force 

