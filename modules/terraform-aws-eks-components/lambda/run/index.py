import time

import boto3


def lambda_handler(event, context):
    cluster = event["cluster"]
    task_definition = event["task_definition"]
    subnets = event["subnets"]
    security_groups = event["security_groups"]
    poll_seconds = int(event.get("poll_seconds", 15))

    ecs = boto3.client("ecs")

    response = ecs.run_task(
        cluster=cluster,
        taskDefinition=task_definition,
        launchType="FARGATE",
        platformVersion="LATEST",
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": subnets,
                "securityGroups": security_groups,
                "assignPublicIp": "DISABLED",
            }
        },
    )
    failures = response.get("failures") or []
    if failures:
        raise RuntimeError(f"ecs run-task failed: {failures}")

    tasks = response.get("tasks") or []
    if not tasks:
        raise RuntimeError("ecs run-task returned no tasks")

    task_arn = tasks[0]["taskArn"]

    status = ""
    remaining = context.get_remaining_time_in_millis() / 1000.0
    deadline = time.time() + max(30.0, remaining - 30.0)

    while time.time() < deadline:
        status = _describe(ecs, cluster, task_arn)["lastStatus"]
        if status == "STOPPED":
            break
        time.sleep(poll_seconds)

    if status != "STOPPED":
        return {
            "status": "running",
            "task_arn": task_arn,
            "exit_code": None,
            "stopped_reason": None,
        }

    task = _describe(ecs, cluster, task_arn)
    containers = task.get("containers") or [{}]
    exit_code = containers[0].get("exitCode")
    reason = task.get("stoppedReason")

    if exit_code != 0:
        raise RuntimeError(
            f"task failed exitCode={exit_code} stoppedReason={reason} arn={task_arn}"
        )

    return {
        "status": "ok",
        "task_arn": task_arn,
        "exit_code": exit_code,
        "stopped_reason": reason,
    }


def _describe(ecs, cluster, task_arn):
    described = ecs.describe_tasks(cluster=cluster, tasks=[task_arn])
    tasks = described.get("tasks") or []
    if not tasks:
        raise RuntimeError(f"ecs describe-tasks returned no task: {task_arn}")
    return tasks[0]
