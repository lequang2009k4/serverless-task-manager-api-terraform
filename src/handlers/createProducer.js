import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs";
import { clientError, serverError } from "../utils/response.js";
import { validator } from "../utils/validator.js";
import crypto from "crypto"; 

const sqsClient = new SQSClient({});

export const handler = async (event, context) => {
    const logContext = {
        awsRequestId: context.awsRequestId,
        path: event.path,
        httpMethod: event.httpMethod
    };

    try {
        if (!event.body) return clientError("Input data cannot be empty.", logContext);
        
        const payload = JSON.parse(event.body);
        
        // Validation
        const validation = validator.validateCreateTask(payload);
        if (!validation.isValid) return clientError(validation.errors, logContext);
        
        // Gen task ID to response for  Client
        payload.id = payload.id || crypto.randomUUID();
        const queueUrl = process.env.CREATE_TASK_QUEUE_URL;

        // send to sqs
        const result = await sqsClient.send(new SendMessageCommand({
            QueueUrl: queueUrl,
            MessageBody: JSON.stringify(payload)
        }));

        console.info(`[CREATE-PRODUCER] Message sent to SQS. ID: ${result.MessageId}`);

        return {
            statusCode: 202,
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                message: "Create request accepted and is being processed.",
                taskId: payload.id,
                trackingId: result.MessageId
            })
        };
    } catch (error) {
        return serverError(error, logContext);
    }
};
