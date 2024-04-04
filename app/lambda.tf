################################## LAMBDA #############################


#archive file
data "archive_file" "zip-python" {
  type        = "zip"
  source_file = "code/index.py"
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
