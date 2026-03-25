# Serverless Task Manager API
This is a simple demo Task Management API built with Node.js 20.x and deployed on AWS using the Serverless Application Model (SAM). The project utilizes several AWS core services including AWS Lambda, Amazon API Gateway, Amazon DynamoDB, Amazon CloudWatch, and AWS IAM.
# 1. Getting Started
## Clone project
```
git clone https://github.com/lequang2009k4/serverless-task-manager-api.git
cd serverless-task-manager-api
```
## Project Structure
```
serverless-task-manager-api/
├── src/
│   ├── handlers/                # Lambda Entry Points 
│   │   ├── createTask.js        
│   │   ├── getAllTasks.js
│   │   ├── getTaskById.js
│   │   └── deleteTask.js
│   │
│   ├── services/                # Business Logic Layer
│   │   └── taskService.js       
│   │
│   ├── repositories/            # Data Access Layer
│   │   └── taskRepository.js    
│   │
│   ├── models/                  # Data Models 
│   │   └── taskModel.js         
│   │
│   ├── utils/                   # Shared Utilities & Helpers
│   │   ├── response.js          # Standardizes API responses 
│   │   └── validator.js         # Input validation logic
│   │
│   └── config/                  # Configuration & Clients
│       └── dynamoClient.js      # AWS SDK DynamoDB client initialization
│
├── tests/
│   └── units/                   # Unit Testing
│       └── handlers/            # Tests for Lambda entry points
│           ├── createTask.test.js
│           ├── getAllTasks.test.js
│           ├── getTaskById.test.js
│           └── deleteTask.test.js
│
├── infrastructure/              # Infrastructure as Code (IaC)
│   └── template.yaml            # AWS SAM template
│
├── package.json                 # Project dependencies and scripts
└── README.md                    # Project documentation & deployment guide
```

# 2. Deployment with AWS SAM
## 2.1. Build: `sam build -t infrastructure/template.yaml`
## 2.2. Deploy
### First Time: `sam deploy --guided`
Key Configuration Options:
* Stack Name & Region: Define your preferred stack name and AWS region.
* Confirm changes before deploy [Y/n]: Choose Y. SAM will list the 4 Lambda functions and 1 DynamoDB table for final verification.
* Allow SAM CLI IAM role creation [Y/n]: Choose Y. This grants Lambda permissions to interact with DynamoDB. Choosing N will result in 500 Internal Server Error.
* Disable rollback [y/N]: Choose N. This ensures AWS rolls back to a clean state if the deployment fails.
* Authorization Warning: Since this demo does not include an Auth layer (e.g., Cognito), SAM will warn you for each function. Choose Y to proceed for demo purposes.
* Save arguments to configuration file [Y/n]: Choose Y to save these settings to samconfig.toml for future use.
### Subsequent Deployments: `sam deploy`
# 3. API Testing
Once deployment is complete, the **ApiUrl** will be displayed in the Outputs section. Use the following curl commands to test your endpoints:
|   API  | Command |
| ------------- |-------------|
|    POST /tasks  | `curl -X POST ApiUrl -H "Content-Type: application/json" -d '{"title": "You are deploy sucsess "}'`|
| GET /tasks      | `curl -X GET ApiUrl`    |
| GET /tasks/{id}    | `curl -X GET ApiUrl/id`    |
| DELETE /tasks/{id}  | `curl -X DELETE ApiUrl/id `   |
