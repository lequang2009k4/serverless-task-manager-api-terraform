import { taskService } from "../services/taskService.js";

export const handler = async (event) => {
    // SQS sends data as an array of Records (based on your batch_size)
    for (const record of event.Records) {
        try {
            const data = JSON.parse(record.body);
           
            // Logging both MessageId (SQS tracking) and TaskId (DynamoDB ID)
            console.log(`[CONSUMER-DELETE] MessageId: ${record.messageId} | Deleting task: ${data.id}`);
            throw new Error("Simulated Database Timeout Error");
            // Call the delete logic from the service layer
            await taskService.removeTask(data.id);

            console.info(`[SUCCESS] Task ${data.id} removed from DynamoDB.`);
        } catch (error) {
            // Logic: If the task is already gone (404), we don't need to Retry.
            // In Async systems, this is called "Idempotency" support.
            if (error.message.includes("Not found")) {
                console.warn(`[SKIP] Task ${data.id} not found, skipping retry.`);
                // We return (don't throw) so SQS considers this record "Processed" and deletes it.
                return; 
            }

            console.error("[RETRY TRIGGERED] Delete failed:", error.message);
            // THROW ERROR here for system-level issues (like DB Timeout) to trigger SQS Retry
            throw error; 
        }
    }
};
