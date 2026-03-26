# --- 1. PROVIDER & DATA SOURCES ---
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws" # Specifies using the official library from Hashicorp
      version = "~> 5.0" # Uses version 5.x (prevents auto-upgrading to 6.0 to avoid compatibility issues)
    }
  }
}

provider "aws" {
  region = var.aws_region # Retrieves the region (e.g., ap-southeast-2) from variables.tf
}

data "archive_file" "lambda_bundle" {
  type        = "zip" # Compression format is .zip
  source_dir  = "${path.module}/../" # Compresses the entire current directory (root) containing main.tf
  output_path = "${path.module}/../lambda_bundle.zip" # Path where the zip file is created with a hash code. [If you edit one character in Node.js code -> Zip file changes -> Hash code changes.]
  
  excludes = [ # Do not include these files in the zip
    "terraform", ".terraform", "terraform.tfstate", "terraform.tfstate.backup", ".terraform.lock.hcl", "lambda_bundle.zip", ".git", ".gitignore", "README.md",
    ".DS_Store", "package-lock.json"
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
  explicit_auth_flows = ["ADMIN_NO_SRP_AUTH", "USER_PASSWORD_AUTH"] # Login by sending direct US/PW || allows backend to authenticate users without complex encryption
}

# --- 3. DYNAMODB ---
resource "aws_dynamodb_table" "tasks" {
  name         = "MySimpleTasks-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id" # Partition Key
  attribute {
    name = "id"
    type = "S"
  }
  tags = { Environment = var.env } # Tags for management
}

# --- 4. IAM ROLE & POLICY ---
# 1. Create a "Title" (Role) due to AWS Zero Trust
resource "aws_iam_role" "lambda_exec" {
  name = "task_manager_lambda_role_${var.env}"
  # "Assume Role Policy": This is a declaration: "I allow the Lambda service to borrow this title/role."
  assume_role_policy = jsonencode({ # Acts as a bridge, converting HCL to JSON 
    Version = "2012-10-17" # AWS Policy language version
    Statement = [{ # List of contract terms/statements
      Action = "sts:AssumeRole" # Security Token Service. Allowed to be used to obtain a temporary access token.
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" } # Only AWS Lambda
    }]
  })
}

# 2. Write the "Permission Description" (Policy)
resource "aws_iam_role_policy" "lambda_common_policy" {
  name = "task_manager_policy_${var.env}"
  role = aws_iam_role.lambda_exec.id  # Attach this permission board to the Role above
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Permission Group 1: Data operations (DynamoDB)
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Scan"] # No table manipulation (Drop/Create) allowed
        Effect   = "Allow"
        Resource = aws_dynamodb_table.tasks.arn # Can only touch the specific "tasks" store created
      },
      {
        # Permission Group 2: Logging (CloudWatch Logs)
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*" # Permission to write logs to AWS monitoring system | Every console.log() in Node.js will be pushed to CloudWatch Logs
      }
    ]
  })
}

# --- 5. LAMBDA FUNCTIONS ---
locals { # Use locals for grouping
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
  role             = aws_iam_role.lambda_exec.arn # Wear the IAM Role "ID Badge"
  filename         = data.archive_file.lambda_bundle.output_path 
  source_code_hash = data.archive_file.lambda_bundle.output_base64sha256 # Terraform sees a new Hash different from the one on AWS -> It commands: "Update code now!".
  environment { variables = local.lambda_env.variables } # Passes env vars; Terraform handles it so your JS code doesn't need to hardcode the table name: const tableName = process.env.TABLE_NAME
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
# Receives guests (Endpoint), Checks IDs (Authorizer), and Leads guests to the right room (Integration)
# Structure: https://[API_ID].execute-api.[REGION].amazonaws.com/[STAGE]/[RESOURCE] 
# In a real project, you would use Route 53 to "mask" this with a pretty domain name.
# API ID: Unique ID assigned by AWS to your aws_api_gateway_rest_api.main.
# execute-api: AWS service name specifically for invoking API Gateways.
# Region (e.g., ap-southeast-2): Physical area where your API "server" is located.
# Root Domain: Root domain for all AWS cloud services.
# Stage (e.g., dev): The deployment environment.
# Resource Path (e.g., tasks): The sub-path declared in Section 6.

# Terraform Link: In your code, there is ${var.env}. When you deploy with env = "dev", Terraform creates a Stage named dev.
# API Gateway works in a Tree structure. Root is / -> /tasks is a child of Root -> {id} is a child of /tasks.

# 1. Create the API Building
resource "aws_api_gateway_rest_api" "main" {
  name = "TaskManagerAPI-${var.env}"
  endpoint_configuration {
    types = ["REGIONAL"] # Runs in the region closest to users (e.g., Sydney)
  }
}

# 2. Card Scanner (Connect to Cognito). It extracts the Authorization Header (the JWT Token used in curl) and sends it to Cognito to verify.
resource "aws_api_gateway_authorizer" "cognito_auth" {
  name          = "CognitoAuthorizer"
  rest_api_id   = aws_api_gateway_rest_api.main.id 
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.main.arn] # Uses User Pool from Section 2
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
  path_part   = "{id}" # Curly braces {} are vital. They tell AWS this is a variable.
}

# --- 7. METHODS & INTEGRATIONS --- 
# Install "Doors" (Method) and "Pipes" (Integration)
# In Terraform, every action (GET, POST, DELETE) needs 2 components:
# + Method: Defines action type and security (Who can enter?).
# + Integration: Defines destination (Who to meet?).

# POST /tasks
resource "aws_api_gateway_method" "post_task" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.tasks.id # Attached to /tasks hall
  http_method   = "POST" # POST action
  authorization = "COGNITO_USER_POOLS" # Cognito ID required
  authorizer_id = aws_api_gateway_authorizer.cognito_auth.id  # Uses created card scanner
}

resource "aws_api_gateway_integration" "post_task_int" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.tasks.id
  http_method             = aws_api_gateway_method.post_task.http_method
  integration_http_method = "POST" # AWS Standard: Calling Lambda always uses POST [Clients can call API via GET/DELETE/PUT -> but when API Gateway calls Lambda, it uses AWS internal POST protocol]
  type                    = "AWS_PROXY" # "Full Proxy" mode -> "Express delivery", API Gateway won't interfere with data. It bundles Header, Body, Query Params... into an Event and throws it to Lambda.
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
# Allows API Gateway the right to trigger Lambda
resource "aws_lambda_permission" "apigw_create" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_task.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_get_all" {
  action        = "lambda:InvokeFunction" # Action: Allows "Triggering" the function
  function_name = aws_lambda_function.get_all_tasks.function_name
  principal     = "apigateway.amazonaws.com" # Trusted client object
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*" # Filter funnel. The identifier address of the API you just created.
# /*/*: These wildcards mean allow all Stages (dev/prod) and all Methods (POST/GET) of the API
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

# --- 9. DEPLOYMENT & STAGE ---
resource "aws_api_gateway_deployment" "main" { # The "Publish" button
  rest_api_id = aws_api_gateway_rest_api.main.id

  # Ensure Deployment only happens after all Integrations are complete
  depends_on = [
    aws_api_gateway_integration.post_task_int,
    aws_api_gateway_integration.get_tasks_int,
    aws_api_gateway_integration.get_task_id_int,
    aws_api_gateway_integration.delete_task_id_int
  ]
  
  # AWS API Gateway is "lazy" with updates; changing a Method name or security type requires a redeploy.
  # Forced Update Trigger: Hashes the list of integrations and authorizers.
  # If any ID in here changes, the API is redeployed immediately.
  triggers = { # A list of values; if any value changes from the previous run, Terraform understands: "The old Deployment is outdated, I must create a new Deployment (new Snapshot) immediately."
    redeployment = sha1(jsonencode([ # Bundles all monitored configs into a JSON string -> Turns that long string into a unique code (e.g., af32b...).
      # If you edit even a comma in the API config, this sha1 code will jump to a completely different number (e.g., 87cc2...). Then, trigger changes -> Terraform triggers new Deployment.
      
      # 1. Monitor Path configurations
      aws_api_gateway_resource.tasks,
      
      # 2. Monitor Method details (e.g., changing Authorization = "NONE" changes the Hash)
      aws_api_gateway_method.post_task,
      
      # 3. Monitor "Pipes" (Integration) (e.g., changing Lambda Function changes the Hash)
      aws_api_gateway_integration.post_task_int,
      
      # 4. Monitor Security configurations
      aws_api_gateway_authorizer.cognito_auth,
      
      # 5. (Advanced tip) Monitor the Hash of the Lambda code itself
      data.archive_file.lambda_bundle.output_base64sha256
    ]))
  }

  lifecycle { # "Zero Downtime" technique
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "main" { # Environment label
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.env
}
