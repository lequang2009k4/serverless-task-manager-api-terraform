# Serverless Task Manager API
This is a simple demo Task Management API built with Node.js 20.x and deployed on AWS using Terraform. The project utilizes several AWS core services including AWS Lambda,Congito, Amazon API Gateway, Amazon DynamoDB, Amazon CloudWatch, and AWS IAM
# 1. Getting Started
## Clone project
```
git clone https://github.com/lequang2009k4/serverless-task-manager-api-terraform.git
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
├── terraform/                   # Infrastructure as Code
│   ├── main.tf                  # Main configuration (Lambda, Gateway, DynamoDB)
│   ├── variables.tf             # Input variables
│   ├── outputs.tf               # Output values (ApiUrl)
│
├── package.json                 # Project dependencies and scripts
└── README.md                    # Project documentation & deployment guide
```

# 2. Deployment 
## 2.1. Initialize
```
cd terraform
terraform init
```
## 2.2. Plan (Optional)
```
terraform plan
```
## 2.3. Deploy
```
terraform apply
```
Key Configuration Notes:
* Confirm changes: Enter yes to confirm crud resource on aws
* State Management: Terraform have file terraform.tfstate to manage infrastructure (Don't remove it)

# 3. API Testing
Once deployment is complete, the **ApiUrl** will be displayed in the Outputs section. Use the following curl commands to test your endpoints:
|   API  | Command |
| ------------- |-------------|
|    POST /tasks  | `curl -X POST ApiUrl -H "Authorization: idToken" -H "Content-Type: application/json" -d '{"title": "You are deploy sucsess "}'`|
| GET /tasks      | `curl -X GET ApiUrl -H "Authorization: idToken" -H "Content-Type: application/json"`    |
| GET /tasks/{id}    | `curl -X GET ApiUrl/id -H "Authorization: idToken" -H "Content-Type: application/json"`    |
| DELETE /tasks/{id}  | `curl -X DELETE ApiUrl/id -H "Authorization: idToken" -H "Content-Type: application/json" `   |
