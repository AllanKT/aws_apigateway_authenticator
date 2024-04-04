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
