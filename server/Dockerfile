# Single-stage: pure Python, no vendored Node subprocess (unlike
# daily-tech-brief-bedrock's dual-runtime image) -- this server is a native
# FastMCP/Mangum handler, not a stdio wrapper around a JS MCP server.
FROM public.ecr.aws/lambda/python:3.13

COPY server/requirements.txt ${LAMBDA_TASK_ROOT}/requirements.txt
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt

COPY server/ ${LAMBDA_TASK_ROOT}/

# COPY preserves source file modes; make everything world-readable so
# Lambda's non-root execution user can read it regardless of host perms.
RUN chmod -R a+rX ${LAMBDA_TASK_ROOT}

CMD ["handler.lambda_handler"]
