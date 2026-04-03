import { taskService } from "../services/taskService.js";

export const handler = async (event) => {
    // SQS sends data as an array of Records 
    for (const record of event.Records) {
        try {
            const data = JSON.parse(record.body);
          
   
            // Logging both MessageId (Infrastructure) and TaskId (Business) for tracing
            console.log(`[CONSUMER-CREATE] MessageId: ${record.messageId} | Processing task: ${data.id}`);

            // Call the existing Business logic from the service
            await taskService.createNewTask(data);

            console.info(`[SUCCESS] Task ${data.id} saved to DynamoDB.`);
        } catch (error) {
            console.error("[RETRY TRIGGERED] Create failed:", error.message);
            
            // THROW ERROR here so SQS recognizes the failure and triggers an automatic RETRY (Task 3)
            throw error; 
        }
    }
};
