import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs";
import { clientError, serverError } from "../utils/response.js";

const sqsClient = new SQSClient({});

export const handler = async (event, context) => {
    const logContext = {
        awsRequestId: context.awsRequestId,
        path: event.path,
        httpMethod: event.httpMethod
    };

    try {
        const id = event.pathParameters?.id;
        if (!id) return clientError("Task ID is required.", logContext);
        
        const payload = { id };
        const queueUrl = process.env.DELETE_TASK_QUEUE_URL;

        // Send to sqs
        const result = await sqsClient.send(new SendMessageCommand({
            QueueUrl: queueUrl,
            MessageBody: JSON.stringify(payload)
        }));

        console.info(`[DELETE-PRODUCER] Message sent to SQS. ID: ${result.MessageId}`);

        return {
            statusCode: 202,
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                message: "Delete request accepted and is being processed.",
                taskId: id,
                trackingId: result.MessageId
            })
        };
    } catch (error) {
        return serverError(error, logContext);
    }
};
