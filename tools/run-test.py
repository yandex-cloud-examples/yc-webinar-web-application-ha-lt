#!/usr/bin/env python3
import time
import uuid
import argparse
import json
import logging
import re
import pprint

import yandexcloud
from grpc import StatusCode
#from grpc._channel import _InactiveRpcError
#from yandex.cloud.loadtesting.api.v1.agent.agent_pb2 import Agent
#from yandex.cloud.loadtesting.api.v1.agent_service_pb2 import (
#    CreateAgentMetadata, DeleteAgentRequest, GetAgentRequest)
from yandex.cloud.loadtesting.api.v1.agent.status_pb2 import Status as AgentStatus
from yandex.cloud.loadtesting.api.v1.test.status_pb2 import Status as TestStatus
from yandex.cloud.loadtesting.api.v1.agent_service_pb2_grpc import \
    AgentServiceStub
from yandex.cloud.loadtesting.api.v1.config.config_pb2 import Config
from yandex.cloud.loadtesting.api.v1.config_service_pb2 import (
    CreateConfigMetadata, CreateConfigRequest)
from yandex.cloud.loadtesting.api.v1.config_service_pb2_grpc import \
    ConfigServiceStub
from yandex.cloud.loadtesting.api.v1.report_service_pb2 import (
    GetTableReportRequest, GetTableReportResponse)
from yandex.cloud.loadtesting.api.v1.report_service_pb2_grpc import \
    ReportServiceStub
from yandex.cloud.loadtesting.api.v1.test.agent_selector_pb2 import \
    AgentSelector
from yandex.cloud.loadtesting.api.v1.test.details_pb2 import Details
from yandex.cloud.loadtesting.api.v1.test.single_agent_configuration_pb2 import \
    SingleAgentConfiguration
from yandex.cloud.loadtesting.api.v1.test.test_pb2 import Test
from yandex.cloud.loadtesting.api.v1.test_service_pb2 import (
    CreateTestMetadata, CreateTestRequest, GetTestRequest)
from yandex.cloud.loadtesting.api.v1.test_service_pb2_grpc import \
    TestServiceStub


def wait_for_agent_to_be_ready(agent_stub, agent_id, timeout=15 * 60):
    request = GetAgentRequest(agent_id=agent_id)
    step = 10
    for seconds in range(1, timeout, step):
        agent: Agent = agent_stub.Get(request)
        if agent.status == AgentStatus.READY_FOR_TEST:
            break
        time.sleep(step)
    else:
        raise Exception(f'can\'t wait for agent to be ready anymore. Waited {seconds=}')

def parse_args():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawTextHelpFormatter)

    auth = parser.add_mutually_exclusive_group(required=True)
    auth.add_argument(
        '--sa-json-path',
        help='Path to the service account key JSON file.\nThis file can be created using YC CLI:\n'
             'yc iam key create --output sa.json --service-account-id <id>',
    )
    auth.add_argument('--iam-token', help='iam token')
    parser.add_argument('--folder-id', help='folder id', required=True)
    parser.add_argument('--config', help='load testing config', required=True)
    parser.add_argument('--agent-id', help='agent id', required=True)
    parser.add_argument('--test-name', default='load_test', help='name of the test')

    return parser.parse_args()

def run_test(sdk: yandexcloud.SDK, folder_id, agent_id, config, test_name):
    config_stub: ConfigServiceStub = sdk.client(ConfigServiceStub)
    create_config_operation = config_stub.Create(CreateConfigRequest(folder_id=folder_id, yaml_string=config))
    config_id = sdk.wait_operation_and_get_result(
        create_config_operation, 
        response_type=Config,  
        meta_type=CreateConfigMetadata, 
        timeout=60
    ).response.id
    
    create_test_request = CreateTestRequest(
        folder_id=folder_id,
        configurations=[SingleAgentConfiguration(config_id=config_id, agent_selector=AgentSelector(agent_id=agent_id))],
        test_details=Details(name=test_name),
    )

    test_stub: TestServiceStub = sdk.client(TestServiceStub)
    create_test_operation = test_stub.Create(create_test_request)
    test_id = sdk.wait_operation_and_get_result(
        create_test_operation, 
        response_type=Test, 
        meta_type=CreateTestMetadata, 
        timeout=60
    ).response.id

    get_test_request = GetTestRequest(test_id=test_id)
    for seconds in range(3 * 60):
        test: Test = test_stub.Get(get_test_request)
        if test.summary.status == TestStatus.RUNNING:
            break
        time.sleep(1)
    else:
        raise Exception(f'can\'t wait for test start anymore. Waited {seconds=}')

    return test_id

def main():
    logging.basicConfig(level=logging.INFO)
    arguments = parse_args()
    interceptor = yandexcloud.RetryInterceptor(max_retry_count=5, retriable_codes=[StatusCode.UNAVAILABLE])
    if arguments.iam_token:
        sdk = yandexcloud.SDK(interceptor=interceptor, iam_token=arguments.iam_token)
    else:
        with open(arguments.sa_json_path) as f:
            service_account_key = json.load(f)
        sdk = yandexcloud.SDK(interceptor=interceptor, service_account_key=service_account_key)
    with open(arguments.config) as f:
        config = f.read()
    test_id = run_test(sdk, arguments.folder_id, arguments.agent_id, config, arguments.test_name)
    print(f'{test_id}')


if __name__ == '__main__':
    main()

