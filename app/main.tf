provider "aws" {
    region = var.aws_region
    access_key = var.aws_access_key
    secret_key = var.aws_secret_key
    token = var.aws_session_token
}

################################## LAMBDA #############################


#archive file
data "archive_file" "zip-python" {
  type        = "zip"
  source_file = "index.py"
  output_path = "index.zip"
}

#upload archive to s3 
resource "aws_s3_object" "lambda-in-s3" {
  bucket = "app-api-lambda-counter"
  key    = "index.zip"
  source = data.archive_file.zip-python.output_path
  etag = filemd5(data.archive_file.zip-python.output_path)
}



resource "aws_lambda_function" "lambda-visitorcounter" {
  function_name = "visitor-counter"

  s3_bucket = "app-api-lambda-counter"
  s3_key    = aws_s3_object.lambda-in-s3.key

  runtime = "python3.9"
  handler = "index.lambda_handler"

  #source_code_hash attribute will change whenever you update the code contained in the archive, which lets Lambda know that there is a new version of your code available.
  source_code_hash = data.archive_file.zip-python.output_base64sha256

  # a role which grants the function permission to access AWS services and resources in your account.
  role = aws_iam_role.lambda_exec.arn
}

#defines a log group to store log messages from your Lambda function for 30 days. By convention, Lambda stores logs in a group with the name /aws/lambda/<Function Name>.
resource "aws_cloudwatch_log_group" "lambda-visitorcounter" {
  name = "/aws/lambda/${aws_lambda_function.lambda-visitorcounter.function_name}"

  retention_in_days = 30
}

#defines an IAM role that allows Lambda to access resources in your AWS account.
resource "aws_iam_role" "lambda_exec" {
  name = "serverless_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

#attaches a policy to the IAM role. The AWSLambdaBasicExecutionRole is an AWS managed policy that allows your Lambda function to write to CloudWatch logs.
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "lambda_dynamoroles" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}



  ###################### DYNAMO D B #####################

resource "aws_dynamodb_table" "dynamo-visitorcounter" {
  name         = "db-visit-count"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "user"

  attribute {
    name = "user"
    type = "S"
  }

}


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

###### routes

resource "aws_api_gateway_method" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.my_authorizer.id
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.proxy.http_method
  integration_http_method = "GET"
  type                    = "HTTP_PROXY"
  uri                     = "https://pokeapi.co/api/v2/pokemon/ditto"
}

resource "aws_api_gateway_method_response" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = "200"

  //cors section
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = aws_api_gateway_method_response.proxy.status_code

  # //cors
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" =  "'Content-Type,jwt_token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,DELETE,PUT'",
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [
    aws_api_gateway_method.proxy,
    aws_api_gateway_integration.integration
  ]
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.integration,
    # aws_api_gateway_integration.options_integration, # Add this line
  ]

  rest_api_id = aws_api_gateway_rest_api.my_api.id
  stage_name = "dev"
}

resource "aws_lambda_permission" "apigateway_invoke_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda-visitorcounter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.my_api.execution_arn}/authorizers/${aws_api_gateway_authorizer.my_authorizer.id}"
}
