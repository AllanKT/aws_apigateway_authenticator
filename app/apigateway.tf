####################### HTTP API GATEWAY #####################

resource "aws_api_gateway_rest_api" "my_api" {
  name = "my-api"
  description = "My API Gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "root" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part = "api"
}


###### authorizer

data "aws_iam_policy_document" "invocation_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}


resource "aws_iam_role" "invocation_role" {
  name               = "api_gateway_auth_invocation"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.invocation_assume_role.json
}

resource "aws_api_gateway_authorizer" "my_authorizer" {
  name                   = "MyAuthorizer"
  rest_api_id            = aws_api_gateway_rest_api.my_api.id
  type                   = "TOKEN"
  authorizer_uri         = aws_lambda_function.lambda-visitorcounter.invoke_arn
  authorizer_credentials = aws_iam_role.invocation_role.arn

  identity_source = "method.request.header.jwt_token"
  authorizer_result_ttl_in_seconds = 0
}
