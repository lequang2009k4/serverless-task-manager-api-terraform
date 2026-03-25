# --- 1. PROVIDER & DATA SOURCES ---
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws" # Specifies the official Hashicorp library
      version = "~> 5.0" # Uses version 5.x (avoids auto-upgrading to 6.0 to prevent compatibility issues)
    }
  }
}

provider "aws" {
  region = var.aws_region # Retrieves the region (e.g., ap-southeast-2) from variables.tf
}

data "archive_file" "lambda_bundle" {
  type        = "zip" # Compression format is .zip
  source_dir  = "${path.module}/" # Compresses the current root directory containing main.tf
  output_path = "${path.module}/lambda_bundle.zip" # Path where the zip file is created with a hash code. [If you edit one character in Node.js code -> Zip file changes -> Hash code changes.]
  
  excludes = [ # Do not include these files in the zip
    "main.tf", "variables.tf", "outputs.tf", "terraform.tfstate", 
    "terraform.tfstate.backup", ".terraform", ".terraform.lock.hcl", "lambda_bundle.zip"
  ]
}

# --- 2. COGNITO ---
resource "aws_cognito_user_pool" "main" {
  name                     = "MyTaskAppUsers-${var.env}"
  username_attributes      = ["email"] # Login via email instead of username
  auto_verified_attributes = ["email"] # Auto-send auth OTP
  password_policy { # Password rules
    minimum_length = 8
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name                = "MyTaskAppClient-${var.env}"
  user_pool_id        = aws_cognito_user_pool.main.id
  explicit_auth_flows = ["ADMIN_NO_SRP_AUTH", "USER_PASSWORD_AUTH"] # Login by sending direct us/pw || allows backend to authenticate users without complex encryption
}

# --- 3. DYNAMODB ---
resource "aws_dynamodb_table" "tasks" {
  name         = "MySimpleTasks-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key      = "id" # Partition Key
  attribute {
    name = "id"
    type = "S"
  }
  tags = { Environment = var.env } # Tagging for management
}

# --- 4. IAM ROLE & POLICY ---
# 1. Create a "Title" (Role)
resource "aws_iam_role" "lambda_exec" {
  name = "task_manager_lambda_role_${var.env}"
  # "Assume Role Policy": This is a statement: "I allow the Lambda service to borrow this title/role."
  assume_role_policy = jsonencode({ # Acts as a bridge to convert HCL to JSON 
    Version = "2012-10-17" # AWS Policy language version
    Statement = [{ # List of contract terms
      Action = "sts:AssumeRole" # Security Token Service. Allowed to be used to obtain a temporary access token.
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" } # Only AWS Lambda
    }]
  })
}

# 2. Write the "Job Description/Permissions" (Policy)
resource "aws_iam_role_policy" "lambda_common_policy" {
  name = "task_manager_policy_${var.env}"
  role = aws_iam_role.lambda_exec.id  # Attach this permission sheet to the Role above
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Permission Group 1: Data operations (DynamoDB)
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Scan"] # Does not allow table-level operations
        Effect   = "Allow"
        Resource = aws_dynamodb_table.tasks.arn # Can only touch the specific "tasks" store created
      },
      {
        # Permission Group 2: Logging (CloudWatch Logs)
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*" # Permission to write logs to AWS monitoring system | Every console.log() in Node.js will be pushed to a service called CloudWatch Logs
      }
    ]
  })
}

# --- 5. LAMBDA FUNCTIONS ---
locals { # Use locals to group common settings
  lambda_env = {
    variables = {
      TABLE_NAME = aws_dynamodb_table.tasks.name # Tells Lambda the DB table name
      NODE_ENV   = var.env # dev or prod
    }
  }
  runtime = "nodejs20.x"  # Using Node.js 20
}

resource "aws_lambda_function" "create_task" {
  function_name    = "CreateTask-${var.env}"
  handler          = "src/handlers/createTask.handler"
  runtime          = local.runtime
  role             = aws_iam_role.lambda_exec.arn # Wears the IAM Role "employee badge"
  filename         = data.archive_file.lambda_bundle.output_path 
  source_code_hash = data.archive_file.lambda_bundle.output_base64sha256 # If Terraform sees a new Hash different from the one on AWS -> It commands: "Update code immediately!".
  environment { variables = local.lambda_env.variables } # Passes environment variables; Terraform injects them, so your JS code doesn't need to know the table name: const tableName = process.env.TABLE_NAME
}

resource "aws_lambda_function" "get_all_tasks" {
  function_name    = "GetAllTasks-${var.env}"
  handler          = "src/handlers/getAllTasks.handler"
  runtime          = local.runtime
  role             = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.lambda_bundle.output_path
  source_code_hash = data.archive_file.lambda_bundle.output_base64sha256
  environment { variables = local.lambda_env.variables }
}

resource "aws_lambda_function" "get_task_by_id" {
  function_name    = "GetTaskById-${var.env}"
  handler          = "src/handlers/getTaskById.handler"
  runtime          = local.runtime
  role             = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.lambda_bundle.output_path
  source_code_hash = data.archive_file.lambda_bundle.output_base64sha256
  environment { variables = local.lambda_env.variables }
}

resource "aws_lambda_function" "delete_task" {
  function_name    = "DeleteTask-${var.env}"
  handler          = "src/handlers/deleteTask.handler"
  runtime          = local.runtime
  role             = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.lambda_bundle.output_path
  source_code_hash = data.archive_file.lambda_bundle.output_base64sha256
  environment { variables = local.lambda_env.variables }
}

# --- 6. API GATEWAY ---
# Receives guests (Endpoint), Checks badge (Authorizer), and Leads guests to the right room (Integration)
# API Gateway works in a Tree structure. Root is / -> /tasks is a child of Root -> {id} is a child of /tasks.
# 1. Create the API "Building"
resource "aws_api_gateway_rest_api" "main" {
  name = "TaskManagerAPI-${var.env}"
  endpoint_configuration {
    types = ["REGIONAL"] # Runs in the region closest to the user (e.g., Sydney)
  }
}

# 2. Badge Scanner (Connects to Cognito). It parses the Authorization Header (the JWT Token used in curl) and sends it to Cognito to verify.
resource "aws_api_gateway_authorizer" "cognito_auth" {
  name          = "CognitoAuthorizer"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.main.arn] # Uses User Pool from Part 2
}

# 3. Define the "Doors" (Resources)
resource "aws_api_gateway_resource" "tasks" { # tasks: Creates the path /tasks
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "tasks"
}

resource "aws_api_gateway_resource" "task_id" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.tasks.id
  path_part   = "{id}" # The curly braces {} are critical. It tells AWS this is a variable.
}

# --- 7. METHODS & INTEGRATIONS --- 
# Install "Doors" (Method) and "Pipes" (Integration)
# In Terraform, every action (GET, POST, DELETE) needs 2 matching components:
# + Method: Defines action type and security (Who is allowed in?).
# + Integration: Defines destination (Who are they meeting?).

# POST /tasks
resource "aws_api_gateway_method" "post_task" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.tasks.id # Attached to /tasks lobby
  http_method   = "POST" # POST Action
  authorization = "COGNITO_USER_POOLS" # Cognito badge required
  authorizer_id = aws_api_gateway_authorizer.cognito_auth.id  # Use created scanner
}

resource "aws_api_gateway_integration" "post_task_int" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.tasks.id
  http_method             = aws_api_gateway_method.post_task.http_method
  integration_http_method = "POST" # AWS Standard: Calling Lambda always uses POST [Clients may call API with GET/DELETE/PUT -> But when API Gateway "picks up the phone" to call Lambda, it always uses AWS internal POST protocol]
  type                    = "AWS_PROXY" # "Full Delegation" type
  uri                     = aws_lambda_function.create_task.invoke_arn # Leads to CreateTask function
}

# GET /tasks
resource "aws_api_gateway_method" "get_tasks" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.tasks.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_auth.id
}

resource "aws_api_gateway_integration" "get_tasks_int" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.tasks.id
  http_method             = aws_api_gateway_method.get_tasks.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_all_tasks.invoke_arn
}

# GET /tasks/{id}
resource "aws_api_gateway_method" "get_task_id" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.task_id.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_auth.id
}

resource "aws_api_gateway_integration" "get_task_id_int" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.task_id.id
  http_method             = aws_api_gateway_method.get_task_id.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_task_by_id.invoke_arn
}

# DELETE /tasks/{id}
resource "aws_api_gateway_method" "delete_task_id" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.task_id.id
  http_method   = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_auth.id
}

resource "aws_api_gateway_integration" "delete_task_id_int" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.task_id.id
  http_method             = aws_api_gateway_method.delete_task_id.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.delete_task.invoke_arn
}

# --- 8. LAMBDA PERMISSIONS ---
resource "aws_lambda_permission" "apigw_create" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_task.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_get_all" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_all_tasks.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_get_id" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_task_by_id.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_delete" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.delete_task.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# --- 9. DEPLOYMENT & STAGE (FIXED FOR CACHE ISSUES) ---
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  # Ensures Deployment only occurs after all Integrations are complete
  depends_on = [
    aws_api_gateway_integration.post_task_int,
    aws_api_gateway_integration.get_tasks_int,
    aws_api_gateway_integration.get_task_id_int,
    aws_api_gateway_integration.delete_task_id_int
  ]

  # Force update trigger: Hashes the list of integrations and authorizers
  # If any ID in this list changes, the API will be redeployed immediately.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.tasks.id,
      aws_api_gateway_resource.task_id.id,
      aws_api_gateway_method.post_task.id,
      aws_api_gateway_authorizer.cognito_auth.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.env
}
