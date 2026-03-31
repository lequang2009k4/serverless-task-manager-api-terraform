import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs"; // Object used to connect to AWS SQS service
import { clientError, serverError } from "../utils/response.js";
import { validator } from "../utils/validator.js";
import crypto from "crypto"; // Standard Node.js library used to generate random ID strings

const sqsClient = new SQSClient({});

export const handler = async (event, context) => {
    const logContext = {
        awsRequestId: context.awsRequestId,
        path: event.path,
        httpMethod: event.httpMethod
    };

    try {
        const method = event.httpMethod;
        let payload = {};
        let queueUrl = "";

        // 1. Categorize request based on HTTP Method
        if (method === "POST") {
            if (!event.body) return clientError("Input data cannot be empty.", logContext);
            payload = JSON.parse(event.body);
            
            // Validation at the Producer to block junk data from entering the Queue
            const validation = validator.validateCreateTask(payload);
            if (!validation.isValid) return clientError(validation.errors, logContext);
            
            // Generate ID early to return to Client for tracking
            payload.id = payload.id || crypto.randomUUID();
            queueUrl = process.env.CREATE_TASK_QUEUE_URL;
        } 
        else if (method === "DELETE") {
            const id = event.pathParameters?.id;
            if (!id) return clientError("Task ID is required.", logContext);
            
            payload = { id };
            queueUrl = process.env.DELETE_TASK_QUEUE_URL;
        }

        // 2. Send message to SQS (Async Processing)
        const result = await sqsClient.send(new SendMessageCommand({
            QueueUrl: queueUrl,
            MessageBody: JSON.stringify(payload) // Task data is converted from Object to JSON string (SQS only accepts text strings).
        }));

        console.info(`[PRODUCER] Message sent to SQS. ID: ${result.MessageId}`);

        // 3. Return 202 Accepted with taskId
        return {
            statusCode: 202,
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                message: "Request accepted and is being processed.",
                taskId: payload.id, // ID in DynamoDB
                trackingId: result.MessageId // This is the SQS message ID, used to cross-reference (correlation) between Producer and Consumer logs when troubleshooting.
            })
        };

    } catch (error) {
        return serverError(error, logContext);
    }
};
